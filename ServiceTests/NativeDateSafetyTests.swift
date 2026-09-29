import XCTest
import Foundation
import PulseLoomCore

/// Same contract runs under Apple Foundation as well as Linux Foundation.
final class NativeDateSafetyTests: XCTestCase {
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

import CoreHaptics
import CloudKit
@testable import PulseLoom

@MainActor private final class P2Player: HapticPlayerIO {
    var completionHandler: ((Error?) -> Void)?
    var loopEnabled = false
    var loopEnd = 0.0
    func start(atTime: TimeInterval) throws {}
    func stop(atTime: TimeInterval) throws {}
    func sendParameters(_ parameters: [CHHapticDynamicParameter], atTime: TimeInterval) throws {}
}
@MainActor private final class P2Engine: HapticEngineIO {
    var stoppedHandler: ((CHHapticEngine.StoppedReason) -> Void)?
    var resetHandler: (() -> Void)?
    var isMutedForHaptics = false
    let player = P2Player()
    func start() throws {}
    func stop(completion: @escaping (Error?) -> Void) { completion(nil) }
    func makeAdvancedPlayer(with pattern: CHHapticPattern) throws -> any HapticPlayerIO { player }
}
@MainActor final class P2ProductRegressionTests: XCTestCase {
    private func root() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: u) }
        return u
    }
    private func app() throws -> AppModel {
        let engine = P2Engine()
        let driver = HapticDriver(makeEngine: { engine }, supportsHaptics: { true }, isForeground: { true }, thermalSafe: { true })
        return AppModel(library: LibraryStore(root: try root()), playback: PlaybackCoordinator(driver: driver))
    }
    func testAUD11UndoRestoresToolAsWellAsPattern() throws {
        let model = try app(); let editor = EditorModel(); editor.attach(model)
        editor.choose(.basic); let before = editor.draft
        editor.choose(.curve); editor.undo()
        XCTAssertEqual(editor.tool, .basic)
        XCTAssertEqual(editor.draft, before)
        editor.redo()
        XCTAssertEqual(editor.tool, .curve)
        XCTAssertEqual(editor.draft.mode, .curve)
    }
    func testAUD12ShortestCurveConvertsToValidBasicPattern() throws {
        let model = try app(); let editor = EditorModel(); editor.attach(model)
        let curve = HapticPattern(name: "short", mode: .curve, segments: [], nodes: [CurveNode(time: 0, value: 0.5), CurveNode(time: 100, value: 0.5)], cycle: 100)
        editor.edit(curve); editor.choose(.basic)
        XCTAssertNoThrow(try Validation.pattern(editor.draft))
        XCTAssertEqual(editor.draft.durationMS, 100, accuracy: 0.001)
    }
    func testAUD14UndoLastXYTouchRemovesTheGesture() throws {
        let model = try app(); let editor = EditorModel(); editor.attach(model)
        editor.choose(.xy); editor.start()
        editor.touchBegan(CGPoint(x: 0.2, y: 0.3)); editor.endTouch()
        editor.removeLastTouch(); editor.end()
        XCTAssertEqual(editor.draft.mode, .basic, "Undoing the only XY gesture must not commit that gesture into a recording")
        XCTAssertEqual(editor.draft.segments.count, 4)
    }
    func testAUD16RoutineRetainsRequestedSoundscape() throws {
        let model = try app()
        let r = Routine(name: "routine", items: [RoutineItem(patternID: "p02", seconds: 15)], sound: true)
        // Same ordering as RoutinesView: sound first, followed by the public routine API.
        try model.sound.play()
        try model.playback.playRoutine(r, resolver: { model.library.pattern($0) }, pro: false)
        XCTAssertTrue(model.sound.active, "Starting the routine must not immediately stop its requested soundscape")
        model.stopAll()
        XCTAssertFalse(model.sound.active)
    }
    func testAUD17PausePublishesStoppedStateToWatch() async throws {
        let model = try app(); try model.beginCurrent()
        XCTAssertEqual(Mirror(reflecting: model.watch).children.first { $0.label == "lastPlaying" }?.value as? Bool, true)
        model.playback.pause()
        // One main-actor delivery turn is allowed; a timeout does not count as success.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(Mirror(reflecting: model.watch).children.first { $0.label == "lastPlaying" }?.value as? Bool, false)
        model.stopAll()
    }
    func testAUD22UploadPreparationFailureLeavesRetryableState() async throws {
        let folder = try root(), staging = folder.appendingPathComponent("blocked")
        try Data([1]).write(to: staging)
        var local = LibrarySnapshot(), remote = LibrarySnapshot()
        local.custom = [HapticPattern(name: "local")]; remote.custom = [HapticPattern(name: "remote")]
        let payload = folder.appendingPathComponent("remote.json")
        try FileCodec.write(remote, to: payload, maxBytes: FileCodec.libraryMaxBytes)
        let record = CKRecord(recordType: "PulseLoomLibrary", recordID: CKRecord.ID(recordName: "PulseLoom.Library.v1"))
        record["payload"] = CKAsset(fileURL: payload)
        let backend = CloudBackend(load: { _ in record }, save: { $0 }, delete: { _ in })
        let service = CloudSyncService(stagingRoot: staging, backend: backend)
        _ = try await service.synchronize(local)
        XCTAssertEqual(service.state, .conflict)
        do { _ = try await service.resolve(local: local, choice: "local"); XCTFail("Expected file system failure") } catch {}
        XCTAssertEqual(service.state, .failed, "Preparation failures must leave syncing and allow retry")
        try FileManager.default.removeItem(at: staging)
        do {
            _ = try await service.resolve(local: local, choice: "local")
            XCTAssertEqual(service.state, .ready)
        } catch { XCTFail("Retry must be possible: \(error)") }
        service.disable()
    }
}
