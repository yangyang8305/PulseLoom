import Foundation
import SwiftUI
import XCTest
import PulseLoomCore
@testable import PulseLoom

private enum RemovalFault: Error { case denied }

@MainActor final class StorageBoundaryTests: XCTestCase {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PulseLoom-Boundary-" + UUID().uuidString)
    }
    private func assertAbsent(_ paths: [String], root: URL, file: StaticString = #filePath, line: UInt = #line) {
        for path in paths { XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), path, file: file, line: line) }
    }
    func testHistoryErasureRemovesBothFilesAndPreservesUnrelatedContent() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let pattern = HapticPattern(name: "keep this draft")
        try store.save(pattern, pro: false)
        store.saveDraft(pattern); try store.flushDraft()
        try store.preferences { $0.historyEnabled = true }
        store.record(title: "private history", kind: "pattern", seconds: 1, reason: "stop")
        store.record(title: "another private history", kind: "pattern", seconds: 1, reason: "stop")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Private/history.json.previous").path))
        try store.clearHistory()
        assertAbsent(["Private/history.json", "Private/history.json.previous", LibraryErasure.markerName], root: root)
        XCTAssertEqual(store.draft?.name, pattern.name)
        XCTAssertEqual(store.snapshot.custom.map(\.id), [pattern.id])
        let reopened = LibraryStore(root: root)
        XCTAssertFalse(reopened.recoveryRequired)
        XCTAssertTrue(reopened.history.isEmpty)
        XCTAssertEqual(reopened.draft?.name, pattern.name)
    }
    func testInterruptedPrivacyErasureFailsClosedAndFinishesBeforeNextLoad() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        var denied = false
        let store = LibraryStore(root: root, removeFile: { url in
            if !denied && url.lastPathComponent == "library.json.previous" {
                denied = true
                throw RemovalFault.denied
            }
            try FileManager.default.removeItem(at: url)
        })
        let pattern = HapticPattern(name: "must not come back")
        try store.save(pattern, pro: false)
        try store.preferences { $0.name = "private name"; $0.historyEnabled = true }
        store.saveDraft(pattern); try store.flushDraft()
        store.record(title: "private history", kind: "pattern", seconds: 1, reason: "stop")
        let epoch = store.contentGeneration
        do { try store.clearUserContent(); XCTFail("Injected removal failure was ignored") }
        catch RemovalFault.denied {}
        XCTAssertTrue(store.recoveryRequired)
        XCTAssertNotEqual(store.contentGeneration, epoch)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(LibraryErasure.markerName).path))
        XCTAssertThrowsError(try store.save(pattern, pro: false))
        store.saveDraft(pattern, generation: epoch)
        XCTAssertNil(store.draft)
        let reopened = LibraryStore(root: root)
        XCTAssertNil(reopened.loadError)
        XCTAssertFalse(reopened.recoveryRequired)
        XCTAssertTrue(reopened.snapshot.custom.isEmpty)
        XCTAssertEqual(reopened.snapshot.preferences.name, "")
        XCTAssertTrue(reopened.history.isEmpty)
        XCTAssertNil(reopened.draft)
        assertAbsent(["library.json.previous", "draft.json", "draft.json.previous", "Private/history.json", "Private/history.json.previous", LibraryErasure.markerName], root: root)
    }
    func testRestoreFailureCannotLeaveAnOldDraftAlongsideNewLibrary() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        var deny = false
        let store = LibraryStore(root: root, removeFile: { url in
            if deny && url.lastPathComponent == "draft.json" { throw RemovalFault.denied }
            try FileManager.default.removeItem(at: url)
        })
        let old = HapticPattern(name: "old private draft")
        try store.save(old, pro: false)
        store.saveDraft(old); try store.flushDraft()
        var replacement = LibrarySnapshot()
        replacement.custom = [HapticPattern(name: "restored content")]
        deny = true
        do { try store.replace(replacement); XCTFail("Injected removal failure was ignored") }
        catch RemovalFault.denied {}
        XCTAssertTrue(store.recoveryRequired)
        XCTAssertNil(store.draft)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(LibraryReplacement.markerName).path))
        let previous = try FileCodec.read(LibrarySnapshot.self, from: root.appendingPathComponent("library.json.previous"), maxBytes: FileCodec.libraryMaxBytes)
        XCTAssertEqual(previous.custom.first?.id, old.id)
        let reopened = LibraryStore(root: root)
        XCTAssertFalse(reopened.recoveryRequired)
        XCTAssertEqual(reopened.snapshot, replacement)
        XCTAssertNil(reopened.draft)
        let stillPrevious = try FileCodec.read(LibrarySnapshot.self, from: root.appendingPathComponent("library.json.previous"), maxBytes: FileCodec.libraryMaxBytes)
        XCTAssertEqual(stillPrevious, previous, "Retrying recovery must not rotate a good backup to the replacement itself")
        assertAbsent(["draft.json", "draft.json.previous", LibraryReplacement.markerName], root: root)
    }
    func testFullErasureSupersedesPendingReplacementJournal() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        var replacement = LibrarySnapshot(); replacement.custom = [HapticPattern(name: "do not restore")]
        try LibraryReplacement.begin(replacement, preservePrevious: true, root: root)
        try store.clearUserContent()
        let reopened = LibraryStore(root: root)
        XCTAssertTrue(reopened.snapshot.custom.isEmpty)
        XCTAssertFalse(reopened.recoveryRequired)
        assertAbsent([LibraryReplacement.markerName, LibraryErasure.markerName], root: root)
    }
    func testOldEditorBindingsUndoAndDebouncedSaveCannotResurrectErasedContent() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = AppModel(library: LibraryStore(root: root)); let editor = EditorModel(); editor.attach(app)
        editor.draft.name = "private checkpoint"
        editor.beginEditingGesture()
        let name = editor.nameBinding
        let gain = editor.segmentBinding(\.gain)
        gain.wrappedValue = 0.9
        editor.persist()
        let epoch = app.library.contentGeneration
        try app.clearLocalContent()
        editor.refreshLibraryBoundary()
        name.wrappedValue = "late private input"
        gain.wrappedValue = 0.8
        editor.endEditingGesture()
        editor.undo()
        editor.redo()
        app.library.saveDraft(HapticPattern(name: "late captured snapshot"), generation: epoch)
        try await Task.sleep(nanoseconds: 650_000_000)
        try app.library.flushDraft()
        XCTAssertFalse(editor.canUndo)
        XCTAssertFalse(editor.canRedo)
        XCTAssertNotEqual(editor.draft.name, "late private input")
        XCTAssertNotEqual(app.library.draft?.name, "private checkpoint")
        XCTAssertNotEqual(app.library.draft?.name, "late captured snapshot")
        let reopened = LibraryStore(root: root)
        XCTAssertNotEqual(reopened.draft?.name, "private checkpoint")
        editor.nameBinding.wrappedValue = "new work"
        editor.persist(); try app.library.flushDraft()
        XCTAssertEqual(app.library.draft?.name, "new work", "New edits must remain possible after erasure")
    }
    func testErasureInvalidatesAnActiveRecordingAndLateEndCallback() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = AppModel(library: LibraryStore(root: root)); let editor = EditorModel(); editor.attach(app)
        editor.draft.name = "old recording"
        editor.start()
        let take = editor.recordingID
        editor.touchBegan(CGPoint(x: 0.5, y: 0.5))
        try app.library.clearUserContent()
        editor.endTouch(recording: take)
        editor.end()
        editor.persist()
        XCTAssertFalse(editor.recording)
        XCTAssertFalse(editor.down)
        XCTAssertNotEqual(editor.draft.name, "old recording")
        XCTAssertNotEqual(app.library.draft?.name, "old recording")
    }
    func testLateCloudResultCannotCrossEraseOrRestoreBoundary() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = AppModel(library: LibraryStore(root: root))
        let before = app.library.snapshot; let epoch = app.library.contentGeneration
        var reply = before; reply.custom = [HapticPattern(name: "old request")]
        try app.clearLocalContent()
        try app.applySyncResult(reply, before: before, generation: epoch)
        XCTAssertTrue(app.library.snapshot.custom.isEmpty)
        let nextEpoch = app.library.contentGeneration; let nextBefore = app.library.snapshot
        var replacement = LibrarySnapshot(); replacement.custom = [HapticPattern(name: "explicit restore")]
        try app.replaceLibrary(replacement)
        try app.applySyncResult(reply, before: nextBefore, generation: nextEpoch)
        XCTAssertEqual(app.library.snapshot.custom.map(\.name), ["explicit restore"])
    }
    func testOrdinaryCloudRefreshPreservesUnsavedEditorDraft() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = AppModel(library: LibraryStore(root: root)); let editor = EditorModel(); editor.attach(app)
        editor.nameBinding.wrappedValue = "unsaved local work"
        let before = app.library.snapshot; let epoch = app.library.contentGeneration
        var reply = before; reply.custom = [HapticPattern(name: "incoming")]
        try app.applySyncResult(reply, before: before, generation: epoch)
        XCTAssertEqual(app.library.contentGeneration, epoch)
        XCTAssertEqual(editor.draft.name, "unsaved local work")
        XCTAssertEqual(app.library.draft?.name, "unsaved local work")
        XCTAssertEqual(app.library.snapshot.custom.map(\.name), ["incoming"])
        try app.library.flushDraft()
    }
    func testErasureCancelsDeferredShareAndRemovesOwnedExportCopies() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = AppModel(library: LibraryStore(root: root))
        app.sheet = .themes
        app.export(HapticPattern(name: "private export"), name: "PulseLoom-pattern")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Exports/PulseLoom-pattern.json").path))
        try app.clearLocalContent()
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(app.share)
        assertAbsent(["Exports", "CloudStaging"], root: root)
    }
    func testPrivateExportsAreExcludedFromDeviceBackup() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = AppModel(library: LibraryStore(root: root))
        app.export(HapticPattern(name: "private export"), name: "PulseLoom-pattern")
        XCTAssertNil(app.error)
        let folder = root.appendingPathComponent("Exports")
        XCTAssertEqual(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        app.exportDiagnostics()
        XCTAssertNil(app.error)
        XCTAssertEqual(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        try app.clearLocalContent()
        assertAbsent(["Exports"], root: root)
    }
    func testOverLimitSaveDoesNotReplaceMemoryPrimaryOrPreviousFile() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try store.save(HapticPattern(name: "keep"), pro: false)
        try store.preferences { $0.name = "before" }
        let snapshot = store.snapshot
        let primary = try Data(contentsOf: root.appendingPathComponent("library.json"))
        let previous = try Data(contentsOf: root.appendingPathComponent("library.json.previous"))
        var large = HapticPattern(name: "too large")
        large.description = String(repeating: "x", count: FileCodec.libraryMaxBytes)
        do { try store.save(large, pro: false); XCTFail("An over-limit write must fail before changing either file") }
        catch let error as LoomError {
            guard case .storage = error else { return XCTFail("Wrong failure path: \(error)") }
        }
        XCTAssertEqual(store.snapshot, snapshot)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library.json")), primary)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library.json.previous")), previous)
        XCTAssertEqual(LibraryStore(root: root).snapshot, snapshot)
    }
    func testCorruptLibraryIsPreservedUntilExplicitRecoveryAndAllowsFreshStart() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = Data("{invalid".utf8)
        try original.write(to: root.appendingPathComponent("library.json"))
        let store = LibraryStore(root: root)
        XCTAssertTrue(store.recoveryRequired)
        XCTAssertThrowsError(try store.preferences { $0.onboarded = true })
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library.json")), original)
        try store.clearUserContent()
        XCTAssertFalse(store.recoveryRequired)
        try store.preferences { $0.onboarded = true }
        XCTAssertTrue(LibraryStore(root: root).snapshot.preferences.onboarded)
    }
}
