import Foundation
import XCTest
import PulseLoomCore
@testable import PulseLoom

final class DataSafetyTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("PulseLoomAudit-" + UUID().uuidString) }
    func testAcceptedPersistedLibraryCanBeReopened() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        try await MainActor.run {
            let store = LibraryStore(root: folder)
            for i in 0..<30 {
                var pattern = HapticPattern(name: "item \(i)")
                pattern.description = String(repeating: "x", count: 190_000)
                let imported = try PatternImport.decode(FileCodec.encode(pattern))
                try store.save(imported, pro: true)
            }
            XCTAssertEqual(store.snapshot.custom.count, 30)
            let file = folder.appendingPathComponent("library.json")
            let size = try Data(contentsOf: file).count
            print("AUD-06 persisted bytes = \(size)")
            let reopened = LibraryStore(root: folder)
            XCTAssertNil(reopened.loadError, "AUD-06: accepted writes exceed the reader's 5MiB limit")
            XCTAssertEqual(reopened.snapshot.custom.count, 30)
        }
    }
    func testClearHistoryDeletesPreviousDiskContents() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        try await MainActor.run {
            let store = LibraryStore(root: folder)
            try store.preferences { $0.historyEnabled = true }
            store.record(title: "PRIVATE_HISTORY_SENTINEL", kind: "pattern", seconds: 1, reason: "stopped")
            try store.clearHistory()
            XCTAssertTrue(store.history.isEmpty)
            let previous = folder.appendingPathComponent("Private/history.json.previous")
            let text = (try? String(contentsOf: previous, encoding: .utf8)) ?? ""
            XCTAssertFalse(text.contains("PRIVATE_HISTORY_SENTINEL"), "AUD-04: clear-history retains the deleted entry in .previous")
        }
    }
    func testClearUserContentPurgesLibraryAndDraftCopies() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        try await MainActor.run {
            let store = LibraryStore(root: folder)
            let p = HapticPattern(name: "PRIVATE_DRAFT_SENTINEL")
            try store.save(p, pro: true)
            store.saveDraft(p); try store.flushDraft()
            var p2=p; p2.name="next"; store.saveDraft(p2); try store.flushDraft()
            try store.clearUserContent()
            XCTAssertTrue(store.snapshot.custom.isEmpty)
            let lib = (try? String(contentsOf: folder.appendingPathComponent("library.json.previous"), encoding: .utf8)) ?? ""
            let draft = (try? String(contentsOf: folder.appendingPathComponent("draft.json.previous"), encoding: .utf8)) ?? ""
            XCTAssertFalse(lib.contains("PRIVATE_DRAFT_SENTINEL"), "AUD-04: library.json.previous still contains erased user content")
            XCTAssertFalse(draft.contains("PRIVATE_DRAFT_SENTINEL"), "AUD-04: draft.json.previous is not deleted")
        }
    }
    func testClearContentInvalidatesOpenEditor() async throws {
        let folder=root(); defer { try? FileManager.default.removeItem(at: folder) }
        try await MainActor.run {
            let app=AppModel(library: LibraryStore(root: folder)); let editor=EditorModel(); editor.attach(app)
            editor.draft.name="ERASED_NAME"; editor.persist(); try app.library.flushDraft()
            try app.library.clearUserContent()
            XCTAssertNil(app.library.draft)
            // Exactly the existing CreateView onDisappear callback: editor.persist().
            editor.persist(); try app.library.flushDraft()
            XCTAssertNotEqual(app.library.draft?.name, "ERASED_NAME", "AUD-05: unchanged open EditorModel resurrects cleared draft")
        }
    }
}

import CoreHaptics

@MainActor private final class PolicyPlayer: HapticPlayerIO {
    var completionHandler: ((Error?) -> Void)?
    var loopEnabled = false
    var loopEnd = 0.0
    func start(atTime: TimeInterval) throws {}
    func stop(atTime: TimeInterval) throws {}
    func sendParameters(_ parameters: [CHHapticDynamicParameter], atTime: TimeInterval) throws {}
}
@MainActor private final class PolicyEngine: HapticEngineIO {
    var stoppedHandler: ((CHHapticEngine.StoppedReason) -> Void)?
    var resetHandler: (() -> Void)?
    var isMutedForHaptics = false
    var scheduled = 0
    func start() throws {}
    func stop(completion: @escaping (Error?) -> Void) { completion(nil) }
    func makeAdvancedPlayer(with pattern: CHHapticPattern) throws -> any HapticPlayerIO { scheduled += 1; return PolicyPlayer() }
}

@MainActor final class AccessPolicyTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("AccessPolicy-" + UUID().uuidString) }
    private func makeApp(root: URL, engine: PolicyEngine, pro: @escaping () -> Bool = { true }) -> AppModel {
        let driver = HapticDriver(makeEngine: { engine }, supportsHaptics: { true }, isForeground: { true }, thermalSafe: { true })
        return AppModel(library: LibraryStore(root: root), playback: PlaybackCoordinator(driver: driver), entitlementReader: pro)
    }
    private func assertExportBlocked(_ app: AppModel, root: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(app.share, "AUD-09: no share item may be published", file: file, line: line)
        XCTAssertNotNil(app.error, "Blocked export must explain the restriction", file: file, line: line)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Exports").path)) ?? []
        XCTAssertTrue(files.isEmpty, "No partial or restricted export may be written", file: file, line: line)
    }
    func testAUD10AppCommandBoundaryReadsLiveEntitlementNotConnectionSnapshot() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let engine = PolicyEngine(); var livePro = true
        let app = makeApp(root: root, engine: engine, pro: { livePro })
        app.remote.pro = true // Deliberately stale transport snapshot; never a real purchase.
        livePro = false
        app.remote.onCommand?(RemoteCommand(sequence: 1, action: "start", patternID: "p02"), 0.4)
        XCTAssertEqual(engine.scheduled, 0, "AUD-10: a live revoked entitlement must not acquire output")
        XCTAssertFalse(app.playback.isPlaying)
    }
    func testAUD15OldRemoteGainDoesNotRescheduleLocalSession() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let engine = PolicyEngine(); let app = makeApp(root: root, engine: engine)
        try app.beginCurrent()
        let before = engine.scheduled
        app.remote.onCommand?(RemoteCommand(sequence: 5, action: "gain", gain: 1), 1)
        XCTAssertEqual(engine.scheduled, before, "AUD-15: stale remote gain cannot change the local session")
        XCTAssertEqual(app.playback.kind, "pattern")
        XCTAssertTrue(app.playback.isPlaying, "Rejecting a foreign command must not stop local output")
        app.stopAll()
    }
    func testAUD09PaidPresetExportIsRejectedBeforeWritingOrSharing() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine())
        app.export(Catalog.presets.first { $0.premium }!, name: "paid")
        assertExportBlocked(app, root: root)
    }
    func testAUD09EditedPaidCopyStillCannotBeExported() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine()); let editor = EditorModel(); editor.attach(app)
        editor.edit(Catalog.presets.first { $0.premium }!, copy: true)
        editor.change { $0.name = "renamed"; $0.segments[0].gain = 0.1 }
        app.export(editor.draft, name: "derived")
        assertExportBlocked(app, root: root)
    }
    func testAUD09RecordingOverPaidDraftRetainsItsSource() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine()); let editor = EditorModel(); editor.attach(app)
        editor.edit(Catalog.presets.first { $0.premium }!, copy: true)
        editor.choose(.tap); editor.start(); editor.touchBegan(CGPoint(x: 0.5, y: 0.5))
        try await Task.sleep(nanoseconds: 100_000_000)
        editor.endTouch(); editor.end()
        XCTAssertTrue(editor.draft.sourcePremium, "Recording replaces shape, not the source of an existing draft")
        app.export(editor.draft, name: "recorded-derived")
        assertExportBlocked(app, root: root)
        app.stopAll()
    }
    func testAUD09OriginalWorkExportsWithAllItsSegments() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine())
        let original = HapticPattern(name: "my original")
        app.export(original, name: "original")
        XCTAssertNil(app.error)
        let url = try XCTUnwrap(app.share?.url)
        let decoded = try FileCodec.read(HapticPattern.self, from: url)
        XCTAssertEqual(decoded, original)
    }
    func testAUD09ImportedJSONCannotSelfAttestOriginality() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine())
        let imported = try PatternImport.decode(FileCodec.encode(HapticPattern(name: "claims original")))
        app.export(imported, name: "untrusted")
        assertExportBlocked(app, root: root)
    }
    func testAUD09WholeBackupWithRestrictedWorkIsBlockedNotFiltered() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine())
        let paid = Catalog.presets.first { $0.premium }!.copyForEditing()
        try app.library.save(paid, pro: true)
        try app.library.save(HapticPattern(name: "original"), pro: true)
        let before = app.library.snapshot
        app.export(before, name: "backup")
        assertExportBlocked(app, root: root)
        XCTAssertEqual(app.library.snapshot, before, "Blocked backup must not remove any works")
    }
    func testAUD09RoutineContainingPaidPresetBlocksBackup() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine())
        let paid = Catalog.presets.first { $0.premium }!
        try app.library.commit { $0.routines = [Routine(name: "mix", items: [RoutineItem(patternID: paid.id)])] }
        app.export(app.library.snapshot, name: "routine-backup")
        assertExportBlocked(app, root: root)
    }
    func testAUD09ExternalRestoreCannotCreateTrustedOriginals() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine())
        var external = LibrarySnapshot(); external.custom = [HapticPattern(name: "external claim")]
        try app.replaceLibrary(external)
        app.export(app.library.snapshot, name: "restored")
        assertExportBlocked(app, root: root)
    }
    func testSameAccountCloudPayloadIsNotAnExternalShareOperation() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine())
        let before = app.library.snapshot
        var incoming = before.cloudPayload()
        incoming.custom = [Catalog.presets.first { $0.premium }!.copyForEditing()]
        try app.applySyncResult(incoming, before: before, generation: app.library.contentGeneration)
        XCTAssertEqual(app.library.snapshot.custom.first?.sourcePremium, true)
        XCTAssertNil(app.share)
        XCTAssertNil(app.error, "Tests the local cloud-application boundary, not a real CloudKit connection")
    }
}
