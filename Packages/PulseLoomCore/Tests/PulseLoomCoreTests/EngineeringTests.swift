import XCTest
@testable import PulseLoomCore

/// SplitMix64: fixed seeds and operation indices make every failure reproducible.
private struct EngineeringRNG {
    var state: UInt64
    mutating func next(_ upper: Int) -> Int {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Int((z ^ (z >> 31)) % UInt64(upper))
    }
}

final class EngineeringUnitTests: XCTestCase {
    func testEveryShippedPatternHasUniqueIdentityValidContentAndLocalizedNames() throws {
        XCTAssertFalse(Catalog.pieces.isEmpty, "Composed pieces must actually be loaded")
        XCTAssertEqual(Set(Catalog.presets.map(\.id)).count, Catalog.presets.count)
        for p in Catalog.presets {
            try Validation.pattern(p)
            for language in ["zh", "en", "ja"] {
                XCTAssertFalse(p.displayName(language: language).trimmingCharacters(in: .whitespaces).isEmpty, p.id)
            }
            XCTAssertTrue(p.durationMS.isFinite && p.durationMS > 0, p.id)
        }
    }
    func testPatternPlaybackBoundariesAndInterpolationAgainstAnalyticSignal() throws {
        let p = HapticPattern(name: "triangle", mode: .curve, segments: [], nodes: [
            CurveNode(time: 0, value: 0), CurveNode(time: 500, value: 1), CurveNode(time: 1000, value: 0)
        ], cycle: 1000, loop: false)
        try Validation.pattern(p)
        for i in 0..<100 {
            let t = Double(i) / 100
            XCTAssertEqual(PatternMath.level(p, at: t), t <= 0.5 ? t * 2 : (1 - t) * 2, accuracy: 1e-10)
        }
        for t in [-1.0, 1, 2, .infinity, .nan] { XCTAssertEqual(PatternMath.level(p, at: t), 0) }
        var loop = p; loop.loop = true
        XCTAssertEqual(PatternMath.level(loop, at: 4.25), 0.5, accuracy: 1e-10)
    }
    func testFadeEnvelopeDoesNotExceedRequestedAmplitude() {
        for elapsed in [-2.0, 0, 0.5, 1, 20] {
            for remaining in [-2.0, 0, 0.5, 1, 20] {
                let v = PatternMath.envelope(elapsed: elapsed, remaining: remaining, fadeIn: 1, fadeOut: 1)
                XCTAssertTrue((0...1).contains(v))
                if elapsed <= 0 || remaining <= 0 { XCTAssertEqual(v, 0) }
            }
        }
    }
    func testInvalidClockCommandsAreAtomic() throws {
        var clock = SessionClock(); try clock.start(now: 10, duration: 30); clock.tick(now: 12)
        for invalid in [Double.nan, .infinity, -.infinity, -1, 7201] {
            let before = (clock.state, clock.played, clock.limit, clock.generation)
            XCTAssertThrowsError(try clock.setRemaining(invalid))
            XCTAssertEqual(clock.state, before.0); XCTAssertEqual(clock.played, before.1)
            XCTAssertEqual(clock.limit, before.2); XCTAssertEqual(clock.generation, before.3)
        }
        XCTAssertThrowsError(try clock.start(now: .nan, duration: 30))
        XCTAssertEqual(clock.played, 2)
    }
    func testExternalRoundTripCannotElevateRestrictedContent() throws {
        for p in Catalog.presets where p.premium {
            let copy = p.copyForEditing()
            let data = try FileCodec.encode(copy)
            let decoded = try FileCodec.decode(HapticPattern.self, data)
            XCTAssertEqual(ContentPolicy.origin(decoded), .restricted)
            XCTAssertFalse(Entitlements.canPlay(decoded, pro: false))
        }
    }
}

final class EngineeringIntegrationTests: XCTestCase {
    func testRandomizedAtomicFileRoundTripsAndPreviousVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.json")
        var rng = EngineeringRNG(state: 0xF11E)
        var previous: HapticPattern?
        for step in 0..<150 {
            let p = HapticPattern(name: "Roundtrip \(step)", segments: [Segment(
                duration: Double(50 + rng.next(400)), gap: Double(50 + rng.next(400)),
                gain: Double(1 + rng.next(100)) / 100, sharp: Double(rng.next(101)) / 100)])
            try Validation.pattern(p)
            try FileCodec.write(p, to: url)
            XCTAssertEqual(try FileCodec.read(HapticPattern.self, from: url), p, "step=\(step)")
            if let previous { XCTAssertEqual(try FileCodec.read(HapticPattern.self, from: url.appendingPathExtension("previous")), previous) }
            let old = try Data(contentsOf: url)
            XCTAssertThrowsError(try FileCodec.write(p, to: url, maxBytes: 1))
            XCTAssertEqual(try Data(contentsOf: url), old, "Rejected writes must not damage committed data")
            previous = p
        }
    }
}

final class EngineeringStateMachineTests: XCTestCase {
    /// Reference state tracks accumulated time explicitly; it does not invoke SessionClock/PatternMath.
    func testSessionClockAgainstIndependentModel16000Operations() throws {
        for seed in 1...32 {
            var rng = EngineeringRNG(state: UInt64(seed))
            var sut = SessionClock(), expected: PlaybackState = .idle
            var played = 0.0, limit = 180.0, anchor: Double?, now = 100.0, generation: UInt64 = 0
            func advance(_ t: Double) {
                guard expected == .playing, let a = anchor else { return }
                if t > a { played += t - a; anchor = t }
                if played >= limit { played = limit; anchor = nil; expected = .completed }
            }
            for step in 0..<500 {
                now += Double(rng.next(20)) / 10
                let action = rng.next(8)
                switch action {
                case 0:
                    limit = Double(1 + rng.next(120)); played = 0; anchor = now; expected = .playing; generation &+= 1
                    try sut.start(now: now, duration: limit)
                case 1: advance(now); sut.tick(now: now)
                case 2, 3:
                    advance(now)
                    if expected == .playing { expected = action == 2 ? .paused : .interrupted }
                    anchor = nil; sut.pause(now: now, interrupted: action == 3)
                case 4:
                    if [.paused, .interrupted].contains(expected), limit > played {
                        expected = .playing; anchor = now; generation &+= 1
                    }
                    sut.resume(now: now)
                case 5: expected = .idle; anchor = nil; generation &+= 1; sut.stop()
                case 6: expected = .failed; anchor = nil; generation &+= 1; sut.fail()
                default:
                    let remaining = Double(rng.next(120)); limit = min(7200, played + remaining)
                    try sut.setRemaining(remaining)
                }
                let trace = "seed=\(seed) step=\(step) action=\(action) now=\(now)"
                XCTAssertEqual(sut.state, expected, trace)
                XCTAssertEqual(sut.played, played, accuracy: 1e-8, trace)
                XCTAssertEqual(sut.limit, limit, accuracy: 1e-8, trace)
                XCTAssertEqual(sut.remaining, max(0, limit - played), accuracy: 1e-8, trace)
                XCTAssertEqual(sut.generation, generation, trace)
                if sut.state != expected || abs(sut.played - played) > 1e-8 { return }
            }
        }
    }
    func testConsentRandomTransitionsFailClosedAndNeverExceedLimit() throws {
        for seed in 1...20 {
            var rng = EngineeringRNG(state: UInt64(seed)), sut = RemoteConsent()
            var allowed = false, consumed: UInt64 = 0
            for step in 0..<300 {
                switch rng.next(5) {
                case 0: sut.grant(); allowed = true
                case 1: sut.revoke(); allowed = false
                case 2: sut.resetConnection(); allowed = false; consumed = 0
                default:
                    let seq = rng.next(4) == 0 ? consumed : consumed + 1
                    let action = ["gain", "stop", "emergencyStop", "ping", "unknown"][rng.next(5)]
                    let foreground = rng.next(2) == 0, pro = rng.next(2) == 0
                    let gain = Double(rng.next(101)) / 100
                    let legal = seq > consumed && action != "unknown"
                    let shouldSucceed = legal && (action != "gain" || (allowed && foreground && pro))
                    do {
                        let result = try sut.accept(RemoteCommand(sequence: seq, action: action, gain: gain), foreground: foreground, pro: pro)
                        XCTAssertTrue(shouldSucceed, "seed=\(seed) step=\(step)")
                        if action == "gain" { XCTAssertEqual(result ?? -1, min(gain, 0.4), accuracy: 1e-10) }
                    } catch { XCTAssertFalse(shouldSucceed, "seed=\(seed) step=\(step) error=\(error)") }
                    if legal { consumed = seq; if action == "emergencyStop" { allowed = false } }
                }
                XCTAssertEqual(sut.allowed, allowed, "seed=\(seed) step=\(step)")
                XCTAssertEqual(sut.lastSequence, consumed)
            }
        }
    }
}
