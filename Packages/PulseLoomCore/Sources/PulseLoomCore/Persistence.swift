import Foundation

public enum FileCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, _ data: Data, maxBytes: Int = 5 * 1024 * 1024)
        throws -> T
    {
        guard data.count <= maxBytes else { throw LoomError.invalid("File exceeds the size limit.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encode(value)
        if fm.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("previous")
            if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
            try fm.copyItem(at: url, to: backup)
        }
        try data.write(to: url, options: .atomic)
        #if os(iOS) || os(watchOS)
            try fm.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path)
        #endif
    }
    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try decode(type, Data(contentsOf: url))
    }
}
public enum PatternImport {
    /// Accept native files plus the approved prototype's schemaVersion=2 DTO; never trust privilege flags from JSON.
    public static func decode(_ data: Data) throws -> HapticPattern {
        guard data.count <= 256 * 1024 else { throw LoomError.invalid("Pattern file exceeds 256 KB.") }
        var p: HapticPattern
        if let native = try? FileCodec.decode(HapticPattern.self, data) {
            p = native
        } else {
            let d = try JSONDecoder().decode(PrototypePattern.self, from: data)
            guard d.schemaVersion == 2 else { throw LoomError.invalid("Unsupported pattern schema.") }
            p = HapticPattern(
                name: d.name, englishName: d.en ?? "", mode: d.mode,
                segments: d.segments?.map {
                    Segment(
                        duration: $0.duration, gap: $0.gap, gain: $0.gain, sharp: $0.sharp,
                        type: $0.type ?? .continuous)
                } ?? [],
                nodes: d.nodes?.map { CurveNode(time: $0.time, value: $0.value) } ?? [],
                cycle: d.cycle ?? 2000,
                sharpness: d.sharp ?? 0.25, loop: d.loop ?? true, fadeIn: d.fadeIn ?? 0,
                fadeOut: d.fadeOut ?? 0)
        }
        p.id = UUID().uuidString
        p.builtin = false
        p.premium = false
        p.sourcePremium = false
        p.category = "custom"
        p.updatedAt = Date()
        try Validation.pattern(p)
        return p
    }
    public static func decodeMany(_ data: Data) throws -> [HapticPattern] {
        guard data.count <= 5 * 1024 * 1024 else { throw LoomError.invalid("Library exceeds 5 MB.") }
        if let list = try? FileCodec.decode([HapticPattern].self, data) {
            guard list.count <= 200 else { throw LoomError.invalid("At most 200 patterns can be imported.") }
            return try list.map { try decode(FileCodec.encode($0)) }
        }
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list = object["patterns"] as? [[String: Any]]
        {
            guard list.count <= 200 else { throw LoomError.invalid("At most 200 patterns can be imported.") }
            return try list.map { try decode(JSONSerialization.data(withJSONObject: $0)) }
        }
        return [try decode(data)]
    }
    private struct PrototypePattern: Decodable {
        var schemaVersion: Int
        var name: String
        var en: String?
        var mode: PatternMode
        var segments: [Part]?
        var nodes: [Node]?
        var cycle: Double?
        var sharp: Double?
        var loop: Bool?
        var fadeIn: Double?
        var fadeOut: Double?
        struct Part: Decodable {
            var duration: Double
            var gap: Double
            var gain: Double
            var sharp: Double
            var type: EventKind?
        }
        struct Node: Decodable {
            var time: Double
            var value: Double
        }
    }
}
public enum CloudMerge {
    /// Union IDs, honor tombstones, and preserve both conflicting edits. Does not silently overwrite user-authored content.
    public static func preservingBoth(local: LibrarySnapshot, remote: LibrarySnapshot) throws
        -> LibrarySnapshot
    {
        try Validation.snapshot(local)
        try Validation.snapshot(remote)
        var merged = local
        for (k, v) in remote.tombstones {
            merged.tombstones[k] = max(v, merged.tombstones[k] ?? .distantPast)
        }
        var items = Dictionary(
            uniqueKeysWithValues: local.custom.filter {
                (merged.tombstones[$0.id] ?? .distantPast) < $0.updatedAt
            }.map { ($0.id, $0) })
        var remap: [String: String] = [:]
        for p in remote.custom {
            guard (merged.tombstones[p.id] ?? .distantPast) < p.updatedAt else { continue }
            if let existing = items[p.id], !samePatternContent(existing, p) {
                var copy = p
                copy.id = UUID().uuidString
                copy.name = String((p.name + " (copy)").prefix(30))
                remap[p.id] = copy.id
                items[copy.id] = copy
            } else {
                items[p.id] = p
            }
        }
        merged.custom = items.values.filter { (merged.tombstones[$0.id] ?? .distantPast) < $0.updatedAt }
            .sorted { $0.id < $1.id }
        let ids = Set((Catalog.presets + merged.custom).map(\.id))
        var seen = Set<String>()
        merged.favorites = (local.favorites + remote.favorites.map { remap[$0] ?? $0 }).filter {
            ids.contains($0) && seen.insert($0).inserted
        }
        var routines = Dictionary(
            uniqueKeysWithValues: local.routines.filter {
                (merged.tombstones[$0.id] ?? .distantPast) < $0.updatedAt
            }.map { ($0.id, $0) })
        for var r in remote.routines {
            guard (merged.tombstones[r.id] ?? .distantPast) < r.updatedAt else { continue }
            r.items = r.items.map {
                var x = $0
                x.patternID = remap[x.patternID] ?? x.patternID
                return x
            }
            if let old = routines[r.id], !sameRoutineContent(old, r) {
                r.id = UUID().uuidString
                r.name = String((r.name + " (copy)").prefix(30))
            }
            routines[r.id] = r
        }
        merged.routines = routines.values.compactMap { r in
            var r = r
            r.items.removeAll { !ids.contains($0.patternID) }
            return r.items.isEmpty ? nil : r
        }.sorted { $0.id < $1.id }
        if !ids.contains(merged.preferences.lastPattern) { merged.preferences.lastPattern = "p02" }
        merged.updatedAt = Date()
        try Validation.snapshot(merged)
        return merged
    }
    private static func samePatternContent(_ a: HapticPattern, _ b: HapticPattern) -> Bool {
        var a = a
        var b = b
        a.updatedAt = Date(timeIntervalSince1970: 0)
        b.updatedAt = a.updatedAt
        return a == b
    }
    private static func sameRoutineContent(_ a: Routine, _ b: Routine) -> Bool {
        var a = a
        var b = b
        a.updatedAt = Date(timeIntervalSince1970: 0)
        b.updatedAt = a.updatedAt
        return a == b
    }

}
