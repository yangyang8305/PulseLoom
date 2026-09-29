import CloudKit
import Combine
import CryptoKit
import Foundation
import PulseLoomCore

/// Live CloudKit calls are isolated from deterministic failure/suspension tests.
@MainActor struct CloudBackend {
    var load: (CKRecord.ID) async throws -> CKRecord?
    var save: (CKRecord) async throws -> CKRecord
    var delete: (CKRecord.ID) async throws -> Void
    static func live(_ database: CKDatabase) -> Self {
        Self(load: { id in
            do { return try await database.record(for: id) }
            catch let e as CKError where e.code == .unknownItem { return nil }
        }, save: { record in
            let results = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
            guard let result = results.saveResults[record.recordID] else { throw LoomError.storage("CloudKit returned no save result.") }
            return try result.get()
        }, delete: { id in _ = try await database.deleteRecord(withID: id) })
    }
}

@MainActor final class CloudSyncService: ObservableObject {
    enum State { case off, ready, syncing, conflict, failed }
    @Published private(set) var state: State = .off
    @Published var error: String?
    @Published private(set) var remoteSnapshot: LibrarySnapshot?
    @Published private(set) var lastSync: Date?
    private var database: CloudBackend?
    private var record: CKRecord?
    private var baseline: Data?
    private var generation = UUID()
    private let stagingRoot: URL
    init(stagingRoot: URL? = nil, backend: CloudBackend? = nil) {
        database = backend
        if backend != nil { state = .ready }
        self.stagingRoot = stagingRoot ?? FileManager.default.temporaryDirectory.appendingPathComponent("PulseLoom-CloudStaging")
    }
    private func requireCurrent(_ expected: UUID) throws {
        guard generation == expected, !Task.isCancelled else { throw CancellationError() }
    }
    private let recordID = CKRecord.ID(recordName: "PulseLoom.Library.v1")
    func enable() async throws {
        let expected = UUID()
        generation = expected
        guard let id = Bundle.main.object(forInfoDictionaryKey: "CloudContainerID") as? String, !id.isEmpty
        else { throw LoomError.unavailable("CloudKit container is not configured.") }
        let c = CKContainer(identifier: id)
        guard try await c.accountStatus() == .available else {
            throw LoomError.unavailable(NSLocalizedString("sync.account", comment: ""))
        }
        try requireCurrent(expected)
        database = .live(c.privateCloudDatabase)
        state = .ready
    }
    func disable() {
        generation = UUID()
        database = nil
        record = nil
        remoteSnapshot = nil
        baseline = nil
        state = .off
    }
    func synchronize(_ local: LibrarySnapshot) async throws -> LibrarySnapshot? {
        let expected = generation
        guard let database else {
            throw LoomError.unavailable(NSLocalizedString("sync.account", comment: ""))
        }
        guard state != .syncing else { throw LoomError.unavailable("A sync is already in progress.") }
        state = .syncing
        error = nil
        do {
            let remoteRecord: CKRecord?
            do { remoteRecord = try await database.load(recordID) } catch let e as CKError
                where e.code == .unknownItem
            { remoteRecord = nil }
            try requireCurrent(expected)
            record = remoteRecord
            let localCloud = local.cloudPayload()
            let localData = try FileCodec.encode(localCloud)
            if let remoteRecord, let asset = remoteRecord["payload"] as? CKAsset, let u = asset.fileURL {
                let remote = try FileCodec.read(LibrarySnapshot.self, from: u, maxBytes: FileCodec.libraryMaxBytes)
                try Validation.snapshot(remote)
                remoteSnapshot = remote
                let remoteData = try FileCodec.encode(remote.cloudPayload())
                if localData != remoteData {
                    if let baseline, localData == baseline {
                        var result = remote
                        result.preferences = local.preferences
                        result.preferences.theme = remote.preferences.theme
                        result.preferences.appearance = remote.preferences.appearance
                        result.mixes = local.mixes
                        result.notes = local.notes
                        let ids = Set((Catalog.presets + result.custom).map(\.id))
                        if !ids.contains(result.preferences.lastPattern) {
                            result.preferences.lastPattern = "p02"
                        }
                        try Validation.snapshot(result)
                        self.baseline = remoteData
                        state = .ready
                        lastSync = Date()
                        return result
                    }
                    if baseline == nil && local.custom.isEmpty && local.routines.isEmpty
                        && local.tombstones.isEmpty && local.favorites.isEmpty
                    {
                        var result = remote
                        result.preferences = local.preferences
                        result.preferences.theme = remote.preferences.theme
                        result.preferences.appearance = remote.preferences.appearance
                        result.mixes = local.mixes
                        result.notes = local.notes
                        let ids = Set((Catalog.presets + result.custom).map(\.id))
                        if !ids.contains(result.preferences.lastPattern) {
                            result.preferences.lastPattern = "p02"
                        }
                        try Validation.snapshot(result)
                        self.baseline = remoteData
                        state = .ready
                        lastSync = Date()
                        return result
                    }
                    if baseline != remoteData {
                        state = .conflict
                        return nil
                    }
                }
            }
            try await upload(localCloud, generation: expected)
            return nil
        } catch {
            markFailure(error, expected: expected)
            throw error
        }
    }
    func resolve(local: LibrarySnapshot, choice: String) async throws -> LibrarySnapshot {
        let expected = generation
        guard ["local", "remote", "both"].contains(choice) else { throw LoomError.invalid("Unknown conflict choice.") }
        guard state != .syncing else { throw LoomError.unavailable("A sync is already in progress.") }
        guard let remoteSnapshot else { throw LoomError.invalid("No sync conflict is pending.") }
        var result: LibrarySnapshot
        if choice == "remote" {
            result = remoteSnapshot
            result.preferences = local.preferences
            result.preferences.theme = remoteSnapshot.preferences.theme
            result.preferences.appearance = remoteSnapshot.preferences.appearance
            result.mixes = local.mixes
            result.notes = local.notes
        } else if choice == "both" {
            result = try CloudMerge.preservingBoth(local: local, remote: remoteSnapshot)
        } else {
            result = local
        }
        let available = Set((Catalog.presets + result.custom).map(\.id))
        if !available.contains(result.preferences.lastPattern) { result.preferences.lastPattern = "p02" }
        try Validation.snapshot(result)
        state = .syncing
        try await upload(result.cloudPayload(), generation: expected)
        try requireCurrent(expected)
        return result
    }
    private func markFailure(_ failure: Error, expected: UUID) {
        // Cancellation belongs to the old operation; it may not overwrite a newly enabled session.
        guard generation == expected else { return }
        if state != .conflict { state = .failed }
        error = failure.localizedDescription
    }
    private func upload(_ value: LibrarySnapshot, generation expected: UUID) async throws {
        var temporary: URL?
        defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }
        do {
            try requireCurrent(expected)
            guard let database else { throw LoomError.unavailable("Cloud sync is off.") }
            let data = try FileCodec.encode(value)
            guard data.count <= FileCodec.libraryMaxBytes else { throw LoomError.storage("Cloud library exceeds the size limit.") }
            try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            var folder = stagingRoot
            var flags = URLResourceValues()
            flags.isExcludedFromBackup = true
            try folder.setResourceValues(flags)
            let u = stagingRoot.appendingPathComponent(UUID().uuidString + ".json")
            temporary = u
            try data.write(to: u, options: [.atomic, .completeFileProtection])
            // A failed save must not mutate the cached record to reference a deleted staging file.
            let r = (record?.copy() as? CKRecord) ?? CKRecord(recordType: "PulseLoomLibrary", recordID: recordID)
            r["payload"] = CKAsset(fileURL: u)
            let result = try await database.save(r)
            try requireCurrent(expected)
            record = result
            baseline = data
            state = .ready
            error = nil
            lastSync = Date()
            remoteSnapshot = nil
        } catch let e as CKError where e.code == .serverRecordChanged {
            if generation == expected {
                state = .conflict
                // The old resolution input is stale. Require synchronize() to fetch the new record.
                remoteSnapshot = nil
                error = "Cloud content changed again. Sync before resolving."
            }
            throw e
        } catch {
            markFailure(error, expected: expected)
            throw error
        }
    }
    func deleteCloud() async throws {
        let expected = generation
        guard let database else { throw LoomError.unavailable("Cloud sync is off. No cloud deletion was requested.") }
        guard state != .syncing else { throw LoomError.unavailable("A sync is already in progress.") }
        state = .syncing
        do {
            try requireCurrent(expected)
            try await database.delete(recordID)
            try requireCurrent(expected)
            disable()
        } catch {
            markFailure(error, expected: expected)
            throw error
        }
    }
}
