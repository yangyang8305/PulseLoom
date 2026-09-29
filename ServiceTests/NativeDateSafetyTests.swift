import XCTest
import Foundation
import PulseLoomCore

/// Same contract runs under Apple Foundation as well as Linux Foundation.
final class NativeDateSafetyTests: XCTestCase {
    func testCloudDeleteThenLaterEditSurvivesSerialization() throws {
        var local = LibrarySnapshot(); var remote = LibrarySnapshot()
        local.custom = [HapticPattern(id: "same", name: "later edit", updatedAt: Date(timeIntervalSince1970: 100.9))]
        remote.tombstones["same"] = Date(timeIntervalSince1970: 100.1)
        XCTAssertEqual(try CloudMerge.preservingBoth(local: local, remote: remote).custom.count, 1)
        let serializedLocal = try FileCodec.decode(LibrarySnapshot.self, FileCodec.encode(local))
        let serializedRemote = try FileCodec.decode(LibrarySnapshot.self, FileCodec.encode(remote))
        XCTAssertEqual(try CloudMerge.preservingBoth(local: serializedLocal, remote: serializedRemote).custom.count, 1, "AUD-08: ISO8601 drops subseconds and a later edit is incorrectly deleted")
    }
}

import CoreHaptics
import CloudKit
@testable import PulseLoom

@MainActor private final class P2Player: HapticPlayerIO {
    var completionHandler: ((Error?) -> Void)?
    var loopEnabled = false
    var loopEnd = 0.0
    func start(atTime: TimeInterval) throws {}
    func stop(atTime: TimeInterval) throws {}
    func sendParameters(_ parameters: [CHHapticDynamicParameter], atTime: TimeInterval) throws {}
}
@MainActor private final class P2Engine: HapticEngineIO {
    var stoppedHandler: ((CHHapticEngine.StoppedReason) -> Void)?
    var resetHandler: (() -> Void)?
    var isMutedForHaptics = false
    let player = P2Player()
    func start() throws {}
    func stop(completion: @escaping (Error?) -> Void) { completion(nil) }
    func makeAdvancedPlayer(with pattern: CHHapticPattern) throws -> any HapticPlayerIO { player }
}
@MainActor final class P2ProductRegressionTests: XCTestCase {
    private func root() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: u) }
        return u
    }
    private func app() throws -> AppModel {
        let engine = P2Engine()
        let driver = HapticDriver(makeEngine: { engine }, supportsHaptics: { true }, isForeground: { true }, thermalSafe: { true })
        return AppModel(library: LibraryStore(root: try root()), playback: PlaybackCoordinator(driver: driver))
    }
    func testAUD11UndoRestoresToolAsWellAsPattern() throws {
        let model = try app(); let editor = EditorModel(); editor.attach(model)
        editor.choose(.basic); let before = editor.draft
        editor.choose(.curve); editor.undo()
        XCTAssertEqual(editor.tool, .basic)
        XCTAssertEqual(editor.draft, before)
        editor.redo()
        XCTAssertEqual(editor.tool, .curve)
        XCTAssertEqual(editor.draft.mode, .curve)
    }
    func testAUD12ShortestCurveConvertsToValidBasicPattern() throws {
        let model = try app(); let editor = EditorModel(); editor.attach(model)
        let curve = HapticPattern(name: "short", mode: .curve, segments: [], nodes: [CurveNode(time: 0, value: 0.5), CurveNode(time: 100, value: 0.5)], cycle: 100)
        editor.edit(curve); editor.choose(.basic)
        XCTAssertNoThrow(try Validation.pattern(editor.draft))
        XCTAssertEqual(editor.draft.durationMS, 100, accuracy: 0.001)
    }
    func testAUD14UndoLastXYTouchRemovesTheGesture() throws {
        let model = try app(); let editor = EditorModel(); editor.attach(model)
        editor.choose(.xy); editor.start()
        editor.touchBegan(CGPoint(x: 0.2, y: 0.3)); editor.endTouch()
        editor.removeLastTouch(); editor.end()
        XCTAssertEqual(editor.draft.mode, .basic, "Undoing the only XY gesture must not commit that gesture into a recording")
        XCTAssertEqual(editor.draft.segments.count, 4)
    }
    func testAUD16RoutineRetainsRequestedSoundscape() throws {
        let model = try app()
        let r = Routine(name: "routine", items: [RoutineItem(patternID: "p02", seconds: 15)], sound: true)
        // Same ordering as RoutinesView: sound first, followed by the public routine API.
        try model.sound.play()
        try model.playback.playRoutine(r, resolver: { model.library.pattern($0) }, pro: false)
        XCTAssertTrue(model.sound.active, "Starting the routine must not immediately stop its requested soundscape")
        model.stopAll()
        XCTAssertFalse(model.sound.active)
    }
    func testAUD17PausePublishesStoppedStateToWatch() async throws {
        let model = try app(); try model.beginCurrent()
        XCTAssertEqual(Mirror(reflecting: model.watch).children.first { $0.label == "lastPlaying" }?.value as? Bool, true)
        model.playback.pause()
        // One main-actor delivery turn is allowed; a timeout does not count as success.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(Mirror(reflecting: model.watch).children.first { $0.label == "lastPlaying" }?.value as? Bool, false)
        model.stopAll()
    }
    func testAUD22UploadPreparationFailureLeavesRetryableState() async throws {
        let folder = try root(), staging = folder.appendingPathComponent("blocked")
        try Data([1]).write(to: staging)
        var local = LibrarySnapshot(), remote = LibrarySnapshot()
        local.custom = [HapticPattern(name: "local")]; remote.custom = [HapticPattern(name: "remote")]
        let payload = folder.appendingPathComponent("remote.json")
        try FileCodec.write(remote, to: payload, maxBytes: FileCodec.libraryMaxBytes)
        let record = CKRecord(recordType: "PulseLoomLibrary", recordID: CKRecord.ID(recordName: "PulseLoom.Library.v1"))
        record["payload"] = CKAsset(fileURL: payload)
        let backend = CloudBackend(load: { _ in record }, save: { $0 }, delete: { _ in })
        let service = CloudSyncService(stagingRoot: staging, backend: backend)
        _ = try await service.synchronize(local)
        XCTAssertEqual(service.state, .conflict)
        do { _ = try await service.resolve(local: local, choice: "local"); XCTFail("Expected file system failure") } catch {}
        XCTAssertEqual(service.state, .failed, "Preparation failures must leave syncing and allow retry")
        try FileManager.default.removeItem(at: staging)
        do {
            _ = try await service.resolve(local: local, choice: "local")
            XCTAssertEqual(service.state, .ready)
        } catch { XCTFail("Retry must be possible: \(error)") }
        service.disable()
    }
}

@MainActor final class P2LifecycleControlTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func app(now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) throws -> AppModel {
        let engine = P2Engine()
        let driver = HapticDriver(makeEngine: { engine }, supportsHaptics: { true }, isForeground: { true }, thermalSafe: { true })
        return AppModel(library: LibraryStore(root: try root()), playback: PlaybackCoordinator(driver: driver, now: now))
    }
    func testUndoFlushesLiveGestureAndKeepsToolCoherent() throws {
        let m = try app(), e = EditorModel(); e.attach(m); e.choose(.basic)
        let binding = e.segmentBinding(\.gain), original = e.draft
        binding.wrappedValue = 0.8
        e.undo()
        XCTAssertEqual(e.draft, original)
        XCTAssertEqual(e.tool, .basic)
        e.redo()
        XCTAssertEqual(e.draft.segments[0].gain, 0.8)
    }
    func testCurveConversionAcrossAllSupportedLengths() throws {
        let m = try app(), e = EditorModel(); e.attach(m)
        for duration in [100.0, 101, 799, 800, 12000, 30000] {
            let p = HapticPattern(name: "curve", mode: .curve, segments: [], nodes: [CurveNode(time: 0, value: 0.5), CurveNode(time: duration, value: 0.5)], cycle: duration)
            e.edit(p); e.choose(.basic)
            XCTAssertNoThrow(try Validation.pattern(e.draft))
            XCTAssertEqual(e.draft.durationMS, duration, accuracy: 0.001)
            XCTAssertLessThanOrEqual(e.draft.segments.count, 16)
            e.undo(); XCTAssertEqual(e.tool, .curve); XCTAssertEqual(e.draft, p)
        }
    }
    func testUndoXYStrokeRetainsEarlierGesture() throws {
        let m = try app(), e = EditorModel(); e.attach(m); e.choose(.xy); e.start()
        e.touchBegan(CGPoint(x: 0.2, y: 0.2)); e.endTouch()
        e.touchBegan(CGPoint(x: 0.9, y: 0.9)); e.endTouch()
        e.removeLastTouch(); e.end()
        XCTAssertEqual(e.draft.mode, .recorded)
        XCTAssertFalse(e.draft.segments.contains { abs($0.sharp - 0.9) < 0.001 })
        XCTAssertTrue(e.draft.segments.contains { abs($0.sharp - 0.2) < 0.001 && $0.gain > 0 })
        e.removeLastTouch()
        XCTAssertEqual(e.draft.mode, .basic)
        XCTAssertEqual(e.draft.segments.count, 4)
    }
    func testRoutineSoundSurvivesStepAdvanceAndStopsOnCompletion() throws {
        var now = 0.0
        let m = try app(now: { now })
        let r = Routine(name: "routine", items: [RoutineItem(patternID: "p02", seconds: 15), RoutineItem(patternID: "p03", seconds: 15)], sound: true)
        try m.playRoutine(r)
        XCTAssertTrue(m.sound.active)
        now = 16; m.playback.tick()
        XCTAssertEqual(m.playback.routineIndex, 1); XCTAssertTrue(m.sound.active)
        m.playback.pause(); XCTAssertFalse(m.sound.active)
        try m.playback.resume(); XCTAssertTrue(m.sound.active)
        now = 32; m.playback.tick()
        XCTAssertEqual(m.playback.state, .completed); XCTAssertFalse(m.sound.active)
        XCTAssertEqual(Mirror(reflecting: m.watch).children.first { $0.label == "lastPlaying" }?.value as? Bool, false)
    }
    func testCloudDeletionWithoutBackendReportsNoRequest() async throws {
        let s = CloudSyncService(stagingRoot: try root())
        do { try await s.deleteCloud(); XCTFail("An absent backend cannot count as deleted") }
        catch { XCTAssertEqual(s.state, .off) }
    }
    func testCancelledCloudRequestLeavesRetryableState() async throws {
        var task: Task<Void, Never>?
        let backend = CloudBackend(load: { _ in task?.cancel(); throw CancellationError() }, save: { $0 }, delete: { _ in })
        let s = CloudSyncService(stagingRoot: try root(), backend: backend)
        task = Task { @MainActor in
            do { _ = try await s.synchronize(LibrarySnapshot()); XCTFail("Expected cancellation") } catch {}
        }
        await task?.value
        XCTAssertEqual(s.state, .failed)
        s.disable(); XCTAssertEqual(s.state, .off)
    }
    func testLateCloudResultAfterDisableDoesNotRestoreState() async throws {
        var started = false
        var continuation: CheckedContinuation<CKRecord?, Error>?
        let backend = CloudBackend(load: { _ in started = true; return try await withCheckedThrowingContinuation { continuation = $0 } }, save: { $0 }, delete: { _ in })
        let s = CloudSyncService(stagingRoot: try root(), backend: backend)
        let task = Task { @MainActor in
            do { _ = try await s.synchronize(LibrarySnapshot()); XCTFail("Old result must be cancelled") } catch {}
        }
        for _ in 0..<100 where !started { await Task.yield() }
        XCTAssertTrue(started)
        s.disable(); continuation?.resume(returning: nil)
        await task.value
        XCTAssertEqual(s.state, .off); XCTAssertNil(s.lastSync)
    }
}


import AppIntents

@MainActor final class PlatformContractTests: XCTestCase {
    func testAUD18PublishingWidgetPreservesExplicitAppearance() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppModel(library: LibraryStore(root: root))
        let group = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: group))
        let prior = defaults.object(forKey: "appearance")
        defer { if let prior { defaults.set(prior, forKey: "appearance") } else { defaults.removeObject(forKey: "appearance") } }
        try app.library.preferences { $0.appearance = .dark; $0.theme = "blush" }
        app.publishWidget()
        XCTAssertEqual(defaults.string(forKey: "appearance"), "dark")
        try app.library.preferences { $0.appearance = .light }
        app.publishWidget()
        XCTAssertEqual(defaults.string(forKey: "appearance"), "light")
        app.stopAll()
    }
    func testAUD19ShortcutRejectsUnresolvablePresetInsteadOfReportingSuccess() async throws {
        let group = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: group))
        defaults.removeObject(forKey: "shortcutPattern")
        defer { defaults.removeObject(forKey: "shortcutPattern") }
        var intent = OpenPulseLoomIntent()
        intent.pattern = PresetEntity(id: "unknown-injected-id", name: "not a preset")
        do { _ = try await intent.perform(); XCTFail("Unknown entity must not produce success or a stored command") } catch {}
        XCTAssertNil(defaults.string(forKey: "shortcutPattern"))
    }
}

@MainActor final class PlatformPositiveTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let group = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String)
        return try XCTUnwrap(UserDefaults(suiteName: group))
    }
    func testAutomaticWidgetAppearanceIsPublishedWithoutRevealingPrivateTitle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let m = AppModel(library: LibraryStore(root: root)), d = try defaults()
        let previous = ["appearance", "title", "theme", "patternID", "widgetPalette"].map { ($0, d.object(forKey: $0)) }
        defer {
            for (key, value) in previous {
                if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
            }
            m.stopAll()
        }
        try m.library.preferences { $0.appearance = .auto; $0.theme = "night"; $0.widgetPrivate = true }
        m.publishWidget()
        XCTAssertEqual(d.string(forKey: "appearance"), "auto")
        XCTAssertEqual(d.string(forKey: "title"), T("widget.privateTitle"))
        let theme = try XCTUnwrap(Catalog.themes.first { $0.id == "night" })
        let palettes = try XCTUnwrap(d.dictionary(forKey: "widgetPalette"))
        XCTAssertEqual(palettes["light"] as? [String], [theme.light[0], theme.light[5], theme.light[4]])
        XCTAssertEqual(palettes["dark"] as? [String], [theme.dark[0], theme.dark[5], theme.dark[4]])
    }
    func testPlainOpenSupersedesStaleSelectionWithoutStartingPlayback() async throws {
        let d = try defaults(), prior = d.object(forKey: "shortcutPattern")
        defer { if let prior { d.set(prior, forKey: "shortcutPattern") } else { d.removeObject(forKey: "shortcutPattern") } }
        d.set("p02", forKey: "shortcutPattern")
        let intent = OpenPulseLoomIntent()
        _ = try await intent.perform()
        XCTAssertNil(d.string(forKey: "shortcutPattern"))
    }
    func testKnownPresetCanResolveAndPerformNavigation() async throws {
        let ids = ["p02", "nonexistent"]
        let entities = try await PresetQuery().entities(for: ids)
        XCTAssertEqual(entities.map(\.id), ["p02"])
        let d = try defaults(), prior = d.object(forKey: "shortcutPattern")
        defer { if let prior { d.set(prior, forKey: "shortcutPattern") } else { d.removeObject(forKey: "shortcutPattern") } }
        var intent = OpenPulseLoomIntent()
        intent.pattern = try XCTUnwrap(entities.first)
        // perform emits navigation only; actual Siri discovery remains a separate acceptance task.
        _ = try await intent.perform()
    }
}
