import XCTest
import Foundation
import PulseLoomCore

final class DateSafetyTests: XCTestCase {
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
