import Foundation

public enum PlaybackState: String, Sendable {
    case idle, preparing, playing, paused, interrupted, completed, failed
}
public struct SessionClock: Sendable {
    public private(set) var state: PlaybackState = .idle
    public private(set) var played: Double = 0
    public private(set) var limit: Double = 180
    public private(set) var generation: UInt64 = 0
    private var anchor: Double?
    public init() {}
    public var remaining: Double { max(0, limit - played) }
    public mutating func start(now: Double, duration: Double) throws {
        guard now.isFinite, Validation.finite(duration, 0.05...600) else {
            throw LoomError.invalid("Invalid session timing.")
        }
        generation &+= 1
        played = 0
        limit = duration
        anchor = now
        state = .playing
    }
    public mutating func tick(now: Double) {
        guard state == .playing, let a = anchor, now.isFinite else { return }
        played += max(0, now - a)
        anchor = max(a, now)
        if played >= limit {
            played = limit
            anchor = nil
            state = .completed
        }
    }
    public mutating func pause(now: Double, interrupted: Bool = false) {
        tick(now: now)
        if state == .playing { state = interrupted ? .interrupted : .paused }
        anchor = nil
    }
    public mutating func resume(now: Double) {
        guard now.isFinite, [.paused, .interrupted].contains(state), remaining > 0 else { return }
        anchor = now
        state = .playing
        generation &+= 1
    }
    public mutating func setRemaining(_ seconds: Double) throws {
        guard Validation.finite(seconds, 0...600) else {
            throw LoomError.invalid("Timer must be within 10 minutes.")
        }
        limit = min(600, played + seconds)
    }
    public mutating func stop() {
        state = .idle
        anchor = nil
        generation &+= 1
    }
    public mutating func fail() {
        state = .failed
        anchor = nil
        generation &+= 1
    }
}
public struct TouchRecorder: Sendable {
    public private(set) var segments: [Segment] = []
    public private(set) var active = false
    public private(set) var isDown = false
    public private(set) var startTime = 0.0
    private var downTime = 0.0
    private var lastUp: Double?
    public init() {}
    public mutating func start(now: Double) {
        segments = []
        active = true
        isDown = false
        startTime = now
        lastUp = nil
    }
    @discardableResult public mutating func down(now: Double, gain: Double = 0.5, sharpness: Double = 0.25)
        -> Bool
    {
        guard active, !isDown, segments.count < 128, now - startTime < 30 else { return false }
        if let up = lastUp, !segments.isEmpty { segments[segments.count - 1].gap = max(0, (now - up) * 1000) }
        downTime = now
        isDown = true
        segments.append(
            Segment(duration: 0, gap: 0, gain: min(1, max(0, gain)), sharp: min(1, max(0, sharpness))))
        return true
    }
    public mutating func up(now: Double) {
        guard isDown, !segments.isEmpty else { return }
        let ms = max(0, min(10000, (min(now, startTime + 30) - downTime) * 1000))
        segments[segments.count - 1].duration = ms < 50 ? 0 : ms
        segments[segments.count - 1].type = ms < 50 ? .transient : .continuous
        lastUp = min(now, startTime + 30)
        isDown = false
    }
    public mutating func tick(now: Double) {
        if isDown && now - downTime >= 10 { up(now: downTime + 10) }
        if active && now - startTime >= 30 { finish(now: startTime + 30) }
    }
    public mutating func finish(now: Double) {
        up(now: now)
        active = false
    }
    public mutating func undo() {
        guard !isDown, !segments.isEmpty else { return }
        segments.removeLast()
        lastUp = nil
    }
    public func pattern(name: String) throws -> HapticPattern {
        var list = segments
        guard !list.isEmpty else { throw LoomError.invalid("Record at least one touch.") }
        let length = list.reduce(0) { $0 + $1.duration + $1.gap }
        list[list.count - 1].gap += min(150, max(0, 30000 - length))
        let p = HapticPattern(name: name, mode: .recorded, segments: list)
        try Validation.pattern(p, requireName: !name.isEmpty)
        return p
    }
}
public struct BreathTiming: Codable, Equatable, Sendable {
    public var inhale = 4.0
    public var hold = 0.0
    public var exhale = 6.0
    public var minutes = 3.0
    public init() {}
    public var cycle: Double { inhale + hold + exhale }
    public func phase(at seconds: Double) -> (String, Double) {
        let t = seconds.truncatingRemainder(dividingBy: max(1, cycle))
        if t < inhale { return ("breath.inhale", inhale - t) }
        if t < inhale + hold { return ("breath.hold", inhale + hold - t) }
        return ("breath.exhale", cycle - t)
    }
    public func pattern() throws -> HapticPattern {
        guard Validation.finite(inhale, 2...10), Validation.finite(hold, 0...8),
            Validation.finite(exhale, 2...12), Validation.finite(minutes, 1...10)
        else { throw LoomError.invalid("Invalid breathing rhythm.") }
        var ns = [CurveNode(time: 0, value: 0.1), CurveNode(time: inhale * 1000, value: 0.5)]
        if hold > 0 { ns.append(CurveNode(time: (inhale + hold) * 1000, value: 0.5)) }
        ns.append(CurveNode(time: cycle * 1000, value: 0.1))
        return HapticPattern(name: "Breathing", mode: .curve, segments: [], nodes: ns, cycle: cycle * 1000)
    }
}
