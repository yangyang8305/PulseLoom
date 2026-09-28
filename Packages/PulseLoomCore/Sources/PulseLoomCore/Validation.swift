import Foundation

public enum Validation {
    public static func finite(_ x: Double, _ range: ClosedRange<Double>) -> Bool {
        x.isFinite && range.contains(x)
    }
    public static func pattern(_ p: HapticPattern, requireName: Bool = true) throws {
        if requireName && !(1...30).contains(p.name.trimmingCharacters(in: .whitespacesAndNewlines).count) {
            throw LoomError.invalid("Name must contain 1–30 characters.")
        }
        guard !p.id.isEmpty, p.id.count <= 100 else { throw LoomError.invalid("Invalid pattern identifier.") }
        guard finite(p.durationMS, 100...30_000), finite(p.fadeIn, 0...5000), finite(p.fadeOut, 0...5000),
            finite(p.sharpness, 0...1)
        else { throw LoomError.invalid("Invalid duration, fade, or texture.") }
        if p.mode == .curve {
            guard (2...64).contains(p.nodes.count), Set(p.nodes.map(\.id)).count == p.nodes.count,
                p.nodes.first?.time == 0, p.nodes.last?.time == p.cycle
            else { throw LoomError.invalid("Curve requires 2–64 unique nodes including both endpoints.") }
            var last = -1.0
            for n in p.nodes {
                guard finite(n.time, 0...p.cycle), finite(n.value, 0...1), n.time > last else {
                    throw LoomError.invalid("Curve nodes must be ordered, distinct, and within range.")
                }
                last = n.time
            }
            guard p.nodes.contains(where: { $0.value > 0 }) else {
                throw LoomError.invalid("A pattern needs at least one nonzero segment.")
            }
        } else {
            let maxCount = (p.mode == .basic && !p.builtin) ? 16 : 128
            guard (1...maxCount).contains(p.segments.count),
                Set(p.segments.map(\.id)).count == p.segments.count
            else { throw LoomError.invalid("Invalid number of segments.") }
            for s in p.segments {
                let limit = (p.mode == .recorded || p.builtin) ? 10000.0 : 2000.0
                guard finite(s.duration, s.type == .transient ? 0...50 : 50...limit),
                    finite(s.gap, 0...30000),
                    finite(s.gain, 0...1), finite(s.sharp, 0...1)
                else { throw LoomError.invalid("Segment values are out of range.") }
            }
            guard p.segments.contains(where: { $0.gain > 0 }) else {
                throw LoomError.invalid("A pattern needs at least one nonzero segment.")
            }
        }
    }
    public static func routine(_ r: Routine, patterns: [HapticPattern]) throws {
        guard (1...30).contains(r.name.trimmingCharacters(in: .whitespacesAndNewlines).count),
            (1...12).contains(r.items.count), finite(r.duration, 15...600), finite(r.crossfade, 0...3)
        else { throw LoomError.invalid("A routine needs 1–12 steps and at most 10 minutes.") }
        let ids = Set(patterns.map(\.id))
        for item in r.items {
            guard ids.contains(item.patternID), finite(item.seconds, 15...300), finite(item.gain, 0...1)
            else { throw LoomError.invalid("Invalid or missing routine step.") }
        }
    }
    public static func snapshot(_ s: LibrarySnapshot) throws {
        guard s.schemaVersion == 1, s.custom.count <= 200, s.routines.count <= 200, s.mixes.count <= 200,
            s.notes.count <= 500, s.favorites.count <= 216, s.tombstones.count <= 2000,
            Set(s.custom.map(\.id)).count == s.custom.count,
            Set(s.routines.map(\.id)).count == s.routines.count,
            Set(s.mixes.map(\.id)).count == s.mixes.count,
            s.notes.allSatisfy({ $0.text.count <= 2000 }),
            s.mixes.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 50 && $0.trackName.count <= 1024 })
        else { throw LoomError.invalid("Unsupported or oversized library.") }
        let reserved = Set(Catalog.presets.map(\.id))
        for p in s.custom {
            guard !p.builtin, !reserved.contains(p.id) else {
                throw LoomError.invalid("Imported content cannot replace built-in content.")
            }
            try pattern(p)
        }
        let all = Catalog.presets + s.custom
        let ids = Set(all.map(\.id))
        guard s.favorites.allSatisfy(ids.contains), Set(s.favorites).count == s.favorites.count else {
            throw LoomError.invalid("Invalid favorite references.")
        }
        for r in s.routines { try routine(r, patterns: all) }
        let p = s.preferences
        guard finite(p.gain, 0...1), finite(p.speed, 0.5...2), finite(p.sharpness, 0...1),
            finite(p.timer, 30...600),
            ThemeCatalog.all.contains(where: { $0.id == p.theme }), p.name.count <= 24,
            ids.contains(p.lastPattern),
            reserved.contains(p.widgetPattern)
        else { throw LoomError.invalid("Invalid preferences.") }
        for m in s.mixes { try music(m.configuration, duration: 600) }
    }
    public static func music(_ c: MusicConfiguration, duration: Double) throws {
        guard finite(c.gain, 0...1), finite(c.sensitivity, 0...1), finite(c.volume, 0...1),
            finite(c.sharpness, 0...1),
            finite(c.overlayMix, 0...1), finite(c.offset, -0.5...0.5), finite(c.from, 0...duration),
            finite(c.to, 0...duration), c.to == 0 || c.to - c.from >= 0.1
        else { throw LoomError.invalid("Invalid music configuration or range.") }
    }
}
public enum PatternMath {
    public static func level(_ p: HapticPattern, at seconds: Double) -> Double {
        guard seconds.isFinite, seconds >= 0, p.durationMS > 0 else { return 0 }
        let raw = seconds * 1000
        if !p.loop && raw >= p.durationMS { return 0 }
        let t = p.loop ? raw.truncatingRemainder(dividingBy: p.durationMS) : raw
        if p.mode == .curve {
            guard let first = p.nodes.first else { return 0 }
            if t <= first.time { return first.value }
            for (a, b) in zip(p.nodes, p.nodes.dropFirst()) where t <= b.time {
                return a.value + (b.value - a.value) * (t - a.time) / max(0.001, b.time - a.time)
            }
            return p.nodes.last?.value ?? 0
        }
        var start = 0.0
        for s in p.segments {
            let d = s.type == .transient ? max(15, s.duration) : s.duration
            if t >= start && t < start + d { return s.gain }
            start += s.duration + s.gap
        }
        return 0
    }
    public static func envelope(elapsed: Double, remaining: Double, fadeIn: Double, fadeOut: Double) -> Double
    {
        let a = fadeIn > 0 ? min(1, max(0, elapsed / fadeIn)) : 1
        let b = fadeOut > 0 ? min(1, max(0, remaining / fadeOut)) : 1
        return a * b
    }
}
/// Value-semantic snapshots make a complete drag one undo operation, rather than one per frame.
public struct EditHistory<Value: Equatable> {
    public private(set) var undoStack: [Value] = []
    public private(set) var redoStack: [Value] = []
    public init() {}
    public mutating func record(_ previous: Value) {
        if undoStack.last != previous { undoStack.append(previous) }
        if undoStack.count > 30 { undoStack.removeFirst() }
        redoStack = []
    }
    public mutating func undo(_ current: Value) -> Value? {
        guard let value = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return value
    }
    public mutating func redo(_ current: Value) -> Value? {
        guard let value = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return value
    }
}
