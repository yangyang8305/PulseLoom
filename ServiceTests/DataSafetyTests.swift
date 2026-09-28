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
