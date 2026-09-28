import Foundation
import XCTest
import PulseLoomCore

final class CodecBoundaryTests: XCTestCase {
    func testExactSubsecondDatesRoundTripWithoutOrderingLoss() throws {
        for reference in [-978307099.9, -978307099.1, 0, 812345678.123456, 812345678.123457] {
            let date = Date(timeIntervalSinceReferenceDate: reference)
            XCTAssertEqual(try FileCodec.decode(Date.self, FileCodec.encode(date)), date)
        }
    }
    func testLegacyISO8601DatesWithAndWithoutFractionsRemainReadable() throws {
        XCTAssertEqual(try FileCodec.decode(Date.self, Data("\"1970-01-01T00:01:40Z\"".utf8)), Date(timeIntervalSince1970: 100))
        let fractional = try FileCodec.decode(Date.self, Data("\"1970-01-01T00:01:40.900Z\"".utf8))
        XCTAssertEqual(fractional.timeIntervalSince1970, 100.9, accuracy: 0.000001)
    }
    func testNewerTombstoneStillWinsAfterRoundTrip() throws {
        var local = LibrarySnapshot(); var remote = LibrarySnapshot()
        local.custom = [HapticPattern(id: "same", name: "old edit", updatedAt: Date(timeIntervalSince1970: 100.1))]
        remote.tombstones["same"] = Date(timeIntervalSince1970: 100.9)
        let lhs = try FileCodec.decode(LibrarySnapshot.self, FileCodec.encode(local))
        let rhs = try FileCodec.decode(LibrarySnapshot.self, FileCodec.encode(remote))
        XCTAssertTrue(try CloudMerge.preservingBoth(local: lhs, remote: rhs).custom.isEmpty)
    }
    func testWriteLimitPreflightsBeforeEitherFileChanges() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("value.json")
        try FileCodec.write("oldest", to: url, maxBytes: 32)
        try FileCodec.write("current", to: url, maxBytes: 32)
        let primary = try Data(contentsOf: url), previous = try Data(contentsOf: url.appendingPathExtension("previous"))
        do { try FileCodec.write(String(repeating: "x", count: 33), to: url, maxBytes: 32); XCTFail("Over limit") }
        catch let error as LoomError { guard case .storage = error else { return XCTFail("Wrong error: \(error)") } }
        XCTAssertEqual(try Data(contentsOf: url), primary)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("previous")), previous)
        XCTAssertEqual(try FileCodec.read(String.self, from: url, maxBytes: 32), "current")
    }
    func testBoundedReadRejectsOversizedFileWithoutDecoding() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 120, count: 33).write(to: url)
        do { _ = try FileCodec.readData(from: url, maxBytes: 32); XCTFail("Over limit") }
        catch let error as LoomError { guard case .invalid = error else { return XCTFail("Wrong error: \(error)") } }
    }
    func testMalformedDateIsRejectedRatherThanDefaulted() {
        for invalid in ["{}", "{\"referenceSeconds\":\"not a number\"}", "\"not a date\""] {
            XCTAssertThrowsError(try FileCodec.decode(Date.self, Data(invalid.utf8)))
        }
    }
}
