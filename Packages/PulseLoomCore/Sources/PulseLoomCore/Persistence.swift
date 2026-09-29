import Foundation

public enum FileCodec {
    public static let defaultMaxBytes = 5 * 1024 * 1024
    /// A local library can contain many individually valid 256 KiB patterns.
    /// Apply the SAME bound at every library write/read/import/CloudKit staging boundary.
    public static let libraryMaxBytes = 64 * 1024 * 1024
    private struct ExactDate: Codable { let referenceSeconds: Double }
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let seconds = date.timeIntervalSinceReferenceDate
            guard seconds.isFinite else { throw LoomError.invalid("Non-finite date.") }
            try ExactDate(referenceSeconds: seconds).encode(to: encoder)
        }
        return try encoder.encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, _ data: Data, maxBytes: Int = defaultMaxBytes)
        throws -> T
    {
        guard maxBytes > 0, data.count <= maxBytes else { throw LoomError.invalid("File exceeds the size limit.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            // New files round-trip Date's actual binary64 reference epoch value.
            // Legacy ISO8601 files remain readable; their already-lost fractions cannot be recovered.
            if let exact = try? ExactDate(from: decoder) {
                guard exact.referenceSeconds.isFinite else { throw LoomError.invalid("Non-finite date.") }
                return Date(timeIntervalSinceReferenceDate: exact.referenceSeconds)
            }
            let single = try decoder.singleValueContainer()
            let text = try single.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw LoomError.invalid("Invalid date.") }
            return date
        }
        return try decoder.decode(type, from: data)
    }
    public static func write<T: Encodable>(
        _ value: T, to url: URL, maxBytes: Int = defaultMaxBytes, preservePrevious: Bool = true
    ) throws {
        // Preflight before touching either the current file OR its recovery copy.
        let data = try encode(value)
        guard maxBytes > 0, data.count <= maxBytes else { throw LoomError.storage("The library size limit would be exceeded. Nothing was replaced.") }
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if preservePrevious, fm.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("previous")
            let previous = try readData(from: url, maxBytes: maxBytes)
            #if os(iOS) || os(watchOS)
                try previous.write(to: backup, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
                try previous.write(to: backup, options: .atomic)
            #endif
        }
        #if os(iOS) || os(watchOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
            try data.write(to: url, options: .atomic)
        #endif
    }
    public static func readData(from url: URL, maxBytes: Int = defaultMaxBytes) throws -> Data {
        guard maxBytes > 0, maxBytes < Int.max else { throw LoomError.invalid("Invalid file limit.") }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maxBytes else { throw LoomError.invalid("File too large or empty.") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // Bounded read also checks a file that grows after resourceValues was read.
        var data = Data()
        data.reserveCapacity(size)
        while data.count <= maxBytes {
            let chunk = try handle.read(upToCount: min(64 * 1024, maxBytes + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard !data.isEmpty, data.count <= maxBytes else { throw LoomError.invalid("File too large or empty.") }
        return data
    }
    public static func read<T: Decodable>(
        _ type: T.Type, from url: URL, maxBytes: Int = defaultMaxBytes
    ) throws -> T {
        try decode(type, readData(from: url, maxBytes: maxBytes), maxBytes: maxBytes)
    }
    /// Logical removal of app-owned files, not a promise of physical flash/OS-backup erasure.
    public static func erase(_ url: URL) throws {
        let fm = FileManager.default
        for item in [url, url.appendingPathExtension("previous")] {
            if fm.fileExists(atPath: item.path) { try fm.removeItem(at: item) }
        }
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
        p = ContentPolicy.imported(p)
        p.id = UUID().uuidString
        p.builtin = false
        p.premium = false
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
                copy.id = try conflictID("pattern", p)
                copy.name = String((p.name + " (copy)").prefix(30))
                remap[p.id] = copy.id
                // A replay must neither resurrect a tombstoned copy nor overwrite its later edit.
                if (merged.tombstones[copy.id] ?? .distantPast) < copy.updatedAt {
                    if let previous = items[copy.id] {
                        if samePatternContent(previous, copy), previous.updatedAt < copy.updatedAt { items[copy.id] = copy }
                    } else { items[copy.id] = copy }
                }
            } else {
                if let existing = items[p.id], existing.updatedAt > p.updatedAt { continue }
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
                r.id = try conflictID("routine", r)
                r.name = String((r.name + " (copy)").prefix(30))
                if let previous = routines[r.id] {
                    if sameRoutineContent(previous, r), previous.updatedAt < r.updatedAt { routines[r.id] = r }
                    continue
                }
            } else if let old = routines[r.id], old.updatedAt > r.updatedAt { continue }
            if (merged.tombstones[r.id] ?? .distantPast) < r.updatedAt { routines[r.id] = r }
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
    private static func conflictID(_ kind: String, _ pattern: HapticPattern) throws -> String {
        var canonical = pattern
        canonical.updatedAt = Date(timeIntervalSince1970: 0)
        return "conflict-" + kind + "-" + StableContentDigest.hex(try FileCodec.encode(canonical))
    }
    private static func conflictID(_ kind: String, _ routine: Routine) throws -> String {
        var canonical = routine
        canonical.updatedAt = Date(timeIntervalSince1970: 0)
        return "conflict-" + kind + "-" + StableContentDigest.hex(try FileCodec.encode(canonical))
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

/// SHA-256 for reproducible content identifiers on Linux and Apple platforms.
/// Not a content-authentication mechanism; export provenance still uses ContentPolicy.
enum StableContentDigest {
    static func hex(_ input: Data) -> String {
        let k: [UInt32] = [
            0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
            0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
            0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
            0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
            0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
            0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
            0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
            0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2]
        var bytes = Array(input), h: [UInt32] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]
        let bits = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: bits >> shift)) }
        func rotate(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        for offset in stride(from: 0, to: bytes.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let j = offset + 4 * i
                w[i] = UInt32(bytes[j]) << 24 | UInt32(bytes[j+1]) << 16 | UInt32(bytes[j+2]) << 8 | UInt32(bytes[j+3])
            }
            for i in 16..<64 {
                let a = w[i-15], b = w[i-2]
                w[i] = w[i-16] &+ (rotate(a,7) ^ rotate(a,18) ^ (a >> 3)) &+ w[i-7] &+ (rotate(b,17) ^ rotate(b,19) ^ (b >> 10))
            }
            var a=h[0], b=h[1], c=h[2], d=h[3], e=h[4], f=h[5], g=h[6], z=h[7]
            for i in 0..<64 {
                let t1 = z &+ (rotate(e,6) ^ rotate(e,11) ^ rotate(e,25)) &+ ((e & f) ^ (~e & g)) &+ k[i] &+ w[i]
                let t2 = (rotate(a,2) ^ rotate(a,13) ^ rotate(a,22)) &+ ((a & b) ^ (a & c) ^ (b & c))
                z=g; g=f; f=e; e=d &+ t1; d=c; c=b; b=a; a=t1 &+ t2
            }
            for (i,v) in [a,b,c,d,e,f,g,z].enumerated() { h[i] = h[i] &+ v }
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }
}
