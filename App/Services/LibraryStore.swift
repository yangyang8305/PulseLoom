import Combine
import Foundation
import PulseLoomCore

@MainActor final class LibraryStore: ObservableObject {
    @Published private(set) var snapshot = LibrarySnapshot()
    @Published private(set) var history: [HistoryEntry] = []
    @Published var loadError: String?
    @Published var draft: HapticPattern?
    let root: URL
    private var writable = true
    private var draftTask: Task<Void, Never>?
    var allPatterns: [HapticPattern] { Catalog.presets + snapshot.custom }
    init(root: URL? = nil) {
        var resolved = root
        #if DEBUG
            if resolved == nil, let testID = ProcessInfo.processInfo.environment["PULSELOOM_UI_TEST_ID"],
                UUID(uuidString: testID) != nil
            {
                resolved = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "PulseLoom-UITests-" + testID, isDirectory: true)
            }
        #endif
        self.root =
            resolved
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PulseLoom", isDirectory: true)
        let url = self.root.appendingPathComponent("library.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let s = try FileCodec.read(LibrarySnapshot.self, from: url)
                try Validation.snapshot(s)
                snapshot = s
            } catch {
                loadError = error.localizedDescription
                writable = false
            }
        }
        let historyURL = self.root.appendingPathComponent("Private/history.json")
        if FileManager.default.fileExists(atPath: historyURL.path) {
            do {
                history = try FileCodec.read([HistoryEntry].self, from: historyURL)
                pruneHistory()
            } catch { loadError = error.localizedDescription }
        }
        let draftURL = self.root.appendingPathComponent("draft.json")
        if FileManager.default.fileExists(atPath: draftURL.path) {
            do { draft = try FileCodec.read(HapticPattern.self, from: draftURL) } catch {
                loadError = error.localizedDescription
            }
        }
    }
    func pattern(_ id: String) -> HapticPattern? { allPatterns.first { $0.id == id } }
    func commit(_ change: (inout LibrarySnapshot) throws -> Void) throws {
        guard writable else {
            throw LoomError.storage("The original library is preserved. Restore a backup before editing.")
        }
        var next = snapshot
        try change(&next)
        next.updatedAt = Date()
        try Validation.snapshot(next)
        try FileCodec.write(next, to: root.appendingPathComponent("library.json"))
        snapshot = next
        NotificationCenter.default.post(name: .loomLibraryChanged, object: nil)
    }
    func preferences(_ change: (inout Preferences) -> Void) throws { try commit { change(&$0.preferences) } }
    func save(_ p: HapticPattern, pro: Bool) throws {
        try Validation.pattern(p)
        guard !p.builtin else { throw LoomError.invalid("Create a copy before editing a preset.") }
        let isNew = !snapshot.custom.contains { $0.id == p.id }
        guard Entitlements.canSave(isNew: isNew, count: snapshot.custom.count, pro: pro) else {
            throw LoomError.entitlement
        }
        try commit { s in
            var p = p
            p.updatedAt = Date()
            if let i = s.custom.firstIndex(where: { $0.id == p.id }) {
                s.custom[i] = p
            } else {
                s.custom.insert(p, at: 0)
            }
            s.tombstones.removeValue(forKey: p.id)
        }
    }
    func delete(_ id: String) throws {
        try commit { s in
            s.custom.removeAll { $0.id == id }
            s.favorites.removeAll { $0 == id }
            s.tombstones[id] = Date()
            s.routines = s.routines.compactMap { r in
                var r = r
                r.items.removeAll { $0.patternID == id }
                return r.items.isEmpty ? nil : r
            }
            if s.preferences.lastPattern == id { s.preferences.lastPattern = "p02" }
        }
    }
    func favorite(_ id: String) throws {
        guard pattern(id) != nil else { throw LoomError.invalid("Pattern no longer exists.") }
        try commit { s in
            if s.favorites.contains(id) { s.favorites.removeAll { $0 == id } } else { s.favorites.append(id) }
        }
    }
    func saveDraft(_ p: HapticPattern?) {
        draft = p
        draftTask?.cancel()
        draftTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                try self?.flushDraft()
            } catch is CancellationError {} catch { self?.loadError = error.localizedDescription }
        }
    }
    func flushDraft() throws {
        guard writable else { throw LoomError.storage("Cannot overwrite a library awaiting recovery.") }
        let u = root.appendingPathComponent("draft.json")
        if let draft {
            try FileCodec.write(draft, to: u)
        } else if FileManager.default.fileExists(atPath: u.path) {
            try FileManager.default.removeItem(at: u)
        }
    }
    func restorePrevious() throws {
        let s = try FileCodec.read(
            LibrarySnapshot.self, from: root.appendingPathComponent("library.json.previous"))
        try Validation.snapshot(s)
        try FileCodec.write(s, to: root.appendingPathComponent("library.json"))
        snapshot = s
        writable = true
        loadError = nil
    }
    func replace(_ s: LibrarySnapshot) throws {
        try Validation.snapshot(s)
        try FileCodec.write(s, to: root.appendingPathComponent("library.json"))
        snapshot = s
        writable = true
        loadError = nil
    }
    func record(title: String, kind: String, seconds: Double, reason: String) {
        guard snapshot.preferences.historyEnabled, seconds > 0 else { return }
        history.insert(HistoryEntry(title: title, kind: kind, seconds: seconds, reason: reason), at: 0)
        pruneHistory()
        do { try saveHistory() } catch { loadError = error.localizedDescription }
    }
    func clearHistory() throws {
        history = []
        try saveHistory()
    }
    private func pruneHistory() {
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        history = Array(history.filter { $0.date > cutoff }.prefix(100))
    }
    private func saveHistory() throws {
        let u = root.appendingPathComponent("Private/history.json")
        try FileCodec.write(history, to: u)
        var folder = u.deletingLastPathComponent()
        var flags = URLResourceValues()
        flags.isExcludedFromBackup = true
        try folder.setResourceValues(flags)
    }
    func clearUserContent() throws {
        var fresh = LibrarySnapshot()
        fresh.preferences = snapshot.preferences
        fresh.preferences.lastPattern = "p02"
        try replace(fresh)
        draft = nil
        try flushDraft()
        try clearHistory()
    }
}
extension Notification.Name { static let loomLibraryChanged = Notification.Name("PulseLoom.libraryChanged") }
