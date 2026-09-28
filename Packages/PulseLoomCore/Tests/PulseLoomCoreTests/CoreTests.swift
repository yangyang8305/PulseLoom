import XCTest

@testable import PulseLoomCore

final class CatalogTests: XCTestCase {
    func testSixteenStablePresets() {
        XCTAssertEqual(Catalog.presets.count, 16)
        XCTAssertEqual(Catalog.presets.map(\.id), (1...16).map { String(format: "p%02d", $0) })
    }
    func testSixFreePresets() { XCTAssertEqual(Catalog.presets.filter { !$0.premium }.count, 6) }
    func testAllPresetsAreValid() {
        for p in Catalog.presets { XCTAssertNoThrow(try Validation.pattern(p), p.id) }
    }
    func testAllThemesHaveTwelveLightDarkTokens() {
        XCTAssertEqual(Catalog.themes.count, 6)
        for t in Catalog.themes {
            XCTAssertEqual(t.light.count, 12)
            XCTAssertEqual(t.dark.count, 12)
            for c in t.light + t.dark {
                XCTAssertNotNil(c.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression))
            }
        }
    }
    func testThemeFreeCount() { XCTAssertEqual(Catalog.themes.filter(\.free).count, 2) }
    func testLocalizationNames() {
        for p in Catalog.presets {
            XCTAssertFalse(p.displayName(language: "en").isEmpty)
            XCTAssertFalse(p.displayName(language: "ja").isEmpty)
            XCTAssertEqual(p.displayName(language: "zh"), p.name)
        }
    }
    func testCopyIsIndependent() {
        let original = Catalog.presets[7]
        var copy = original.copyForEditing()
        copy.segments[0].gain = 0
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertFalse(copy.builtin)
        XCTAssertTrue(copy.sourcePremium)
        XCTAssertNotEqual(copy.segments[0].gain, original.segments[0].gain)
    }
}
final class ValidationTests: XCTestCase {
    func valid() -> HapticPattern { HapticPattern(name: "Test") }
    func testNormalPattern() { XCTAssertNoThrow(try Validation.pattern(valid())) }
    func testEmptyName() {
        var p = valid()
        p.name = "  "
        XCTAssertThrowsError(try Validation.pattern(p))
        XCTAssertNoThrow(try Validation.pattern(p, requireName: false))
    }
    func testLongName() {
        var p = valid()
        p.name = String(repeating: "a", count: 31)
        XCTAssertThrowsError(try Validation.pattern(p))
    }
    func testNonFiniteGain() {
        for value in [Double.nan, Double.infinity, -0.1, 1.1] {
            var p = valid()
            p.segments[0].gain = value
            XCTAssertThrowsError(try Validation.pattern(p))
        }
    }
    func testInvalidDurations() {
        for value in [-1.0, 0, Double.nan, 3001] {
            var p = valid()
            p.segments[0].duration = value
            XCTAssertThrowsError(try Validation.pattern(p))
        }
    }
    func testSilentPattern() {
        var p = valid()
        p.segments = p.segments.map {
            var s = $0
            s.gain = 0
            return s
        }
        XCTAssertThrowsError(try Validation.pattern(p))
    }
    func testSegmentAndRecordingCaps() {
        var p = valid()
        p.segments = (0..<17).map { _ in Segment() }
        XCTAssertThrowsError(try Validation.pattern(p))
        p.mode = .recorded
        XCTAssertNoThrow(try Validation.pattern(p))
        p.segments = (0..<129).map { _ in Segment(duration: 50, gap: 0) }
        XCTAssertThrowsError(try Validation.pattern(p))
    }
    func testRecordedLongHold() {
        var p = valid()
        p.mode = .recorded
        p.segments = [Segment(duration: 10000, gap: 100)]
        XCTAssertNoThrow(try Validation.pattern(p))
        p.segments[0].duration = 10001
        XCTAssertThrowsError(try Validation.pattern(p))
    }
    func testDuplicateSegmentIDs() {
        var p = valid()
        p.segments = [p.segments[0], p.segments[0]]
        XCTAssertThrowsError(try Validation.pattern(p))
    }
    func testCycleOverThirtySeconds() {
        var p = valid()
        p.mode = .recorded
        p.segments = (0..<4).map { _ in Segment(duration: 10000, gap: 0) }
        XCTAssertThrowsError(try Validation.pattern(p))
    }
    func testCurveValidation() {
        var p = HapticPattern(
            name: "curve", mode: .curve, segments: [],
            nodes: [CurveNode(time: 0, value: 0.1), CurveNode(time: 2000, value: 0.8)], cycle: 2000)
        XCTAssertNoThrow(try Validation.pattern(p))
        p.nodes.append(CurveNode(time: 1000, value: 0.2))
        XCTAssertThrowsError(try Validation.pattern(p))
    }
    func testCurveMissingEndpoints() {
        let p = HapticPattern(
            name: "curve", mode: .curve,
            nodes: [CurveNode(time: 10, value: 0.1), CurveNode(time: 2000, value: 0.8)])
        XCTAssertThrowsError(try Validation.pattern(p))
    }
    func testCurveTooManyNodes() {
        let p = HapticPattern(
            name: "curve", mode: .curve,
            nodes: (0..<65).map { CurveNode(time: Double($0) * 100, value: 0.5) }, cycle: 6400)
        XCTAssertThrowsError(try Validation.pattern(p))
    }
    func testRoutineLimits() {
        var r = Routine(
            name: "ritual",
            items: [RoutineItem(patternID: "p02", seconds: 300), RoutineItem(patternID: "p04", seconds: 300)])
        XCTAssertNoThrow(try Validation.routine(r, patterns: Catalog.presets))
        r.items.append(RoutineItem(patternID: "p01", seconds: 15))
        XCTAssertThrowsError(try Validation.routine(r, patterns: Catalog.presets))
    }
    func testMissingRoutineReference() {
        let r = Routine(name: "r", items: [RoutineItem(patternID: "missing")])
        XCTAssertThrowsError(try Validation.routine(r, patterns: Catalog.presets))
    }
    func testSnapshotReferences() {
        var s = LibrarySnapshot()
        XCTAssertNoThrow(try Validation.snapshot(s))
        s.favorites = ["missing"]
        XCTAssertThrowsError(try Validation.snapshot(s))
    }
    func testDuplicateFavorites() {
        var s = LibrarySnapshot()
        s.favorites = ["p01", "p01"]
        XCTAssertThrowsError(try Validation.snapshot(s))
    }
    func testDuplicateRoutineIDs() {
        var s = LibrarySnapshot()
        let r = Routine(id: "same", name: "r", items: [RoutineItem(patternID: "p01")])
        s.routines = [r, r]
        XCTAssertThrowsError(try Validation.snapshot(s))
    }
    func testSnapshotCannotOverrideBuiltin() {
        var s = LibrarySnapshot()
        s.custom = [Catalog.presets[0]]
        XCTAssertThrowsError(try Validation.snapshot(s))
    }
    func testMusicBounds() {
        var c = MusicConfiguration()
        c.to = 30
        XCTAssertNoThrow(try Validation.music(c, duration: 30))
        c.offset = 0.51
        XCTAssertThrowsError(try Validation.music(c, duration: 30))
        c.offset = 0
        c.from = 30
        XCTAssertThrowsError(try Validation.music(c, duration: 30))
    }
    func testEntitlementQuota() {
        XCTAssertTrue(Entitlements.canSave(isNew: true, count: 2, pro: false))
        XCTAssertFalse(Entitlements.canSave(isNew: true, count: 3, pro: false))
        XCTAssertTrue(Entitlements.canSave(isNew: false, count: 100, pro: false))
        XCTAssertFalse(Entitlements.canSave(isNew: true, count: 200, pro: true))
    }
    func testPaidDerivativeRetainsGate() {
        let p = Catalog.presets[6].copyForEditing()
        XCTAssertFalse(Entitlements.canPlay(p, pro: false))
        XCTAssertTrue(Entitlements.canPlay(p, pro: true))
        XCTAssertTrue(Entitlements.canPlay(valid(), pro: false))
    }
}
final class ClockAndEditorTests: XCTestCase {
    func testPauseDoesNotConsumeTime() throws {
        var c = SessionClock()
        try c.start(now: 10, duration: 180)
        c.tick(now: 20)
        c.pause(now: 25)
        c.tick(now: 100)
        XCTAssertEqual(c.played, 15)
        c.resume(now: 100)
        c.tick(now: 110)
        XCTAssertEqual(c.played, 25)
    }
    func testTimerCannotExtendPastTenMinutes() throws {
        var c = SessionClock()
        try c.start(now: 0, duration: 600)
        c.tick(now: 550)
        try c.setRemaining(600)
        XCTAssertEqual(c.limit, 600)
        XCTAssertEqual(c.remaining, 50)
    }
    func testNegativeClockJumpIgnored() throws {
        var c = SessionClock()
        try c.start(now: 100, duration: 30)
        c.tick(now: 90)
        XCTAssertEqual(c.played, 0)
        c.tick(now: 110)
        XCTAssertEqual(c.played, 10)
    }
    func testCompletionAndStop() throws {
        var c = SessionClock()
        try c.start(now: 0, duration: 30)
        c.tick(now: 31)
        XCTAssertEqual(c.state, .completed)
        XCTAssertEqual(c.played, 30)
        c.stop()
        XCTAssertEqual(c.state, .idle)
    }
    func testInterruptedDoesNotAutoResume() throws {
        var c = SessionClock()
        try c.start(now: 0, duration: 30)
        c.pause(now: 5, interrupted: true)
        c.tick(now: 20)
        XCTAssertEqual(c.state, .interrupted)
        XCTAssertEqual(c.remaining, 25)
    }
    func testUndoRedoIsValueSemantic() {
        var h = EditHistory<Int>()
        for i in 0..<40 { h.record(i) }
        XCTAssertEqual(h.undoStack.count, 30)
        XCTAssertEqual(h.undo(40), 39)
        XCTAssertEqual(h.redo(39), 40)
        h.record(41)
        XCTAssertTrue(h.redoStack.isEmpty)
    }
    func testRecorderTrimsLeadingSilence() throws {
        var r = TouchRecorder()
        r.start(now: 0)
        r.down(now: 2)
        r.up(now: 2.2)
        r.finish(now: 3)
        let p = try r.pattern(name: "tap")
        XCTAssertEqual(p.segments[0].duration, 200, accuracy: 0.01)
        XCTAssertLessThan(p.durationMS, 400)
    }
    func testSecondFingerIgnored() {
        var r = TouchRecorder()
        r.start(now: 0)
        XCTAssertTrue(r.down(now: 1))
        XCTAssertFalse(r.down(now: 1.1))
        XCTAssertEqual(r.segments.count, 1)
    }
    func testRecorderShortTapIsTransient() throws {
        var r = TouchRecorder()
        r.start(now: 0)
        r.down(now: 0.1)
        r.up(now: 0.12)
        r.finish(now: 1)
        let p = try r.pattern(name: "tap")
        XCTAssertEqual(p.segments[0].type, .transient)
        XCTAssertEqual(p.segments[0].duration, 0)
    }
    func testRecorderTenSecondHoldCap() {
        var r = TouchRecorder()
        r.start(now: 0)
        r.down(now: 1)
        r.tick(now: 12)
        XCTAssertFalse(r.isDown)
        XCTAssertEqual(r.segments[0].duration, 10000)
    }
    func testRecorderThirtySecondCap() {
        var r = TouchRecorder()
        r.start(now: 0)
        r.down(now: 29)
        r.tick(now: 31)
        XCTAssertFalse(r.active)
        XCTAssertFalse(r.isDown)
        XCTAssertEqual(r.segments[0].duration, 1000)
    }
    func testRecorderCapacity() {
        var r = TouchRecorder()
        r.start(now: 0)
        for i in 0..<128 {
            r.down(now: Double(i) * 0.1)
            r.up(now: Double(i) * 0.1 + 0.06)
        }
        XCTAssertFalse(r.down(now: 13))
        XCTAssertEqual(r.segments.count, 128)
    }
    func testBreathing() throws {
        let b = BreathTiming()
        XCTAssertEqual(b.phase(at: 1).0, "breath.inhale")
        XCTAssertEqual(b.phase(at: 5).0, "breath.exhale")
        XCTAssertNoThrow(try Validation.pattern(b.pattern()))
    }
    func testPatternMath() {
        let p = HapticPattern(name: "p", segments: [Segment(duration: 200, gap: 200, gain: 0.8)])
        XCTAssertEqual(PatternMath.level(p, at: 0.1), 0.8)
        XCTAssertEqual(PatternMath.level(p, at: 0.3), 0)
        XCTAssertEqual(PatternMath.level(p, at: 0.5), 0.8)
    }
    func testCurveMath() {
        let p = HapticPattern(
            name: "c", mode: .curve, nodes: [CurveNode(time: 0, value: 0), CurveNode(time: 1000, value: 1)],
            cycle: 1000)
        XCTAssertEqual(PatternMath.level(p, at: 0.5), 0.5, accuracy: 0.001)
    }
    func testFadeMath() {
        XCTAssertEqual(PatternMath.envelope(elapsed: 0.5, remaining: 10, fadeIn: 1, fadeOut: 1), 0.5)
        XCTAssertEqual(PatternMath.envelope(elapsed: 10, remaining: 0, fadeIn: 1, fadeOut: 1), 0)
    }
}
final class PersistenceTests: XCTestCase {
    func testRoundTrip() throws {
        var s = LibrarySnapshot()
        s.updatedAt = Date(timeIntervalSince1970: 100)
        s.custom = [HapticPattern(name: "mine", updatedAt: Date(timeIntervalSince1970: 100))]
        let encoded = try FileCodec.encode(s)
        let decoded = try FileCodec.decode(LibrarySnapshot.self, encoded)
        XCTAssertEqual(s, decoded)
    }
    func testAtomicFileAndPrevious() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let u = root.appendingPathComponent("data.json")
        try FileCodec.write([1], to: u)
        try FileCodec.write([2], to: u)
        XCTAssertEqual(try FileCodec.read([Int].self, from: u), [2])
        XCTAssertEqual(try FileCodec.read([Int].self, from: u.appendingPathExtension("previous")), [1])
    }
    func testInvalidParentThrows() throws {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: u) }
        try Data("file".utf8).write(to: u)
        XCTAssertThrowsError(try FileCodec.write([1], to: u.appendingPathComponent("x")))
    }
    func testCorruptJSONRejected() {
        XCTAssertThrowsError(try FileCodec.decode(LibrarySnapshot.self, Data("bad".utf8)))
    }
    func testOversizeRejected() {
        XCTAssertThrowsError(try PatternImport.decode(Data(repeating: 32, count: 300000)))
    }
    func testImportChangesIDAndPrivilege() throws {
        var p = Catalog.presets[0]
        p.premium = true
        let x = try PatternImport.decode(FileCodec.encode(p))
        XCTAssertNotEqual(x.id, p.id)
        XCTAssertFalse(x.builtin)
        XCTAssertFalse(x.premium)
    }
    func testPrototypePatternImport() throws {
        let data = Data(
            #"{"schemaVersion":2,"name":"HTML","mode":"basic","segments":[{"duration":250,"gap":250,"gain":0.5,"sharp":0.2}]}"#
                .utf8)
        XCTAssertEqual(try PatternImport.decode(data).name, "HTML")
    }
    func testBulkImport() throws {
        let data = try FileCodec.encode([HapticPattern(name: "one"), HapticPattern(name: "two")])
        let ps = try PatternImport.decodeMany(data)
        XCTAssertEqual(ps.count, 2)
        XCTAssertNotEqual(ps[0].id, ps[1].id)
    }
    func testCloudPayloadExcludesPrivateFields() {
        var s = LibrarySnapshot()
        s.preferences.name = "personal"
        s.preferences.theme = "lilac"
        s.mixes = [MusicMix(name: "private", trackName: "file.mp3", configuration: MusicConfiguration())]
        s.notes = [FeedbackNote(text: "private", screen: "music")]
        let cloud = s.cloudPayload()
        XCTAssertEqual(cloud.preferences.name, "")
        XCTAssertTrue(cloud.mixes.isEmpty)
        XCTAssertTrue(cloud.notes.isEmpty)
        XCTAssertEqual(cloud.preferences.theme, "lilac")
    }
    func testCloudFingerprintIgnoresDeviceOnlyMutations() throws {
        var a = LibrarySnapshot()
        a.updatedAt = Date(timeIntervalSince1970: 1)
        var b = a
        b.preferences.gain = 0.8
        b.preferences.name = "changed"
        b.updatedAt = Date(timeIntervalSince1970: 5)
        XCTAssertEqual(try FileCodec.encode(a.cloudPayload()), try FileCodec.encode(b.cloudPayload()))
    }
    func testConflictPreservesBoth() throws {
        var a = LibrarySnapshot()
        var b = LibrarySnapshot()
        a.custom = [HapticPattern(id: "same", name: "one", updatedAt: Date(timeIntervalSince1970: 10))]
        b.custom = [HapticPattern(id: "same", name: "two", updatedAt: Date(timeIntervalSince1970: 11))]
        let result = try CloudMerge.preservingBoth(local: a, remote: b)
        XCTAssertEqual(result.custom.count, 2)
    }
    func testDeletedRemoteEditDoesNotResurrectThroughCopy() throws {
        var a = LibrarySnapshot()
        var b = LibrarySnapshot()
        a.custom = [HapticPattern(id: "same", name: "local", updatedAt: Date(timeIntervalSince1970: 10))]
        b.custom = [HapticPattern(id: "same", name: "remote", updatedAt: Date(timeIntervalSince1970: 11))]
        a.tombstones["same"] = Date(timeIntervalSince1970: 20)
        let result = try CloudMerge.preservingBoth(local: a, remote: b)
        XCTAssertTrue(result.custom.isEmpty)
    }
    func testFavoritesRetainLocalOrder() throws {
        var a = LibrarySnapshot()
        var b = LibrarySnapshot()
        a.favorites = ["p03", "p01"]
        b.favorites = ["p02", "p01"]
        XCTAssertEqual(try CloudMerge.preservingBoth(local: a, remote: b).favorites, ["p03", "p01", "p02"])
    }
}
final class RemoteTests: XCTestCase {
    func testDefaultDenies() {
        var s = RemoteConsent()
        XCTAssertThrowsError(
            try s.accept(
                RemoteCommand(sequence: 1, action: "start", patternID: "p01", gain: 0.3), foreground: true,
                pro: false))
    }
    func testClampsToReceiverLimit() throws {
        var s = RemoteConsent()
        s.grant()
        s.limit = 0.4
        XCTAssertEqual(
            try s.accept(
                RemoteCommand(sequence: 1, action: "start", patternID: "p01", gain: 0.9), foreground: true,
                pro: false), 0.4)
    }
    func testBackgroundDenied() {
        var s = RemoteConsent()
        s.grant()
        XCTAssertThrowsError(
            try s.accept(
                RemoteCommand(sequence: 1, action: "start", patternID: "p01", gain: 0.3), foreground: false,
                pro: false))
    }
    func testStopAllowedWithoutConsent() throws {
        var s = RemoteConsent()
        XCTAssertNil(try s.accept(RemoteCommand(sequence: 1, action: "stop"), foreground: false, pro: false))
    }
    func testReplayRejected() throws {
        var s = RemoteConsent()
        let c = RemoteCommand(sequence: 1, action: "ping")
        _ = try s.accept(c, foreground: true, pro: false)
        XCTAssertThrowsError(try s.accept(c, foreground: true, pro: false))
    }
    func testUnknownAction() {
        var s = RemoteConsent()
        XCTAssertThrowsError(
            try s.accept(RemoteCommand(sequence: 1, action: "delete"), foreground: true, pro: false))
    }
    func testRemoteCannotBypassPro() {
        var s = RemoteConsent()
        s.grant()
        XCTAssertThrowsError(
            try s.accept(
                RemoteCommand(sequence: 1, action: "start", patternID: "p16", gain: 0.3), foreground: true,
                pro: false))
    }
    func testReconnectRequiresConsent() {
        var s = RemoteConsent()
        s.grant()
        s.resetConnection()
        XCTAssertFalse(s.allowed)
        XCTAssertEqual(s.lastSequence, 0)
    }
    func testRevocation() {
        var s = RemoteConsent()
        s.grant()
        s.revoke()
        XCTAssertThrowsError(
            try s.accept(RemoteCommand(sequence: 1, action: "gain", gain: 0.5), foreground: true, pro: true))
    }
}
final class AudioTests: XCTestCase {
    func testSilenceDoesNotMakeHaptics() throws {
        var a = try AudioAnalyzer(sampleRate: 8000)
        try a.consume([Float](repeating: 0, count: 16000))
        let x = try a.finish()
        XCTAssertEqual(x.duration, 2, accuracy: 0.02)
        XCTAssertEqual(x.level(at: 1, configuration: MusicConfiguration(), overlay: nil), 0)
    }
    func testConstantEnergy() throws {
        var a = try AudioAnalyzer(sampleRate: 8000)
        try a.consume([Float](repeating: 0.4, count: 16000))
        let x = try a.finish()
        XCTAssertGreaterThan(x.level(at: 1, configuration: MusicConfiguration(), overlay: nil), 0)
    }
    func testOnsetsDetected() throws {
        var a = try AudioAnalyzer(sampleRate: 8000)
        var samples = [Float](repeating: 0, count: 48000)
        for i in stride(from: 1600, to: 48000, by: 4000) {
            for j in i..<min(i + 640, 48000) { samples[j] = 0.8 }
        }
        try a.consume(samples)
        let x = try a.finish()
        XCTAssertGreaterThan(x.onsets.count, 5)
    }
    func testAnalysisBounded() throws {
        var a = try AudioAnalyzer(sampleRate: 8000)
        XCTAssertThrowsError(try a.consume([Float](repeating: 0, count: 4_808_000)))
    }
    func testInvalidSampleRate() { XCTAssertThrowsError(try AudioAnalyzer(sampleRate: 0)) }
    func testDemoWavHasValidHeader() throws {
        let d = DemoAudio.wav(seconds: 1)
        XCTAssertEqual(String(data: d.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: d[8..<12], encoding: .ascii), "WAVE")
        XCTAssertGreaterThan(d.count, 40000)
    }
    func testZeroGainProducesSilence() throws {
        var a = try AudioAnalyzer(sampleRate: 8000)
        try a.consume([Float](repeating: 0.5, count: 8000))
        var c = MusicConfiguration()
        c.gain = 0
        XCTAssertEqual(try a.finish().level(at: 0.5, configuration: c, overlay: nil), 0)
    }
}

final class FinalRegressionTests: XCTestCase {
    func testCloudSameContentDifferentTimestampDoesNotDuplicate() throws {
        var a = LibrarySnapshot()
        var b = LibrarySnapshot()
        let original = HapticPattern(id: "same", name: "same", updatedAt: Date(timeIntervalSince1970: 10.1))
        a.custom = [original]
        var other = original
        other.updatedAt = Date(timeIntervalSince1970: 10)
        b.custom = [other]
        XCTAssertEqual(try CloudMerge.preservingBoth(local: a, remote: b).custom.count, 1)
    }
    func testCloudDuplicateIdentifiersThrowInsteadOfTrap() {
        var a = LibrarySnapshot()
        let p = HapticPattern(id: "same", name: "one")
        a.custom = [p, p]
        XCTAssertThrowsError(try CloudMerge.preservingBoth(local: a, remote: LibrarySnapshot()))
    }
    func testCloudConcurrentEditsPreserveNewItem() throws {
        var local = LibrarySnapshot()
        var incoming = LibrarySnapshot()
        local.custom = [HapticPattern(id: "new", name: "new")]
        incoming.custom = [HapticPattern(id: "old", name: "old")]
        XCTAssertEqual(
            Set(try CloudMerge.preservingBoth(local: local, remote: incoming).custom.map(\.id)),
            ["new", "old"])
    }
    func testRemoteConnectionNonceRoundtrip() throws {
        let command = RemoteCommand(
            sequence: 1, action: "start", patternID: "p02", gain: 0.3, connectionID: "fresh-connection")
        let decoded = try FileCodec.decode(RemoteCommand.self, FileCodec.encode(command))
        XCTAssertEqual(decoded.connectionID, "fresh-connection")
    }
    func testRemoteOldWireWithoutNonceDecodesForRejectionByTransport() throws {
        let data = Data(#"{"sequence":1,"action":"start","gain":0.5}"#.utf8)
        XCTAssertNil(try FileCodec.decode(RemoteCommand.self, data).connectionID)
    }
    func testFallbackPaletteHasCompletePairs() {
        XCTAssertEqual(ThemeDefinition.fallback.light.count, 12)
        XCTAssertEqual(ThemeDefinition.fallback.dark.count, 12)
    }
}
