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

/// P2 regression contracts: run unchanged on red and repaired implementations.
final class P2MergeAndRecordingTests: XCTestCase {
    private func conflict() -> (LibrarySnapshot, LibrarySnapshot) {
        var local = LibrarySnapshot(); var remote = LibrarySnapshot()
        let original = HapticPattern(id: "conflict", name: "local", updatedAt: Date(timeIntervalSince1970: 100))
        var other = original; other.name = "remote"
        local.custom = [original]; remote.custom = [other]
        local.routines = [Routine(id: "r", name: "local routine", items: [RoutineItem(patternID: "conflict")])]
        remote.routines = local.routines; remote.routines[0].name = "remote routine"
        remote.favorites = ["conflict"]
        return (local, remote)
    }
    func testAUD07RepeatingSameConflictIsIdempotent() throws {
        let (local, remote) = conflict()
        let first = try CloudMerge.preservingBoth(local: local, remote: remote)
        let second = try CloudMerge.preservingBoth(local: first, remote: remote)
        XCTAssertEqual(second.custom, first.custom, "Replaying an unchanged conflict must not manufacture another work")
        XCTAssertEqual(second.routines, first.routines, "Routine conflict identity must also be stable")
        XCTAssertEqual(second.favorites, first.favorites)
    }
    func testAUD07DeletedConflictCopyDoesNotResurrectOnReplay() throws {
        let (local, remote) = conflict()
        var merged = try CloudMerge.preservingBoth(local: local, remote: remote)
        let copy = try XCTUnwrap(merged.custom.first { $0.id != "conflict" })
        merged.custom.removeAll { $0.id == copy.id }
        merged.routines.removeAll { $0.items.contains { $0.patternID == copy.id } }
        merged.favorites.removeAll { $0 == copy.id }
        merged.tombstones[copy.id] = Date(timeIntervalSince1970: 200)
        let again = try CloudMerge.preservingBoth(local: merged, remote: remote)
        XCTAssertEqual(again.custom.count, 1, "Deleting the conflict copy must survive the same remote replay")
    }
    func testAUD07IdenticalOlderRemoteDoesNotRollBackTimestamp() throws {
        var local = LibrarySnapshot(); var remote = LibrarySnapshot()
        local.custom = [HapticPattern(id: "one", name: "one", updatedAt: Date(timeIntervalSince1970: 200))]
        remote = local; remote.custom[0].updatedAt = Date(timeIntervalSince1970: 100)
        let result = try CloudMerge.preservingBoth(local: local, remote: remote)
        XCTAssertEqual(result.custom[0].updatedAt, local.custom[0].updatedAt)
    }
    func testAUD13ShortTapPreservesNextOnsetTime() throws {
        var r = TouchRecorder(); r.start(now: 0)
        XCTAssertTrue(r.down(now: 0)); r.up(now: 0.03)
        XCTAssertTrue(r.down(now: 0.20)); r.up(now: 0.23); r.finish(now: 0.23)
        let p = try r.pattern(name: "two taps")
        XCTAssertEqual(p.segments[0].type, .transient)
        XCTAssertEqual(p.segments[0].duration + p.segments[0].gap, 200, accuracy: 0.001)
    }
}
