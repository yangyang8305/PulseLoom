import Foundation
import XCTest
import PulseLoomCore
@testable import PulseLoom

final class DataSafetyTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("PulseLoomAudit-" + UUID().uuidString) }
    func testAcceptedPersistedLibraryCanBeReopened() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        try await MainActor.run {
            let store = LibraryStore(root: folder)
            for i in 0..<30 {
                var pattern = HapticPattern(name: "item \(i)")
                pattern.description = String(repeating: "x", count: 190_000)
                let imported = try PatternImport.decode(FileCodec.encode(pattern))
                try store.save(imported, pro: true)
            }
            XCTAssertEqual(store.snapshot.custom.count, 30)
            let file = folder.appendingPathComponent("library.json")
            let size = try Data(contentsOf: file).count
            print("AUD-06 persisted bytes = \(size)")
            let reopened = LibraryStore(root: folder)
            XCTAssertNil(reopened.loadError, "AUD-06: accepted writes exceed the reader's 5MiB limit")
            XCTAssertEqual(reopened.snapshot.custom.count, 30)
        }
    }
    func testClearHistoryDeletesPreviousDiskContents() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        try await MainActor.run {
            let store = LibraryStore(root: folder)
            try store.preferences { $0.historyEnabled = true }
            store.record(title: "PRIVATE_HISTORY_SENTINEL", kind: "pattern", seconds: 1, reason: "stopped")
            try store.clearHistory()
            XCTAssertTrue(store.history.isEmpty)
            let previous = folder.appendingPathComponent("Private/history.json.previous")
            let text = (try? String(contentsOf: previous, encoding: .utf8)) ?? ""
            XCTAssertFalse(text.contains("PRIVATE_HISTORY_SENTINEL"), "AUD-04: clear-history retains the deleted entry in .previous")
        }
    }
    func testClearUserContentPurgesLibraryAndDraftCopies() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        try await MainActor.run {
            let store = LibraryStore(root: folder)
            let p = HapticPattern(name: "PRIVATE_DRAFT_SENTINEL")
            try store.save(p, pro: true)
            store.saveDraft(p); try store.flushDraft()
            var p2=p; p2.name="next"; store.saveDraft(p2); try store.flushDraft()
            try store.clearUserContent()
            XCTAssertTrue(store.snapshot.custom.isEmpty)
            let lib = (try? String(contentsOf: folder.appendingPathComponent("library.json.previous"), encoding: .utf8)) ?? ""
            let draft = (try? String(contentsOf: folder.appendingPathComponent("draft.json.previous"), encoding: .utf8)) ?? ""
            XCTAssertFalse(lib.contains("PRIVATE_DRAFT_SENTINEL"), "AUD-04: library.json.previous still contains erased user content")
            XCTAssertFalse(draft.contains("PRIVATE_DRAFT_SENTINEL"), "AUD-04: draft.json.previous is not deleted")
        }
    }
    func testClearContentInvalidatesOpenEditor() async throws {
        let folder=root(); defer { try? FileManager.default.removeItem(at: folder) }
        try await MainActor.run {
            let app=AppModel(library: LibraryStore(root: folder)); let editor=EditorModel(); editor.attach(app)
            editor.draft.name="ERASED_NAME"; editor.persist(); try app.library.flushDraft()
            try app.library.clearUserContent()
            XCTAssertNil(app.library.draft)
            // Exactly the existing CreateView onDisappear callback: editor.persist().
            editor.persist(); try app.library.flushDraft()
            XCTAssertNotEqual(app.library.draft?.name, "ERASED_NAME", "AUD-05: unchanged open EditorModel resurrects cleared draft")
        }
    }
}

import CoreHaptics

@MainActor private final class PolicyPlayer: HapticPlayerIO {
    var completionHandler: ((Error?) -> Void)?
    var loopEnabled = false
    var loopEnd = 0.0
    func start(atTime: TimeInterval) throws {}
    func stop(atTime: TimeInterval) throws {}
    func sendParameters(_ parameters: [CHHapticDynamicParameter], atTime: TimeInterval) throws {}
}
@MainActor private final class PolicyEngine: HapticEngineIO {
    var stoppedHandler: ((CHHapticEngine.StoppedReason) -> Void)?
    var resetHandler: (() -> Void)?
    var isMutedForHaptics = false
    var scheduled = 0
    func start() throws {}
    func stop(completion: @escaping (Error?) -> Void) { completion(nil) }
    func makeAdvancedPlayer(with pattern: CHHapticPattern) throws -> any HapticPlayerIO { scheduled += 1; return PolicyPlayer() }
}

@MainActor final class AccessPolicyTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("AccessPolicy-" + UUID().uuidString) }
    private func makeApp(root: URL, engine: PolicyEngine, pro: @escaping () -> Bool = { true }) -> AppModel {
        let driver = HapticDriver(makeEngine: { engine }, supportsHaptics: { true }, isForeground: { true }, thermalSafe: { true })
        return AppModel(library: LibraryStore(root: root), playback: PlaybackCoordinator(driver: driver), entitlementReader: pro)
    }
    private func assertExportBlocked(_ app: AppModel, root: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(app.share, "AUD-09: no share item may be published", file: file, line: line)
        XCTAssertNotNil(app.error, "Blocked export must explain the restriction", file: file, line: line)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Exports").path)) ?? []
        XCTAssertTrue(files.isEmpty, "No partial or restricted export may be written", file: file, line: line)
    }
    func testAUD10AppCommandBoundaryReadsLiveEntitlementNotConnectionSnapshot() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let engine = PolicyEngine(); var livePro = true
        let app = makeApp(root: root, engine: engine, pro: { livePro })
        app.remote.pro = true // Deliberately stale transport snapshot; never a real purchase.
        livePro = false
        app.remote.onCommand?(RemoteCommand(sequence: 1, action: "start", patternID: "p02"), 0.4)
        XCTAssertEqual(engine.scheduled, 0, "AUD-10: a live revoked entitlement must not acquire output")
        XCTAssertFalse(app.playback.isPlaying)
    }
    func testAUD15OldRemoteGainDoesNotRescheduleLocalSession() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let engine = PolicyEngine(); let app = makeApp(root: root, engine: engine)
        try app.beginCurrent()
        let before = engine.scheduled
        app.remote.onCommand?(RemoteCommand(sequence: 5, action: "gain", gain: 1), 1)
        XCTAssertEqual(engine.scheduled, before, "AUD-15: stale remote gain cannot change the local session")
        XCTAssertEqual(app.playback.kind, "pattern")
        XCTAssertTrue(app.playback.isPlaying, "Rejecting a foreign command must not stop local output")
        app.stopAll()
    }
    func testAUD09PaidPresetExportIsRejectedBeforeWritingOrSharing() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine())
        app.export(Catalog.presets.first { $0.premium }!, name: "paid")
        assertExportBlocked(app, root: root)
    }
    func testAUD09EditedPaidCopyStillCannotBeExported() {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine()); let editor = EditorModel(); editor.attach(app)
        editor.edit(Catalog.presets.first { $0.premium }!, copy: true)
        editor.change { $0.name = "renamed"; $0.segments[0].gain = 0.1 }
        app.export(editor.draft, name: "derived")
        assertExportBlocked(app, root: root)
    }
    func testAUD09RecordingOverPaidDraftRetainsItsSource() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine()); let editor = EditorModel(); editor.attach(app)
        editor.edit(Catalog.presets.first { $0.premium }!, copy: true)
        editor.choose(.tap); editor.start(); editor.touchBegan(CGPoint(x: 0.5, y: 0.5))
        try await Task.sleep(nanoseconds: 100_000_000)
        editor.endTouch(); editor.end()
        XCTAssertTrue(editor.draft.sourcePremium, "Recording replaces shape, not the source of an existing draft")
        app.export(editor.draft, name: "recorded-derived")
        assertExportBlocked(app, root: root)
        app.stopAll()
    }
    func testAUD09OriginalWorkExportsWithAllItsSegments() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine())
        let original = HapticPattern(name: "my original")
        app.export(original, name: "original")
        XCTAssertNil(app.error)
        let url = try XCTUnwrap(app.share?.url)
        let decoded = try FileCodec.read(HapticPattern.self, from: url)
        XCTAssertEqual(decoded, original)
    }
    func testAUD09ImportedJSONCannotSelfAttestOriginality() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine())
        let imported = try PatternImport.decode(FileCodec.encode(HapticPattern(name: "claims original")))
        app.export(imported, name: "untrusted")
        assertExportBlocked(app, root: root)
    }
    func testAUD09WholeBackupWithRestrictedWorkIsBlockedNotFiltered() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine())
        let paid = Catalog.presets.first { $0.premium }!.copyForEditing()
        try app.library.save(paid, pro: true)
        try app.library.save(HapticPattern(name: "original"), pro: true)
        let before = app.library.snapshot
        app.export(before, name: "backup")
        assertExportBlocked(app, root: root)
        XCTAssertEqual(app.library.snapshot, before, "Blocked backup must not remove any works")
    }
    func testAUD09RoutineContainingPaidPresetBlocksBackup() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine())
        let paid = Catalog.presets.first { $0.premium }!
        try app.library.commit { $0.routines = [Routine(name: "mix", items: [RoutineItem(patternID: paid.id)])] }
        app.export(app.library.snapshot, name: "routine-backup")
        assertExportBlocked(app, root: root)
    }
    func testAUD09ExternalRestoreCannotCreateTrustedOriginals() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine())
        var external = LibrarySnapshot(); external.custom = [HapticPattern(name: "external claim")]
        try app.replaceLibrary(external)
        app.export(app.library.snapshot, name: "restored")
        assertExportBlocked(app, root: root)
    }
    func testSameAccountCloudPayloadIsNotAnExternalShareOperation() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(root: root, engine: PolicyEngine())
        let before = app.library.snapshot
        var incoming = before.cloudPayload()
        incoming.custom = [Catalog.presets.first { $0.premium }!.copyForEditing()]
        try app.applySyncResult(incoming, before: before, generation: app.library.contentGeneration)
        XCTAssertEqual(app.library.snapshot.custom.first?.sourcePremium, true)
        XCTAssertNil(app.share)
        XCTAssertNil(app.error, "Tests the local cloud-application boundary, not a real CloudKit connection")
    }
}

@MainActor private final class AccessWire: RemoteSocketIO {
    var frames: [Data] = []
    private var waiting: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    private var cancelled = false
    func resume() {}
    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        if cancelled { throw CancellationError() }
        switch message {
        case .data(let data): frames.append(data)
        case .string(let text): frames.append(Data(text.utf8))
        @unknown default: throw LoomError.invalid("Unknown wire frame")
        }
    }
    func receive() async throws -> URLSessionWebSocketTask.Message {
        if cancelled { throw CancellationError() }
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }
    func cancel() { cancelled = true; waiting?.resume(throwing: CancellationError()); waiting = nil }
    var dataFrames: [Data] { frames.filter { (try? JSONSerialization.jsonObject(with: $0) as? [String: Any])?["type"] as? String == "data" } }
}

extension AccessPolicyTests {
    private func requireHandshake(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("The real client did not emit the expected handshake")
        throw LoomError.invalid("Handshake timeout")
    }
    private func connectedApp(root: URL, engine: PolicyEngine, pro: @escaping () -> Bool = { true }) async throws -> (AppModel, RemoteService, AccessWire, AccessWire) {
        let outgoing = AccessWire(), incoming = AccessWire()
        let url = URL(string: "https://relay.invalid")!
        let receiver = RemoteService(server: url, makeSocket: { _ in incoming })
        let sender = RemoteService(server: url, makeSocket: { _ in outgoing })
        sender.pro = true
        let driver = HapticDriver(makeEngine: { engine }, supportsHaptics: { true }, isForeground: { true }, thermalSafe: { true })
        let app = AppModel(library: LibraryStore(root: root), playback: PlaybackCoordinator(driver: driver), remote: receiver, entitlementReader: pro)
        let invite = RemoteService.Invitation(room: "policy-room", token: "test-only", key: Data(repeating: 7, count: 32).base64EncodedString(), server: url.absoluteString)
        try sender.connect(invite, role: .sender)
        try receiver.connect(invite, role: .receiver)
        for service in [sender, receiver] {
            try service.handle(Data("{\"type\":\"ready\"}".utf8))
            try service.handle(Data("{\"type\":\"peer_joined\"}".utf8))
        }
        try await requireHandshake { !outgoing.dataFrames.isEmpty && !incoming.dataFrames.isEmpty }
        try sender.handle(incoming.dataFrames.last!)
        try receiver.handle(outgoing.dataFrames.last!)
        receiver.authorize(true)
        XCTAssertTrue(receiver.consent.allowed)
        return (app, sender, outgoing, incoming)
    }
    func testEncryptedRemoteCommandsStopOnLiveRevocationAndCannotResumeOnOldGrant() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let engine = PolicyEngine(); var livePro = true
        let (app, sender, wire, _) = try await connectedApp(root: folder, engine: engine, pro: { livePro })
        defer { sender.disconnect(); app.remote.disconnect(); app.stopAll() }
        try await sender.send(action: "start", patternID: "p02", gain: 0.4)
        try app.remote.handle(wire.dataFrames.last!)
        XCTAssertTrue(app.playback.isPlaying)
        let count = engine.scheduled
        livePro = false // Mirror remains true to expose the previously stale-snapshot race.
        XCTAssertTrue(app.remote.pro)
        try await sender.send(action: "gain", gain: 1)
        try app.remote.handle(wire.dataFrames.last!)
        XCTAssertEqual(engine.scheduled, count)
        XCTAssertFalse(app.playback.isPlaying)
        XCTAssertFalse(app.remote.consent.allowed)
        livePro = true
        try await sender.send(action: "start", patternID: "p02", gain: 0.4)
        do { try app.remote.handle(wire.dataFrames.last!) } catch { /* old nonce is an expected rejection */ }
        XCTAssertEqual(engine.scheduled, count, "Regaining Pro must not silently restore a revoked grant")
        XCTAssertFalse(app.playback.isPlaying)
    }
    func testEntitlementCallbackStopsRemoteButLeavesNewLocalOwnerRunning() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let engine = PolicyEngine(); var livePro = true
        let (app, sender, wire, _) = try await connectedApp(root: folder, engine: engine, pro: { livePro })
        defer { sender.disconnect(); app.remote.disconnect(); app.stopAll() }
        try await sender.send(action: "start", patternID: "p02", gain: 0.4)
        try app.remote.handle(wire.dataFrames.last!)
        XCTAssertTrue(app.playback.isPlaying)
        livePro = false
        app.refreshEntitlement() // Same synchronous callback that PurchaseService invokes after a real change.
        XCTAssertFalse(app.playback.isPlaying)
        XCTAssertFalse(app.remote.consent.allowed)
        try app.beginCurrent()
        XCTAssertEqual(app.playback.kind, "pattern")
        app.refreshEntitlement()
        XCTAssertTrue(app.playback.isPlaying, "Revocation cannot stop a newly acquired free local session")
    }
    func testLocalAcquisitionRevokesRemoteAndEncryptedQueuedGainCannotChangeIt() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let engine = PolicyEngine()
        let (app, sender, wire, _) = try await connectedApp(root: folder, engine: engine)
        defer { sender.disconnect(); app.remote.disconnect(); app.stopAll() }
        try await sender.send(action: "start", patternID: "p02", gain: 0.4)
        try app.remote.handle(wire.dataFrames.last!)
        XCTAssertEqual(app.playback.kind, "remote")
        try await sender.send(action: "gain", gain: 0.9)
        let queued = wire.dataFrames.last!
        try app.beginCurrent()
        let scheduled = engine.scheduled
        XCTAssertFalse(app.remote.consent.allowed)
        do { try app.remote.handle(queued) } catch { /* rejected stale authorization */ }
        XCTAssertEqual(engine.scheduled, scheduled)
        XCTAssertTrue(app.playback.isPlaying)
        XCTAssertEqual(app.playback.kind, "pattern")
    }
    func testOwnerIdentityRejectsGainEvenWhenHigherLevelRevocationHookIsBypassed() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let engine = PolicyEngine()
        let (app, sender, wire, _) = try await connectedApp(root: folder, engine: engine)
        defer { sender.disconnect(); app.remote.disconnect(); app.stopAll() }
        try await sender.send(action: "start", patternID: "p02", gain: 0.4)
        try app.remote.handle(wire.dataFrames.last!)
        XCTAssertTrue(app.playback.isPlaying)
        app.playback.willAcquire = nil // Deliberately remove first defense; test the independent owner boundary.
        try app.beginCurrent()
        XCTAssertTrue(app.remote.consent.allowed)
        let count = engine.scheduled
        try await sender.send(action: "gain", gain: 0.9)
        try app.remote.handle(wire.dataFrames.last!)
        XCTAssertEqual(engine.scheduled, count)
        XCTAssertTrue(app.playback.isPlaying)
        XCTAssertEqual(app.playback.kind, "pattern")
        XCTAssertNotNil(app.error)
    }
    func testValidRemoteGainAndOrdinaryStopStillWork() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let engine = PolicyEngine()
        let (app, sender, wire, _) = try await connectedApp(root: folder, engine: engine)
        defer { sender.disconnect(); app.remote.disconnect(); app.stopAll() }
        try await sender.send(action: "start", patternID: "p02", gain: 0.4)
        try app.remote.handle(wire.dataFrames.last!)
        let count = engine.scheduled
        try await sender.send(action: "gain", gain: 0.7)
        try app.remote.handle(wire.dataFrames.last!)
        XCTAssertGreaterThan(engine.scheduled, count)
        try await sender.send(action: "stop")
        try app.remote.handle(wire.dataFrames.last!)
        XCTAssertFalse(app.playback.isPlaying)
        XCTAssertTrue(app.remote.consent.allowed)
        try await sender.send(action: "start", patternID: "p02", gain: 0.4)
        try app.remote.handle(wire.dataFrames.last!)
        XCTAssertTrue(app.playback.isPlaying)
    }
    func testSenderRejectsOutputAfterRevocationButCanStillStopPeer() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let (app, sender, wire, _) = try await connectedApp(root: folder, engine: PolicyEngine())
        defer { sender.disconnect(); app.remote.disconnect(); app.stopAll() }
        sender.pro = false
        let count = wire.dataFrames.count
        do { try await sender.send(action: "start", patternID: "p02", gain: 0.5); XCTFail("Revoked sender") }
        catch let error as LoomError { XCTAssertEqual(error, .entitlement) }
        XCTAssertEqual(wire.dataFrames.count, count)
        try await sender.send(action: "stop")
        try app.remote.handle(wire.dataFrames.last!)
        XCTAssertTrue(app.remote.consent.allowed)
        try await sender.send(action: "emergencyStop")
        try app.remote.handle(wire.dataFrames.last!)
        XCTAssertFalse(app.remote.consent.allowed)
    }
    func testFullOriginalBackupExportsAllWorksWithoutFiltering() throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let app = makeApp(root: folder, engine: PolicyEngine(), pro: { false })
        try app.library.save(HapticPattern(name: "one"), pro: false)
        try app.library.save(HapticPattern(name: "two"), pro: false)
        let snapshot = app.library.snapshot
        app.export(snapshot, name: "original-backup")
        let url = try XCTUnwrap(app.share?.url)
        XCTAssertEqual(try FileCodec.read(LibrarySnapshot.self, from: url), snapshot)
    }
    func testPaidRoutineTaintRemainsAfterRemovingMemberAndAfterReload() throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(root: folder)
        let paid = Catalog.presets.first { $0.premium }!
        try store.commit { $0.routines = [Routine(name: "composition", items: [RoutineItem(patternID: paid.id), RoutineItem(patternID: "p02")])] }
        try store.commit { $0.routines[0].items.removeFirst() }
        let reopened = LibraryStore(root: folder)
        XCTAssertEqual(reopened.snapshot.routines[0].contentOrigin, .restricted)
        XCTAssertThrowsError(try ContentPolicy.assertExportable(reopened.snapshot))
    }
    func testFreshWorkspaceResetsOriginButEditingToolsDoNot() throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let app = makeApp(root: folder, engine: PolicyEngine()); let editor = EditorModel(); editor.attach(app)
        editor.edit(Catalog.presets.first { $0.premium }!, copy: true)
        editor.choose(.curve); editor.choose(.basic); editor.undo(); editor.redo()
        XCTAssertThrowsError(try ContentPolicy.assertExportable(editor.draft))
        editor.new(); editor.change { $0.name = "a new work" }
        XCTAssertNoThrow(try ContentPolicy.assertExportable(editor.draft))
    }
    func testRecoveryExportCannotBypassRestrictedOrUndecodableContent() throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let app = makeApp(root: folder, engine: PolicyEngine())
        try app.library.save(Catalog.presets.first { $0.premium }!.copyForEditing(), pro: true)
        app.exportRecoveryLibrary()
        assertExportBlocked(app, root: folder)
        app.error = nil
        try Data("{broken".utf8).write(to: folder.appendingPathComponent("library.json"))
        app.exportRecoveryLibrary()
        assertExportBlocked(app, root: folder)
    }
}
