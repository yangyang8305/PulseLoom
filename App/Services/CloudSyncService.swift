import CloudKit
import Combine
import CryptoKit
import Foundation
import PulseLoomCore

@MainActor final class CloudSyncService: ObservableObject {
    enum State { case off, ready, syncing, conflict, failed }
    @Published private(set) var state: State = .off
    @Published var error: String?
    @Published private(set) var remoteSnapshot: LibrarySnapshot?
    @Published private(set) var lastSync: Date?
    private var database: CKDatabase?
    private var record: CKRecord?
    private var baseline: Data?
    private var generation = UUID()
    private let stagingRoot: URL
    init(stagingRoot: URL? = nil) {
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
        database = c.privateCloudDatabase
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
            do { remoteRecord = try await database.record(for: recordID) } catch let e as CKError
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
            try requireCurrent(expected)
            state = .failed
            self.error = error.localizedDescription
            throw error
        }
    }
    func resolve(local: LibrarySnapshot, choice: String) async throws -> LibrarySnapshot {
        let expected = generation
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
    private func upload(_ value: LibrarySnapshot, generation expected: UUID) async throws {
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
        try data.write(to: u, options: [.atomic, .completeFileProtection])
        defer { try? FileManager.default.removeItem(at: u) }
        let r = record ?? CKRecord(recordType: "PulseLoomLibrary", recordID: recordID)
        r["payload"] = CKAsset(fileURL: u)
        do {
            let results = try await database.modifyRecords(
                saving: [r], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
            try requireCurrent(expected)
            guard let result = results.saveResults[recordID] else {
                throw LoomError.storage("CloudKit returned no save result.")
            }
            record = try result.get()
            baseline = data
            state = .ready
            lastSync = Date()
            remoteSnapshot = nil
        } catch let e as CKError where e.code == .serverRecordChanged {
            try requireCurrent(expected)
            state = .conflict
            throw LoomError.storage("Cloud content changed again. Sync before resolving.")
        } catch {
            try requireCurrent(expected)
            state = .failed
            self.error = error.localizedDescription
            throw error
        }
    }
    func deleteCloud() async throws {
        let expected = generation
        guard let database else { return }
        _ = try await database.deleteRecord(withID: recordID)
        try requireCurrent(expected)
        disable()
    }
}
