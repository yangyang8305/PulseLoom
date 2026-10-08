import XCTest
import CoreHaptics
import PulseLoomCore
@testable import PulseLoom

private enum InjectedFailure: Error { case stop, cancelled }
@MainActor private final class PlayerProbe: HapticPlayerIO {
    var completionHandler: ((Error?) -> Void)?
    var loopEnabled = false
    var loopEnd = 0.0
    var failStart = false
    var failSend = false
    var failStop = false
    var stops = 0
    var starts = 0
    func start(atTime: TimeInterval) throws { starts += 1; if failStart { throw InjectedFailure.stop } }
    func stop(atTime: TimeInterval) throws {
        stops += 1
        if failStop { throw InjectedFailure.stop }
    }
    func sendParameters(_ parameters: [CHHapticDynamicParameter], atTime: TimeInterval) throws { if failSend { throw InjectedFailure.stop } }
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
        sender.pro = true; receiver.pro = true // Both sides have an explicit test entitlement before connecting.
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

extension HapticSafetyTests {
    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected engine termination state was not reached")
    }
    func testFailedEngineShutdownRetainsQuarantineUntilExplicitRetrySucceeds() async throws {
        let first = EngineProbe(), replacement = EngineProbe()
        var factories = 0
        let driver = HapticDriver(makeEngine: {
            factories += 1
            return factories == 1 ? first : replacement
        }, supportsHaptics: { true }, isForeground: { true }, thermalSafe: { true })
        try driver.stream(intensity: 0.4, sharpness: 0.2)
        first.player.failStop = true
        var callbacks = 0
        driver.interrupted = { _ in callbacks += 1; driver.stop() }
        driver.stop()
        XCTAssertEqual(first.stops, 1, "A reentrant coordinator stop must not recursively retry")
        XCTAssertFalse(first.player.loopEnabled)
        let oldReset = first.resetHandler
        first.completion?(InjectedFailure.stop)
        await settle { callbacks == 2 }
        XCTAssertTrue(driver.shutdownPending)
        XCTAssertEqual(first.stops, 1, "An error callback is not a new user retry")
        XCTAssertThrowsError(try driver.stream(intensity: 1, sharpness: 1))
        driver.stop()
        XCTAssertEqual(first.stops, 2)
        first.completion?(nil)
        await settle { !driver.shutdownPending }
        try driver.stream(intensity: 0.3, sharpness: 0.2)
        XCTAssertEqual(factories, 2)
        oldReset?()
        try? await Task.sleep(nanoseconds: 20_000_000)
        driver.stop()
        XCTAssertEqual(replacement.player.stops, 1, "An old engine callback must not erase a newer player")
    }
    func testCoordinatorDoesNotAdvertiseSuccessfulStopWhileQuarantined() throws {
        let engine = EngineProbe()
        let driver = HapticDriver(makeEngine: { engine }, supportsHaptics: { true }, isForeground: { true }, thermalSafe: { true })
        let coordinator = PlaybackCoordinator(driver: driver)
        try coordinator.stream(0.5, sharpness: 0.2, source: "manual")
        engine.player.failStop = true
        coordinator.stop()
        XCTAssertEqual(coordinator.state, .failed)
        XCTAssertNotNil(coordinator.lastError)
        XCTAssertEqual(engine.stops, 1)
        XCTAssertThrowsError(try coordinator.stream(0.5, sharpness: 0.2, source: "manual"))
    }
    func testPlayerStartAndParameterFailuresAlsoTerminateOutput() throws {
        for startFailure in [true, false] {
            let engine = EngineProbe()
            let driver = HapticDriver(makeEngine: { engine }, supportsHaptics: { true }, isForeground: { true }, thermalSafe: { true })
            engine.player.failStart = startFailure
            engine.player.failSend = !startFailure
            XCTAssertThrowsError(try driver.stream(intensity: 0.5, sharpness: 0.2))
            XCTAssertTrue(driver.shutdownPending)
            XCTAssertTrue(engine.isMutedForHaptics)
            XCTAssertEqual(engine.stops, 1)
            XCTAssertThrowsError(try driver.prepare())
        }
    }
}

extension SystemMusicSafetyTests {
    func testCanceledSubscriptionNeverAcquiresOtherSources() async throws {
        let probe = MusicProbe(); let service = SystemMusicService(io: probe.io)
        var acquisitions = 0
        service.willPlay = { acquisitions += 1 }
        await service.choose(SystemMusicTrack(id: "one", title: "fixture"))
        let request = Task { try await service.play() }
        await wait { probe.subscriptionGate != nil }
        service.pause()
        probe.subscriptionGate?.resume(returning: true); probe.subscriptionGate = nil
        try await request.value
        XCTAssertEqual(acquisitions, 0)
        XCTAssertEqual(probe.starts, 0)
    }
    func testReplacementWaitsForOldStartCleanup() async throws {
        let probe = MusicProbe(); probe.delaySubscription = false; probe.delayPlay = true
        let service = SystemMusicService(io: probe.io)
        await service.choose(SystemMusicTrack(id: "old", title: "old"))
        let old = Task { try await service.play() }
        await wait { probe.playGate != nil }
        await service.choose(SystemMusicTrack(id: "new", title: "new"))
        do {
            try await service.play()
            XCTFail("A second player start must not overlap the canceled pending start")
        } catch let error as LoomError {
            guard case .unavailable = error else { return XCTFail("Unexpected error: \(error)") }
        }
        probe.playGate?.resume(); probe.playGate = nil
        try await old.value
        XCTAssertFalse(service.playing)
        XCTAssertEqual(service.selected?.title, "new")
        XCTAssertGreaterThanOrEqual(probe.pauses, 2)
        probe.delayPlay = false
        try await service.play()
        XCTAssertTrue(service.playing)
        XCTAssertEqual(probe.starts, 2)
        service.pause()
    }
    func testAcquisitionCallbackCanCancelBeforeOSPlaybackStarts() async throws {
        let probe = MusicProbe(); probe.delaySubscription = false
        let service = SystemMusicService(io: probe.io)
        service.willPlay = { service.pause() }
        await service.choose(SystemMusicTrack(id: "one", title: "fixture"))
        try await service.play()
        XCTAssertEqual(probe.starts, 0)
        XCTAssertFalse(service.playing)
    }
    func testAppModelAcquisitionDoesNotCancelItsOwnSystemMusicRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = MusicProbe(); probe.delaySubscription = false
        let service = SystemMusicService(io: probe.io)
        let app = AppModel(library: LibraryStore(root: root), systemMusic: service)
        await service.choose(SystemMusicTrack(id: "one", title: "fixture"))
        try await service.play()
        XCTAssertTrue(service.playing)
        XCTAssertEqual(probe.starts, 1)
        app.stopAll()
        XCTAssertFalse(service.playing)
    }
}

extension RemoteSafetyTests {
    func testEmergencyRequiresGrantButNextOrdinarySessionWorks() async throws {
        let (sender, receiver, a, b) = try await pair()
        defer { sender.disconnect(); receiver.disconnect() }
        let pingCount = b.dataFrames.count
        let outbound = a.dataFrames.count
        sender.emergency()
        await wait { a.dataFrames.count > outbound }
        try receiver.handle(a.dataFrames.last!)
        XCTAssertFalse(receiver.consent.allowed)
        await wait { b.dataFrames.count > pingCount }
        try sender.handle(b.dataFrames.last!)
        receiver.authorize(true)
        XCTAssertTrue(receiver.consent.allowed)
        var starts = 0
        receiver.onCommand = { command, _ in if command.action == "start" { starts += 1 } }
        try await sender.send(action: "start", patternID: "p02", gain: 0.4)
        try receiver.handle(a.dataFrames.last!)
        XCTAssertEqual(starts, 1)
        try await sender.send(action: "stop")
        try receiver.handle(a.dataFrames.last!)
        XCTAssertTrue(receiver.consent.allowed)
    }
    func testQueuedPreEmergencyCommandCannotRunAfterNewGrant() async throws {
        let (sender, receiver, wire, _) = try await pair()
        defer { sender.disconnect(); receiver.disconnect() }
        try await sender.send(action: "start", patternID: "p02", gain: 0.4)
        let queued = wire.dataFrames.last!
        receiver.emergency()
        receiver.authorize(true)
        var starts = 0
        receiver.onCommand = { command, _ in if command.action == "start" { starts += 1 } }
        XCTAssertThrowsError(try receiver.handle(queued), "Old authorization nonce must be rejected")
        XCTAssertEqual(starts, 0)
    }
    func testDelayedEmergencyDoesNotTargetReplacementConnection() async throws {
        let (sender, receiver, wire, _) = try await pair()
        defer { sender.disconnect(); receiver.disconnect() }
        let count = wire.dataFrames.count
        sender.emergency()
        let url = URL(string: "https://relay.invalid")!
        let next = RemoteService.Invitation(room: "new-room", token: "fixture-token", key: Data(repeating: 2, count: 32).base64EncodedString(), server: url.absoluteString)
        try sender.connect(next, role: .sender)
        try sender.handle(Data("{\"type\":\"ready\"}".utf8))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(wire.dataFrames.count, count, "Old queued emergency must not send into new room")
    }
}


// GameController policy is intentionally tested without pretending simulator motors exist.
@MainActor final class ControllerHapticRouteTests: XCTestCase {
    private let incapable = ControllerOutputDevice(
        id: UUID(), name: "Input-only pad", family: "Game Controller",
        supportsHaptics: false, localities: [])
    private let capable = ControllerOutputDevice(
        id: UUID(), name: "Haptic pad", family: "DualSense",
        supportsHaptics: true, localities: ["default"])

    func testAutomaticPrefersCapableControllerAndIgnoresInputOnlyPads() throws {
        let id = try HapticRoutePolicy.choose(
            .automatic, devices: [incapable, capable], phoneSupported: true)
        XCTAssertEqual(id, capable.id)
    }

    func testAutomaticFallsBackToPhoneOnlyWhenNoCapableControllerExists() throws {
        XCTAssertNil(try HapticRoutePolicy.choose(
            .automatic, devices: [incapable], phoneSupported: true))
        XCTAssertNil(try HapticRoutePolicy.choose(
            .automatic, devices: [], phoneSupported: true))
        XCTAssertThrowsError(try HapticRoutePolicy.choose(
            .automatic, devices: [incapable], phoneSupported: false))
    }

    func testExplicitControllerSelectionNeverSilentlyFallsBack() throws {
        XCTAssertEqual(try HapticRoutePolicy.choose(
            .controller(capable.id), devices: [capable], phoneSupported: false), capable.id)
        XCTAssertThrowsError(try HapticRoutePolicy.choose(
            .controller(incapable.id), devices: [incapable], phoneSupported: true))
        XCTAssertThrowsError(try HapticRoutePolicy.choose(
            .controller(capable.id), devices: [], phoneSupported: true),
            "A disconnected manually selected controller must not silently vibrate the phone")
    }

    func testExplicitPhoneIgnoresAvailableController() throws {
        XCTAssertNil(try HapticRoutePolicy.choose(
            .phone, devices: [capable], phoneSupported: true))
        XCTAssertThrowsError(try HapticRoutePolicy.choose(
            .phone, devices: [capable], phoneSupported: false))
    }
}
