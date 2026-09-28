import Foundation
import PulseLoomCore

/// A restore must not leave a new library next to an old draft after a failed removal.
/// Persist the validated intent; finish it before loading any library on the next launch.
struct LibraryReplacement: Codable {
    let snapshot: LibrarySnapshot
    let preservePrevious: Bool
    static let markerName = "pending-replacement.json"
    private static let journalLimit = FileCodec.libraryMaxBytes * 2
    static func begin(_ snapshot: LibrarySnapshot, preservePrevious: Bool, root: URL) throws {
        try Validation.snapshot(snapshot)
        guard try FileCodec.encode(snapshot).count <= FileCodec.libraryMaxBytes else {
            throw LoomError.storage("Library exceeds the size limit. Nothing was replaced.")
        }
        try FileCodec.write(Self(snapshot: snapshot, preservePrevious: preservePrevious),
                            to: root.appendingPathComponent(markerName), maxBytes: journalLimit, preservePrevious: false)
    }
    @discardableResult static func finish(root: URL, remove: (URL) throws -> Void) throws -> Bool {
        let fm = FileManager.default
        let marker = root.appendingPathComponent(markerName)
        guard fm.fileExists(atPath: marker.path) else { return false }
        let intention = try FileCodec.read(Self.self, from: marker, maxBytes: journalLimit)
        try Validation.snapshot(intention.snapshot)
        guard try FileCodec.encode(intention.snapshot).count <= FileCodec.libraryMaxBytes else {
            throw LoomError.storage("Pending replacement exceeds the size limit.")
        }
        let library = root.appendingPathComponent("library.json")
        // Retrying a completed write must not replace a good previous backup with the replacement itself.
        let installed = try? FileCodec.read(LibrarySnapshot.self, from: library, maxBytes: FileCodec.libraryMaxBytes)
        if installed != intention.snapshot {
            try FileCodec.write(intention.snapshot, to: library, maxBytes: FileCodec.libraryMaxBytes,
                                preservePrevious: intention.preservePrevious)
        }
        let draft = root.appendingPathComponent("draft.json")
        for path in [draft, draft.appendingPathExtension("previous"), marker.appendingPathExtension("previous"), marker] {
            if fm.fileExists(atPath: path.path) { try remove(path) }
        }
        return true
    }
}
