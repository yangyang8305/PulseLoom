import Combine
import Foundation
import PulseLoomCore

@MainActor final class LibraryStore: ObservableObject {
    @Published private(set) var snapshot = LibrarySnapshot()
    @Published private(set) var history: [HistoryEntry] = []
    @Published var loadError: String?
    @Published var draft: HapticPattern?
    let root: URL
    @Published private(set) var contentGeneration = UUID()
    @Published private(set) var recoveryRequired = false
    private var writable = true
    private let removeFile: (URL) throws -> Void
    private var draftTask: Task<Void, Never>?
    var allPatterns: [HapticPattern] { Catalog.presets + snapshot.custom }
    init(root: URL? = nil, removeFile: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.removeFile = removeFile
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
        #if DEBUG
            do { try RecoveryFixture.seedIfRequested(at: self.root) } catch {
                failRecovery(error)
                return
            }
        #endif
        do {
            try LibraryErasure.finish(root: self.root, remove: removeFile)
            try LibraryReplacement.finish(root: self.root, remove: removeFile)
            try loadCurrentFiles()
        } catch { failRecovery(error) }
    }
    private func failRecovery(_ error: Error) {
        writable = false
        recoveryRequired = true
        loadError = error.localizedDescription
    }
    private func loadCurrentFiles() throws {
        let url = root.appendingPathComponent("library.json")
        var current = LibrarySnapshot()
        if FileManager.default.fileExists(atPath: url.path) {
            current = try FileCodec.read(LibrarySnapshot.self, from: url, maxBytes: FileCodec.libraryMaxBytes)
            try Validation.snapshot(current)
        }
        snapshot = current
        let historyURL = root.appendingPathComponent("Private/history.json")
        history = []
        if FileManager.default.fileExists(atPath: historyURL.path) {
            do { history = try FileCodec.read([HistoryEntry].self, from: historyURL); pruneHistory() }
            catch { loadError = error.localizedDescription }
        }
        draft = nil
        let draftURL = root.appendingPathComponent("draft.json")
        if FileManager.default.fileExists(atPath: draftURL.path) {
            do { draft = try FileCodec.read(HapticPattern.self, from: draftURL) }
            catch { loadError = error.localizedDescription }
        }
        writable = true
        recoveryRequired = false
    }
    private func invalidateDraftWriters() {
        draftTask?.cancel()
        draftTask = nil
        draft = nil
        contentGeneration = UUID()
    }
    private func requireWritable() throws {
        guard writable, !recoveryRequired else {
            throw LoomError.storage("The original library is preserved. Finish recovery before editing.")
        }
    }
    func pattern(_ id: String) -> HapticPattern? { allPatterns.first { $0.id == id } }
    func commit(_ change: (inout LibrarySnapshot) throws -> Void) throws {
        guard writable else {
            throw LoomError.storage("The original library is preserved. Restore a backup before editing.")
        }
        var next = snapshot
        try change(&next)
        ContentPolicy.propagate(&next, previous: snapshot)
        next.updatedAt = Date()
        try Validation.snapshot(next)
        try FileCodec.write(next, to: root.appendingPathComponent("library.json"), maxBytes: FileCodec.libraryMaxBytes)
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
    func saveDraft(_ p: HapticPattern?, generation: UUID? = nil) {
        guard writable, !recoveryRequired, generation == nil || generation == contentGeneration else { return }
        draft = p
        draftTask?.cancel()
        let expected = contentGeneration
        draftTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                guard let self, self.contentGeneration == expected, !Task.isCancelled else { return }
                try self.flushDraft()
            } catch is CancellationError {} catch { self?.loadError = error.localizedDescription }
        }
    }
    func flushDraft() throws {
        try requireWritable()
        let u = root.appendingPathComponent("draft.json")
        if let draft { try FileCodec.write(draft, to: u) }
        else { try FileCodec.erase(u) }
    }
    func restorePrevious() throws {
        // An unfinished explicit erasure takes precedence over old recovery content.
        guard !FileManager.default.fileExists(atPath: root.appendingPathComponent(LibraryErasure.markerName).path) else {
            throw LoomError.storage("Finish the pending erasure before restoring other content.")
        }
        let s = try FileCodec.read(LibrarySnapshot.self,
                                  from: root.appendingPathComponent("library.json.previous"), maxBytes: FileCodec.libraryMaxBytes)
        try replace(s, preservePrevious: false)
    }
    func replace(_ s: LibrarySnapshot, preservePrevious: Bool = true) throws {
        guard !FileManager.default.fileExists(atPath: root.appendingPathComponent(LibraryErasure.markerName).path) else {
            throw LoomError.storage("Finish the pending erasure first.")
        }
        try Validation.snapshot(s)
        try LibraryReplacement.begin(s, preservePrevious: preservePrevious, root: root)
        invalidateDraftWriters()
        writable = false
        recoveryRequired = true
        do { try LibraryReplacement.finish(root: root, remove: removeFile) }
        catch { failRecovery(error); throw error }
        snapshot = s
        writable = true
        recoveryRequired = false
        loadError = nil
    }
    /// A normal cloud refresh preserves unsaved local drafts. A restore/wipe boundary rejects old requests.
    @discardableResult func applyCloud(_ s: LibrarySnapshot, generation: UUID) throws -> Bool {
        guard generation == contentGeneration else { return false }
        try requireWritable()
        var merged = s
        ContentPolicy.propagate(&merged, previous: snapshot)
        try Validation.snapshot(merged)
        try FileCodec.write(merged, to: root.appendingPathComponent("library.json"), maxBytes: FileCodec.libraryMaxBytes)
        snapshot = merged
        return true
    }
    func retryRecovery() throws {
        invalidateDraftWriters()
        do {
            try LibraryErasure.finish(root: root, remove: removeFile)
            try LibraryReplacement.finish(root: root, remove: removeFile)
            loadError = nil
            try loadCurrentFiles()
        } catch { failRecovery(error); throw error }
    }
    func record(title: String, kind: String, seconds: Double, reason: String) {
        guard writable, !recoveryRequired, snapshot.preferences.historyEnabled, seconds > 0 else { return }
        history.insert(HistoryEntry(title: title, kind: kind, seconds: seconds, reason: reason), at: 0)
        pruneHistory()
        do { try saveHistory() } catch { loadError = error.localizedDescription }
    }
    func clearHistory() throws {
        try requireWritable()
        try LibraryErasure.begin(.history, preferences: snapshot.preferences, root: root)
        history = []
        do { try LibraryErasure.finish(root: root, remove: removeFile) }
        catch { failRecovery(error); throw error }
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
        // Record intent first. If that fails, no old writer or content is changed.
        try LibraryErasure.begin(.content, preferences: snapshot.preferences, root: root)
        invalidateDraftWriters()
        writable = false
        recoveryRequired = true
        history = []
        do {
            try LibraryErasure.finish(root: root, remove: removeFile)
            try LibraryReplacement.finish(root: root, remove: removeFile)
            loadError = nil
            try loadCurrentFiles()
        } catch { failRecovery(error); throw error }
    }
}
extension Notification.Name { static let loomLibraryChanged = Notification.Name("PulseLoom.libraryChanged") }
