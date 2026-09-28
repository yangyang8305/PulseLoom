#if DEBUG
import Foundation
import PulseLoomCore

/// XCTest fixture only: explicit opt-in plus a valid UUID prevents writes to normal user storage.
enum RecoveryFixture {
    static func seedIfRequested(at root: URL) throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PULSELOOM_CORRUPT_LIBRARY_FIXTURE"] == "1",
            let id = environment["PULSELOOM_UI_TEST_ID"], UUID(uuidString: id) != nil,
            root.lastPathComponent == "PulseLoom-UITests-" + id
        else { return }
        let marker = root.appendingPathComponent("fixture-seeded")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var snapshot = LibrarySnapshot()
        let pattern = HapticPattern(name: "Recovered fixture")
        snapshot.custom = [pattern]
        snapshot.preferences.onboarded = true
        snapshot.preferences.lastPattern = pattern.id
        try FileCodec.encode(snapshot).write(to: root.appendingPathComponent("library.json.previous"), options: .atomic)
        try Data("{broken-json".utf8).write(to: root.appendingPathComponent("library.json"), options: .atomic)
        try Data("seeded".utf8).write(to: marker, options: .atomic)
    }
}
#endif
