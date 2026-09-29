import XCTest
import Foundation
@testable import PulseLoomCore

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

final class P2MergeControlTests: XCTestCase {
    func testStableDigestVectorsAndBlockPadding() {
        XCTAssertEqual(StableContentDigest.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(StableContentDigest.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(StableContentDigest.hex(Data(repeating: 97, count: 1000)), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }
    func testEditedConflictCopyIsNotOverwrittenByOldReplay() throws {
        var local = LibrarySnapshot(); var remote = LibrarySnapshot()
        let original = HapticPattern(id: "root", name: "local", updatedAt: Date(timeIntervalSince1970: 100))
        var other = original; other.name = "remote"; other.contentOrigin = .restricted; other.sourcePremium = true
        local.custom = [original]; remote.custom = [other]
        var merged = try CloudMerge.preservingBoth(local: local, remote: remote)
        let i = try XCTUnwrap(merged.custom.firstIndex { $0.id != "root" })
        merged.custom[i].name = "edited copy"; merged.custom[i].updatedAt = Date(timeIntervalSince1970: 200)
        let result = try CloudMerge.preservingBoth(local: merged, remote: remote)
        XCTAssertEqual(result.custom, merged.custom)
        XCTAssertTrue(result.custom.contains { $0.name == "edited copy" && $0.sourcePremium })
    }
    func testDeletedRoutineConflictDoesNotReappear() throws {
        var local = LibrarySnapshot(); var remote = LibrarySnapshot()
        let r = Routine(id: "r", name: "local", items: [RoutineItem(patternID: "p02")], updatedAt: Date(timeIntervalSince1970: 100))
        local.routines = [r]; remote.routines = [r]; remote.routines[0].name = "remote"
        var result = try CloudMerge.preservingBoth(local: local, remote: remote)
        let copy = try XCTUnwrap(result.routines.first { $0.id != "r" })
        result.routines.removeAll { $0.id == copy.id }; result.tombstones[copy.id] = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(try CloudMerge.preservingBoth(local: result, remote: remote).routines, result.routines)
    }
    func testTouchUndoAndRerecordPreservesRemainingOnset() throws {
        var r = TouchRecorder(); r.start(now: 0)
        _ = r.down(now: 0); r.up(now: 0.03)
        _ = r.down(now: 0.2); r.up(now: 0.22); r.undo()
        _ = r.down(now: 0.4); r.up(now: 0.42); r.finish(now: 0.42)
        let p = try r.pattern(name: "undo")
        XCTAssertEqual(p.segments.count, 2)
        XCTAssertEqual(p.segments[0].duration + p.segments[0].gap, 400, accuracy: 0.001)
    }
}

final class WidgetAppearanceTests: XCTestCase {
    func testAllThemesRespectExplicitLightAndDarkInsteadOfThemeName() {
        XCTAssertEqual(Catalog.themes.count, 6)
        for theme in Catalog.themes {
            for systemDark in [false, true] {
                let light = WidgetPalette(themeID: theme.id, appearance: "light", systemDark: systemDark)
                let dark = WidgetPalette(themeID: theme.id, appearance: "dark", systemDark: systemDark)
                XCTAssertFalse(light.isDark); XCTAssertTrue(dark.isDark)
                XCTAssertEqual(light.background, theme.light[0]); XCTAssertEqual(dark.background, theme.dark[0])
                XCTAssertEqual(light.foreground, theme.light[5]); XCTAssertEqual(dark.foreground, theme.dark[5])
            }
        }
    }
    func testAutoAndLegacyPreferencesFollowSystemAtRenderTime() {
        for raw: String? in [nil, "auto", "unknown-old-value"] {
            XCTAssertFalse(WidgetPalette(themeID: "night", appearance: raw, systemDark: false).isDark)
            XCTAssertTrue(WidgetPalette(themeID: "blush", appearance: raw, systemDark: true).isDark)
        }
    }
    func testUnknownThemeHasLegiblePairedFallback() {
        let value = WidgetPalette(themeID: "removed", appearance: "dark", systemDark: false)
        XCTAssertEqual(value.background, ThemeDefinition.fallback.dark[0])
        XCTAssertEqual(value.foreground, ThemeDefinition.fallback.dark[5])
        XCTAssertNotEqual(value.background, value.foreground)
    }
}
