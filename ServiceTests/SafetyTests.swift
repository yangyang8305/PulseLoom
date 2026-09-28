import XCTest
import CoreHaptics
import PulseLoomCore
@testable import PulseLoom

private enum InjectedFailure: Error { case stop, cancelled }
@MainActor private final class PlayerProbe: HapticPlayerIO {
    var completionHandler: ((Error?) -> Void)?
    var loopEnabled = false
    var loopEnd = 0.0
    var failStop = false
    var stops = 0
    var starts = 0
    func start(atTime: TimeInterval) throws { starts += 1 }
    func stop(atTime: TimeInterval) throws {
        stops += 1
        if failStop { throw InjectedFailure.stop }
    }
    func sendParameters(_ parameters: [CHHapticDynamicParameter], atTime: TimeInterval) throws {}
}
@MainActor private final class EngineProbe: HapticEngineIO {
    var stoppedHandler: ((CHHapticEngine.StoppedReason) -> Void)?
    var resetHandler: (() -> Void)?
    var isMutedForHaptics = false
    var starts = 0
    var stops = 0
    var completion: ((Error?) -> Void)?
    let player = PlayerProbe()
    func start() throws { starts += 1 }
    func stop(completion: @escaping (Error?) -> Void) { stops += 1; self.completion = completion }
    func makeAdvancedPlayer(with pattern: CHHapticPattern) throws -> any HapticPlayerIO { player }
}

@MainActor final class HapticSafetyTests: XCTestCase {
    func testAUD01StopFailureTerminatesEngineAndBlocksRestart() throws {
        let engine = EngineProbe()
        let driver = HapticDriver(makeEngine: { engine }, supportsHaptics: { true }, isForeground: { true }, thermalSafe: { true })
        try driver.stream(intensity: 0.5, sharpness: 0.2)
        engine.player.failStop = true
        driver.stop()
        XCTAssertEqual(engine.stops, 1, "AUD-01: failed player.stop must fall back to engine shutdown")
        XCTAssertTrue(engine.isMutedForHaptics, "AUD-01: mute while shutdown is unconfirmed")
        XCTAssertThrowsError(try driver.prepare(), "AUD-01: restarting before stop confirmation is unsafe")
    }
    func testNormalStopKeepsReusableEngine() throws {
        let engine = EngineProbe()
        let driver = HapticDriver(makeEngine: { engine }, supportsHaptics: { true }, isForeground: { true }, thermalSafe: { true })
        try driver.stream(intensity: 0.5, sharpness: 0.2)
        driver.stop()
        XCTAssertEqual(engine.player.stops, 1)
        XCTAssertEqual(engine.stops, 0)
        XCTAssertNoThrow(try driver.stream(intensity: 0.4, sharpness: 0.2))
    }
}

/// All continuations are explicitly released; waits assert observable suspension rather than accepting timeouts.
@MainActor private final class MusicProbe {
    var subscriptionGate: CheckedContinuation<Bool, Error>?
    var playGate: CheckedContinuation<Void, Error>?
    var delaySubscription = true
    var delayPlay = false
    var starts = 0
    var pauses = 0
    var io: SystemMusicIO {
        SystemMusicIO(
            subscription: {
                if self.delaySubscription { return try await withCheckedThrowingContinuation { self.subscriptionGate = $0 } }
                return true
            },
            play: { _ in
                self.starts += 1
                if self.delayPlay { try await withCheckedThrowingContinuation { self.playGate = $0 } }
            },
            pause: { self.pauses += 1 }, enabled: { true }, foreground: { true },
            trackAvailable: { _ in true }, playbackTime: { 0 })
    }
}
@MainActor final class SystemMusicSafetyTests: XCTestCase {
    private func wait(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Dependency did not reach its controlled suspension point")
    }
    func testAUD02StopCancelsPendingSubscription() async throws {
        let probe = MusicProbe(); let service = SystemMusicService(io: probe.io)
        await service.choose(SystemMusicTrack(id: "one", title: "fixture one"))
        let request = Task { try await service.play() }
        await wait { probe.subscriptionGate != nil }
        service.pause()
        probe.subscriptionGate?.resume(returning: true); probe.subscriptionGate = nil
        try await request.value
        XCTAssertEqual(probe.starts, 0, "AUD-02: a cancelled request must never acquire playback")
        XCTAssertFalse(service.playing)
    }
    func testAUD02StopDuringPlayerStartDoesNotResurrectPlayback() async throws {
        let probe = MusicProbe(); probe.delaySubscription = false; probe.delayPlay = true
        let service = SystemMusicService(io: probe.io)
        await service.choose(SystemMusicTrack(id: "one", title: "fixture one"))
        let request = Task { try await service.play() }
        await wait { probe.playGate != nil }
        service.pause()
        probe.playGate?.resume(); probe.playGate = nil
        try await request.value
        XCTAssertFalse(service.playing, "AUD-02: a late player completion cannot publish playing=true")
        XCTAssertGreaterThanOrEqual(probe.pauses, 2, "Stop once immediately and again after late completion")
    }
    func testOrdinaryMusicPlayAndPause() async throws {
        let probe = MusicProbe(); probe.delaySubscription = false
        let service = SystemMusicService(io: probe.io)
        await service.choose(SystemMusicTrack(id: "one", title: "fixture one"))
        try await service.play()
        XCTAssertTrue(service.playing)
        service.pause()
        XCTAssertFalse(service.playing)
        XCTAssertEqual(probe.starts, 1)
    }
}

@MainActor private final class SocketProbe: RemoteSocketIO {
    var sent: [Data] = []
    var waiting: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    func resume() {}
    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        switch message {
        case .data(let d): sent.append(d)
        case .string(let s): sent.append(Data(s.utf8))
        @unknown default: XCTFail("Unknown socket message")
        }
    }
    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await withCheckedThrowingContinuation { waiting = $0 }
    }
    func cancel() { waiting?.resume(throwing: InjectedFailure.cancelled); waiting = nil }
    var dataFrames: [Data] { sent.filter { (try? JSONSerialization.jsonObject(with: $0) as? [String: Any])?["type"] as? String == "data" } }
}
@MainActor final class RemoteSafetyTests: XCTestCase {
    private func wait(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Handshake/outbound message did not arrive")
    }
    private func pair() async throws -> (RemoteService, RemoteService, SocketProbe, SocketProbe) {
        let a = SocketProbe(), b = SocketProbe()
        let url = URL(string: "https://relay.invalid")!
        let sender = RemoteService(server: url, makeSocket: { _ in a })
        let receiver = RemoteService(server: url, makeSocket: { _ in b })
        let invitation = RemoteService.Invitation(room: "fixture", token: "fixture-token", key: Data(repeating: 1, count: 32).base64EncodedString(), server: url.absoluteString)
        try sender.connect(invitation, role: .sender)
        try receiver.connect(invitation, role: .receiver)
        receiver.pro = true
        for service in [sender, receiver] {
            try service.handle(Data("{\"type\":\"ready\"}".utf8))
            try service.handle(Data("{\"type\":\"peer_joined\"}".utf8))
        }
        await wait { !a.dataFrames.isEmpty && !b.dataFrames.isEmpty }
        try sender.handle(b.dataFrames[0])
        try receiver.handle(a.dataFrames[0])
        receiver.authorize(true)
        return (sender, receiver, a, b)
    }
    func testAUD03EmergencyAPIRequiresNewReceiverConsent() async throws {
        let (sender, receiver, wire, _) = try await pair()
        defer { sender.disconnect(); receiver.disconnect() }
        var starts = 0
        receiver.onCommand = { command, _ in if command.action == "start" { starts += 1 } }
        try await sender.send(action: "start", patternID: "p02", gain: 0.4)
        try receiver.handle(wire.dataFrames.last!)
        XCTAssertEqual(starts, 1)
        let count = wire.dataFrames.count
        sender.emergency()
        await wait { wire.dataFrames.count > count }
        try receiver.handle(wire.dataFrames.last!)
        XCTAssertFalse(receiver.consent.allowed, "AUD-03: test actual emergency API and encrypted wire, not ordinary stop")
        try await sender.send(action: "start", patternID: "p02", gain: 0.4)
        try? receiver.handle(wire.dataFrames.last!)
        XCTAssertEqual(starts, 1, "AUD-03: emergency must latch receiver authorization")
    }
    func testNormalStopPreservesConsentForNextStart() async throws {
        let (sender, receiver, wire, _) = try await pair()
        defer { sender.disconnect(); receiver.disconnect() }
        var stops = 0
        receiver.onSafetyStop = { stops += 1 }
        try await sender.send(action: "stop")
        try receiver.handle(wire.dataFrames.last!)
        XCTAssertEqual(stops, 1)
        XCTAssertTrue(receiver.consent.allowed, "An ordinary stop does not revoke the approved connection")
        var starts = 0
        receiver.onCommand = { command, _ in if command.action == "start" { starts += 1 } }
        try await sender.send(action: "start", patternID: "p02", gain: 0.4)
        try receiver.handle(wire.dataFrames.last!)
        XCTAssertEqual(starts, 1)
    }
}
