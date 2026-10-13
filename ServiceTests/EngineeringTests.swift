import XCTest
import CoreHaptics
import AVFoundation
import PulseLoomCore
@testable import PulseLoom

private enum EngineeringFault: Error { case start }
@MainActor private final class EngineeringPlayer: HapticPlayerIO {
    var completionHandler: ((Error?) -> Void)?
    var loopEnabled = false
    var loopEnd = 0.0
    var starts = 0, stops = 0
    var sends: [[CHHapticDynamicParameter]] = []
    var failStart = false
    func start(atTime: TimeInterval) throws { if failStart { throw EngineeringFault.start }; starts += 1 }
    func stop(atTime: TimeInterval) throws { stops += 1 }
    func sendParameters(_ p: [CHHapticDynamicParameter], atTime: TimeInterval) throws { sends.append(p) }
}
@MainActor private final class EngineeringEngine: HapticEngineIO {
    var stoppedHandler: ((CHHapticEngine.StoppedReason) -> Void)?
    var resetHandler: (() -> Void)?
    var isMutedForHaptics = false
    let controllerTone: ControllerTone?
    var players: [EngineeringPlayer] = []
    var patterns: [CHHapticPattern] = []
    var failNextStart = false
    init(tone: ControllerTone? = nil) { controllerTone = tone }
    func start() throws {}
    func stop(completion: @escaping (Error?) -> Void) { completion(nil) }
    func makeAdvancedPlayer(with pattern: CHHapticPattern) throws -> any HapticPlayerIO {
        let p = EngineeringPlayer(); p.failStart = failNextStart
        failNextStart = false; players.append(p); patterns.append(pattern); return p
    }
}

@MainActor final class EngineeringServiceIntegrationTests: XCTestCase {
    private func driver(_ engine: EngineeringEngine) -> HapticDriver {
        HapticDriver(makeEngine: { engine }, supportsHaptics: { true }, isForeground: { true }, thermalSafe: { true })
    }
    func testEveryPresetCompilesOnPhoneAndBothControllerActuatorPaths() throws {
        for tone: ControllerTone? in [nil, .voiceCoil, .motor] {
            let engine = EngineeringEngine(tone: tone), d = driver(engine)
            for p in Catalog.presets {
                for phase in [0.0, p.durationMS / 2000] {
                    try d.play(p, phase: phase, length: 2, sessionElapsed: 0, sessionLimit: 30, gain: 1, speed: 1, sharp: 0.5)
                    XCTAssertGreaterThan(try XCTUnwrap(engine.patterns.last).duration, 0, p.id)
                    XCTAssertEqual(engine.players.last?.starts, 1, p.id)
                    if tone != nil {
                        let exported = try XCTUnwrap(engine.patterns.last).exportDictionary()
                        let rows = exported[.pattern] as? [[CHHapticPattern.Key: Any]] ?? []
                        XCTAssertFalse(rows.contains { $0[.parameterCurve] != nil }, "Controllers must receive baked events: \(p.id)")
                    }
                }
            }
            XCTAssertTrue(d.stop())
        }
    }
    /// Cold start and warm restart must request identical actuator parameters for the same slider value.
    func testControllerColdAndWarmStreamUseTheSameActuatorMapping() throws {
        for tone in [ControllerTone.voiceCoil, .motor] {
            let e = EngineeringEngine(tone: tone), d = driver(e)
            try d.stream(intensity: 0.25, sharpness: 1)
            let cold = try XCTUnwrap(e.players.last?.sends.last)
            XCTAssertTrue(d.stop())
            try d.stream(intensity: 0.25, sharpness: 1)
            let warm = try XCTUnwrap(e.players.last?.sends.last)
            for id in [CHHapticDynamicParameter.ID.hapticIntensityControl, .hapticSharpnessControl] {
                XCTAssertEqual(cold.first { $0.parameterID == id }?.value, warm.first { $0.parameterID == id }?.value,
                               "First stream must not bypass controller calibration")
            }
            let expected = HapticDriver.controllerSharpness(1, tone: tone)
            XCTAssertEqual(cold.first { $0.parameterID == .hapticSharpnessControl }?.value ?? -1, expected, accuracy: 0.0001)
            XCTAssertTrue(d.stop())
        }
    }
    func testControllerDiagnosticsDescribeParametersActuallySentToEngine() throws {
        let e = EngineeringEngine(tone: .voiceCoil), d = driver(e)
        try d.prepare()
        var last: HapticDispatch?
        d.dispatched = { last = $0 }
        try d.stream(intensity: 0.25, sharpness: 1)
        let sent = try XCTUnwrap(e.players.last?.sends.last)
        let dispatch = try XCTUnwrap(last)
        XCTAssertEqual(dispatch.peakIntensity, Double(sent.first { $0.parameterID == .hapticIntensityControl }?.value ?? -1), accuracy: 0.0001,
                       "Diagnostics promise actual submitted parameters, not uncalibrated slider values")
        XCTAssertEqual(dispatch.sharpness, Double(sent.first { $0.parameterID == .hapticSharpnessControl }?.value ?? -1), accuracy: 0.0001)
        XCTAssertTrue(d.stop())
    }
    func testStalePlayerCompletionCannotAdvanceReplacementSession() async throws {
        let e = EngineeringEngine(), d = driver(e)
        var completions = 0; d.windowCompleted = { completions += 1 }
        let p = try XCTUnwrap(Catalog.loops.first)
        try d.play(p, phase: 0, length: 1, sessionElapsed: 0, sessionLimit: 30, gain: 1, speed: 1, sharp: 0.5)
        let stale = try XCTUnwrap(e.players.last?.completionHandler)
        try d.play(p, phase: 0, length: 1, sessionElapsed: 0, sessionLimit: 30, gain: 1, speed: 1, sharp: 0.5)
        stale(nil)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(completions, 0)
        e.players.last?.completionHandler?(nil)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(completions, 1)
        XCTAssertTrue(d.stop())
    }
    func testThermalRejectionDoesNotCreateOrStartAnyPlayer() {
        let e = EngineeringEngine()
        let d = HapticDriver(makeEngine: { e }, supportsHaptics: { true }, thermalSafe: { false })
        XCTAssertThrowsError(try d.stream(intensity: 1, sharpness: 1))
        XCTAssertTrue(e.players.isEmpty)
    }
    func testLibrarySaveFavoriteDeleteAndRestartAgainstIndependentInventory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Engineering-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var store = LibraryStore(root: root), expected: [String: HapticPattern] = [:]
        var favorites = Set<String>(), state: UInt64 = 0x51A7E
        for step in 0..<180 {
            state = state &* 6364136223846793005 &+ 1
            let choice = Int((state >> 32) % 4)
            if choice == 0 || expected.isEmpty {
                let p = HapticPattern(name: "Inventory \(step)")
                try store.save(p, pro: true); expected[p.id] = p
            } else if let id = expected.keys.sorted().first {
                if choice == 1 {
                    try store.favorite(id)
                    if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
                } else if choice == 2 {
                    try store.delete(id); expected.removeValue(forKey: id); favorites.remove(id)
                } else { store = LibraryStore(root: root) }
            }
            XCTAssertNil(store.loadError, "step=\(step)")
            XCTAssertEqual(Set(store.snapshot.custom.map(\.id)), Set(expected.keys), "step=\(step)")
            XCTAssertEqual(Set(store.snapshot.favorites), favorites, "step=\(step)")
            try Validation.snapshot(store.snapshot)
        }
        let reopened = LibraryStore(root: root)
        XCTAssertEqual(Set(reopened.snapshot.custom.map(\.id)), Set(expected.keys))
    }
    func testAllBundledAudioActuallyDecodesAndMatchesDeclaredDuration() throws {
        XCTAssertEqual(BundledMusic.tracks.count, 8, "Missing bundled resources must fail, not silently disappear")
        XCTAssertEqual(Set(BundledMusic.tracks.map(\.id)).count, 8)
        for track in BundledMusic.tracks {
            let file = try AVAudioFile(forReading: XCTUnwrap(track.url))
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            XCTAssertEqual(seconds, track.seconds, accuracy: 0.2, track.id)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 44100))
            // Sample the body, not the intentionally faded opening.
            file.framePosition = min(file.length / 2, AVAudioFramePosition(file.processingFormat.sampleRate * 3))
            try file.read(into: buffer)
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            var peak: Float = 0
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[i])); XCTAssertTrue(samples[i].isFinite, track.id) }
            XCTAssertGreaterThan(peak, 0.001, "Bundled file must contain audible samples: \(track.id)")
        }
    }
}

@MainActor final class EngineeringPlaybackStateMachineTests: XCTestCase {
    func testRandomStartPauseResumeStopAndTickAgainstModel2400Operations() throws {
        let pattern = try XCTUnwrap(Catalog.loops.first)
        for seed in 1...12 {
            let e = EngineeringEngine(); var time = 0.0
            let d = HapticDriver(makeEngine: { e }, supportsHaptics: { true }, thermalSafe: { true })
            let c = PlaybackCoordinator(driver: d, now: { time }); c.keepAwake = false
            var state: UInt64 = UInt64(seed), expected: PlaybackState = .idle
            var played = 0.0
            for step in 0..<200 {
                state = state &* 6364136223846793005 &+ 1
                let action = Int((state >> 32) % 5)
                switch action {
                case 0: try c.begin(pattern, duration: 600, gain: 0.75); expected = .playing; played = 0
                case 1: c.pause(); if expected == .playing { expected = .paused }
                case 2: try c.resume(); if expected == .paused { expected = .playing }
                case 3: c.stop(); expected = .idle
                default:
                    time += 0.125
                    if expected == .playing { played += 0.125 }
                    c.tick()
                }
                let trace = "seed=\(seed) step=\(step) action=\(action)"
                XCTAssertEqual(c.state, expected, trace)
                XCTAssertEqual(c.elapsed, played, accuracy: 1e-8, trace)
                if expected != .playing { XCTAssertEqual(c.level, 0, trace) }
            }
            c.stop()
            XCTAssertTrue(e.players.allSatisfy { $0.stops > 0 }, "Every acquired player must be stopped: seed=\(seed)")
        }
    }
}
