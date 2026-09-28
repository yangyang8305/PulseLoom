import Foundation
import PulseLoomCore

/// Resumable intention is atomically written before destructive operations. Startup finishes an interrupted
/// erasure before loading old data, or fails closed with recovery controls still reachable.
struct LibraryErasure: Codable {
    enum Scope: String, Codable { case history, content }
    let scope: Scope
    let preferences: Preferences
    static let markerName = "pending-erasure.json"
    static func sanitized(_ original: Preferences) -> Preferences {
        var prefs = original
        prefs.name = ""
        prefs.lastPattern = "p02"
        prefs.widgetPattern = "p02"
        prefs.widgetPrivate = true
        prefs.historyEnabled = false
        prefs.diagnosticsEnabled = false
        return prefs
    }
    static func begin(_ scope: Scope, preferences: Preferences, root: URL) throws {
        let intention = LibraryErasure(scope: scope, preferences: sanitized(preferences))
        try FileCodec.write(intention, to: root.appendingPathComponent(markerName), preservePrevious: false)
    }
    @discardableResult static func finish(root: URL, remove: (URL) throws -> Void) throws -> Bool {
        let fm = FileManager.default
        let marker = root.appendingPathComponent(markerName)
        guard fm.fileExists(atPath: marker.path) else { return false }
        let intention = try FileCodec.read(Self.self, from: marker)
        func purge(_ url: URL) throws {
            for path in [url, url.appendingPathExtension("previous")] {
                if fm.fileExists(atPath: path.path) { try remove(path) }
            }
        }
        try purge(root.appendingPathComponent("Private/history.json"))
        if intention.scope == .content {
            try purge(root.appendingPathComponent("library.json"))
            try purge(root.appendingPathComponent("draft.json"))
            try purge(root.appendingPathComponent(LibraryReplacement.markerName))
            for name in ["Exports", "CloudStaging"] {
                let folder = root.appendingPathComponent(name)
                if fm.fileExists(atPath: folder.path) { try remove(folder) }
            }
            // Exact legacy names created by earlier app versions; never enumerate/delete unrelated files.
            for name in ["PulseLoom-pattern", "PulseLoom-patterns", "PulseLoom-backup", "PulseLoom-diagnostics", "PulseLoom-feedback"] {
                try purge(FileManager.default.temporaryDirectory.appendingPathComponent(name + ".json"))
            }
            var fresh = LibrarySnapshot()
            fresh.preferences = intention.preferences
            try FileCodec.write(fresh, to: root.appendingPathComponent("library.json"),
                                maxBytes: FileCodec.libraryMaxBytes, preservePrevious: false)
        }
        // If any removal/write above fails, leave the intention for explicit retry or next startup.
        try purge(marker)
        return true
    }
}
