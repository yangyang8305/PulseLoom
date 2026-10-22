import Combine
import Foundation
import PulseLoomCore
import UIKit

@MainActor final class PlaybackCoordinator: ObservableObject {
    @Published private(set) var state: PlaybackState = .idle { didSet { didChange?() } }
    var didChange: (() -> Void)?
    var currentGain: Double { gain }
    @Published private(set) var remaining = 180.0
    @Published private(set) var level = 0.0
    @Published private(set) var title = ""
    @Published private(set) var activePattern: HapticPattern?
    @Published private(set) var kind = "pattern"
    @Published var lastError: String?
    /// Last parameters actually handed to the active output; shown on the troubleshooting page.
    @Published private(set) var lastDispatch: HapticDispatch?
    @Published private(set) var routineIndex = 0
    private(set) var outputID = UUID()
    private var clock = SessionClock(), phase = 0.0, lastTick = 0.0, windowEnd = 0.0
    private var gain = 0.8, speed = 1.0, sharp = 0.5
    private var timer: Timer?
    private var streamSource: String?
    private var pausedAt: Double?
    private var routine: Routine?
    private var resolver: ((String) -> HapticPattern?)?
    private var previousIdle = false
    private var savedIdle = false
    let driver: HapticDriver
    let outputs: HapticOutputRouter
    var willAcquire: ((String) -> Void)?
    var didFinish: ((String, String, Double, String) -> Void)?
    var didStopExternal: ((String) -> Void)?
    var keepAwake = true
    var isPlaying: Bool { state == .playing }
    var elapsed: Double { clock.played }
    var foreground = true
    private let now: () -> Double
    init(driver: HapticDriver? = nil, now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
        self.driver = driver ?? HapticDriver()
        self.outputs = HapticOutputRouter(phone: self.driver)
        self.outputs.interrupted = { [weak self] reason in self?.interrupt(reason) }
        self.outputs.windowCompleted = { [weak self] in self?.nextWindow() }
        self.outputs.dispatched = { [weak self] dispatch in
            guard let self else { return }
            // Streams report at up to 50 Hz; publish only when the readout would change.
            if let last = self.lastDispatch, last.kind == dispatch.kind, last.target == dispatch.target,
                abs(last.peakIntensity - dispatch.peakIntensity) < 0.005,
                abs(last.sharpness - dispatch.sharpness) < 0.005
            { return }
            self.lastDispatch = dispatch
        }
        self.outputs.routeInvalidated = { [weak self] reason in
            guard let self, [.playing, .paused, .preparing, .interrupted].contains(self.state) else { return }
            self.interrupt(reason)
        }
        timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    deinit { timer?.invalidate() }
    /// The session length comes from the timer, so a built-in piece that would end early repeats instead.
    static func timed(_ p: HapticPattern) -> HapticPattern {
        guard p.builtin, !p.loop else { return p }
        var q = p
        q.loop = true
        return q
    }
    func begin(
        _ p: HapticPattern, duration: Double, gain: Double, speed: Double = 1, sharp: Double = 0.5,
        kind: String = "pattern"
    ) throws {
        try Validation.pattern(p, requireName: false)
        let p = Self.timed(p)
        willAcquire?(kind)
        stop(reason: "replaced", notifyExternal: false)
        try outputs.prepare()
        let length = p.loop ? duration : min(duration, p.durationMS / 1000 / speed)
        activePattern = p
        title = p.displayName()
        self.kind = kind
        self.gain = gain
        self.speed = speed
        self.sharp = sharp
        pausedAt = nil
        phase = 0
        lastTick = now()
        try clock.start(now: lastTick, duration: min(7200, max(0.05, length)))
        do {
            try schedule()
            state = .playing
            remaining = clock.remaining
            holdScreen()
        } catch {
            clock.fail()
            state = .failed
            lastError = UserFacingError.message(error)
            throw error
        }
    }
    private func schedule() throws {
        guard let p = activePattern else { return }
        let length = min(10, clock.remaining)
        guard length > 0 else { return }
        try outputs.play(
            p, phase: phase, length: length, sessionElapsed: clock.played, sessionLimit: clock.limit,
            gain: gain, speed: speed, sharp: sharp)
        windowEnd = clock.played + length
    }
    private func nextWindow() {
        guard state == .playing else { return }
        tick()
        guard state == .playing else { return }
        do { try schedule() } catch { interrupt(UserFacingError.message(error, fallback: "error.interruption")) }
    }
    func tick() {
        if let pausedAt, [.paused, .interrupted].contains(state),
            now() - pausedAt >= 300
        {
            stop(reason: "pause_timeout")
            return
        }
        guard state == .playing else { return }
        let now = now()
        let delta = max(0, now - lastTick)
        lastTick = now
        phase += delta * speed
        clock.tick(now: now)
        remaining = clock.remaining
        if let p = activePattern {
            level =
                PatternMath.level(p, at: phase) * gain
                * PatternMath.envelope(
                    elapsed: clock.played, remaining: remaining, fadeIn: p.fadeIn / 1000,
                    fadeOut: p.fadeOut / 1000)
        }
        if clock.state == .completed {
            if let r = routine, routineIndex + 1 < r.items.count {
                advanceRoutine(to: routineIndex + 1)
                return
            }
            let finalTitle = title
            let finalKind = kind
            let played = clock.played
            outputs.stop()
            restoreScreen()
            state = outputs.shutdownPending ? .failed : .completed
            level = 0
            routine = nil
            didFinish?(finalTitle, finalKind, played, outputs.shutdownPending ? "shutdown_failed" : "completed")
            didStopExternal?("completed")
        }
    }
    func pause() {
        guard state == .playing else { return }
        clock.pause(now: now())
        outputs.stop()
        remaining = clock.remaining
        pausedAt = now()
        state = outputs.shutdownPending ? .failed : .paused
        level = 0
        restoreScreen()
    }
    func resume() throws {
        guard [.paused, .interrupted].contains(state) else { return }
        pausedAt = nil
        willAcquire?(kind)
        try outputs.prepare()
        clock.resume(now: now())
        lastTick = now()
        do {
            try schedule()
            state = .playing
            holdScreen()
        } catch {
            clock.fail()
            outputs.stop()
            restoreScreen()
            state = .failed
            didStopExternal?("resume_failed")
            throw error
        }
    }
    func stop(reason: String = "stopped", notifyExternal: Bool = true) {
        if [.playing, .paused, .interrupted].contains(state) {
            clock.pause(now: now())
            didFinish?(title, kind, clock.played, reason)
        }
        outputID = UUID()
        state = .idle
        pausedAt = nil
        streamSource = nil
        clock.stop()
        outputs.stop()
        if outputs.shutdownPending { state = .failed }
        level = 0
        routine = nil
        restoreScreen()
        if notifyExternal { didStopExternal?(reason) }
    }
    func interrupt(_ reason: String) {
        outputID = UUID()
        if [.playing, .paused].contains(state) {
            clock.pause(now: now(), interrupted: true)
            state = .interrupted
        }
        if state == .preparing { state = .idle }
        pausedAt = now()
        streamSource = nil
        outputs.stop()
        if outputs.shutdownPending { state = .failed }
        level = 0
        // `reason` is already user-facing: every interrupt(_:) caller localizes before calling.
        lastError = reason
        restoreScreen()
        didStopExternal?(reason)
    }
    func switchPattern(_ pattern: HapticPattern, gain: Double, speed: Double, sharp: Double) throws {
        try Validation.pattern(pattern, requireName: false)
        guard state == .playing, kind == "pattern" else { return }
        tick()
        guard state == .playing else { return }
        // Keep elapsed time and the two-hour ceiling across changes of preset.
        let pattern = Self.timed(pattern)
        activePattern = pattern
        title = pattern.displayName()
        phase = 0
        self.gain = gain
        self.speed = speed
        self.sharp = sharp
        if !pattern.loop { try clock.setRemaining(min(clock.remaining, pattern.durationMS / 1000 / speed)) }
        do { try schedule() } catch {
            interrupt(UserFacingError.message(error, fallback: "error.interruption"))
            throw error
        }
        didChange?()
    }
    func adjust(gain: Double, speed: Double, sharp: Double) throws {
        tick()
        self.gain = gain
        self.speed = speed
        self.sharp = sharp
        if state == .playing {
            do { try schedule() } catch { interrupt(UserFacingError.message(error, fallback: "error.interruption")); throw error }
        }
        didChange?()
    }
    func setRemaining(_ seconds: Double) throws {
        try clock.setRemaining(seconds)
        remaining = clock.remaining
        if state == .playing { try schedule() }
    }
    func stream(_ intensity: Double, sharpness: Double, source: String) throws {
        if streamSource != source {
            willAcquire?(source)
            stop(reason: "replaced", notifyExternal: false)
            kind = source
            try outputs.prepare()
            streamSource = source
            state = .preparing
        }
        try outputs.stream(intensity: intensity, sharpness: sharpness)
        level = intensity
        // Streaming sources have their own audio/touch monotonic clocks and hard duration bounds.
        state = .preparing
        holdScreen()
    }
    func stopStream() {
        outputID = UUID()
        streamSource = nil
        outputs.stop()
        level = 0
        if outputs.shutdownPending { state = .failed } else if state == .preparing { state = .idle }
        restoreScreen()
    }
    func playRoutine(_ r: Routine, resolver: @escaping (String) -> HapticPattern?, pro: Bool) throws {
        let ps = r.items.compactMap { resolver($0.patternID) }
        try Validation.routine(r, patterns: ps)
        guard ps.allSatisfy({ Entitlements.canPlay($0, pro: pro) }) else { throw LoomError.entitlement }
        stop(reason: "replaced", notifyExternal: !r.sound)
        self.resolver = resolver
        self.routine = r
        routineIndex = 0
        do { try startRoutineStep(r, 0) }
        catch { stop(reason: "routine_failed"); throw error }
    }
    private func startRoutineStep(_ r: Routine, _ i: Int) throws {
        guard let p0 = resolver?(r.items[i].patternID) else {
            throw LoomError.invalid("Missing routine pattern.")
        }
        var p = p0
        p.fadeIn = r.crossfade * 1000
        p.fadeOut = r.crossfade * 1000
        p.loop = true
        // begin() clears old routing; preserve the routine locally and reinstate after acquisition.
        let f = resolver
        try begin(p, duration: r.items[i].seconds, gain: r.items[i].gain, kind: "routine")
        routine = r
        resolver = f
        routineIndex = i
    }
    func advanceRoutine(to i: Int) {
        guard let r = routine, r.items.indices.contains(i) else { return }
        do { try startRoutineStep(r, i) } catch { interrupt(UserFacingError.message(error, fallback: "error.interruption")) }
    }
    private func holdScreen() {
        guard keepAwake else { return }
        if !savedIdle {
            previousIdle = UIApplication.shared.isIdleTimerDisabled
            savedIdle = true
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }
    private func restoreScreen() {
        if savedIdle {
            UIApplication.shared.isIdleTimerDisabled = previousIdle
            savedIdle = false
        }
    }
}
