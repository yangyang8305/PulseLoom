import Combine
import Foundation
import PulseLoomCore
import UIKit

@MainActor final class PlaybackCoordinator: ObservableObject {
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var remaining = 180.0
    @Published private(set) var level = 0.0
    @Published private(set) var title = ""
    @Published private(set) var activePattern: HapticPattern?
    @Published private(set) var kind = "pattern"
    @Published var lastError: String?
    @Published var guardEnabled = false
    @Published private(set) var routineIndex = 0
    private var clock = SessionClock(), phase = 0.0, lastTick = 0.0, windowEnd = 0.0
    private var gain = 0.55, speed = 1.0, sharp = 0.25
    private var timer: Timer?
    private var streamSource: String?
    private var pausedAt: Double?
    private var routine: Routine?
    private var resolver: ((String) -> HapticPattern?)?
    private var previousIdle = false
    private var savedIdle = false
    let driver: HapticDriver
    var willAcquire: ((String) -> Void)?
    var didFinish: ((String, String, Double, String) -> Void)?
    var didStopExternal: ((String) -> Void)?
    var keepAwake = true
    var isPlaying: Bool { state == .playing }
    var elapsed: Double { clock.played }
    var foreground = true
    init(driver: HapticDriver? = nil) {
        self.driver = driver ?? HapticDriver()
        self.driver.interrupted = { [weak self] reason in self?.interrupt(reason) }
        self.driver.windowCompleted = { [weak self] in self?.nextWindow() }
        timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    deinit { timer?.invalidate() }
    func begin(
        _ p: HapticPattern, duration: Double, gain: Double, speed: Double = 1, sharp: Double = 0.25,
        kind: String = "pattern"
    ) throws {
        guard foreground else {
            throw LoomError.unavailable(NSLocalizedString("error.foreground", comment: ""))
        }
        try Validation.pattern(p, requireName: false)
        willAcquire?(kind)
        stop(reason: "replaced", notifyExternal: false)
        try driver.prepare()
        let length = p.loop ? duration : min(duration, p.durationMS / 1000 / speed)
        activePattern = p
        title = p.displayName()
        self.kind = kind
        self.gain = gain
        self.speed = speed
        self.sharp = sharp
        pausedAt = nil
        phase = 0
        lastTick = ProcessInfo.processInfo.systemUptime
        try clock.start(now: lastTick, duration: min(600, max(0.05, length)))
        do {
            try schedule()
            state = .playing
            remaining = clock.remaining
            holdScreen()
        } catch {
            clock.fail()
            state = .failed
            lastError = error.localizedDescription
            throw error
        }
    }
    private func schedule() throws {
        guard let p = activePattern else { return }
        let length = min(10, clock.remaining)
        guard length > 0 else { return }
        try driver.play(
            p, phase: phase, length: length, sessionElapsed: clock.played, sessionLimit: clock.limit,
            gain: gain, speed: speed, sharp: sharp)
        windowEnd = clock.played + length
    }
    private func nextWindow() {
        guard state == .playing else { return }
        tick()
        guard state == .playing else { return }
        do { try schedule() } catch { interrupt(error.localizedDescription) }
    }
    private func tick() {
        if let pausedAt, [.paused, .interrupted].contains(state),
            ProcessInfo.processInfo.systemUptime - pausedAt >= 300
        {
            stop(reason: "pause_timeout")
            return
        }
        guard state == .playing else { return }
        let now = ProcessInfo.processInfo.systemUptime
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
            driver.stop()
            restoreScreen()
            state = driver.shutdownPending ? .failed : .completed
            level = 0
            routine = nil
            didFinish?(finalTitle, finalKind, played, driver.shutdownPending ? "shutdown_failed" : "completed")
            didStopExternal?("completed")
        }
    }
    func pause() {
        guard state == .playing else { return }
        clock.pause(now: ProcessInfo.processInfo.systemUptime)
        driver.stop()
        remaining = clock.remaining
        pausedAt = ProcessInfo.processInfo.systemUptime
        state = driver.shutdownPending ? .failed : .paused
        level = 0
        restoreScreen()
    }
    func resume() throws {
        guard [.paused, .interrupted].contains(state), foreground else { return }
        pausedAt = nil
        willAcquire?(kind)
        try driver.prepare()
        clock.resume(now: ProcessInfo.processInfo.systemUptime)
        lastTick = ProcessInfo.processInfo.systemUptime
        do {
            try schedule()
            state = .playing
            holdScreen()
        } catch {
            clock.fail()
            state = .failed
            throw error
        }
    }
    func stop(reason: String = "stopped", notifyExternal: Bool = true) {
        if [.playing, .paused, .interrupted].contains(state) {
            clock.pause(now: ProcessInfo.processInfo.systemUptime)
            didFinish?(title, kind, clock.played, reason)
        }
        state = .idle
        pausedAt = nil
        streamSource = nil
        clock.stop()
        driver.stop()
        if driver.shutdownPending { state = .failed }
        level = 0
        routine = nil
        guardEnabled = false
        restoreScreen()
        if notifyExternal { didStopExternal?(reason) }
    }
    func interrupt(_ reason: String) {
        if [.playing, .paused].contains(state) {
            clock.pause(now: ProcessInfo.processInfo.systemUptime, interrupted: true)
            state = .interrupted
        }
        if state == .preparing { state = .idle }
        pausedAt = ProcessInfo.processInfo.systemUptime
        streamSource = nil
        driver.stop()
        if driver.shutdownPending { state = .failed }
        level = 0
        lastError = reason
        restoreScreen()
        didStopExternal?(reason)
    }
    func switchPattern(_ pattern: HapticPattern, gain: Double, speed: Double, sharp: Double) throws {
        try Validation.pattern(pattern, requireName: false)
        guard state == .playing, kind == "pattern" else { return }
        tick()
        guard state == .playing else { return }
        // Keep elapsed time and the 600-second ceiling across changes of preset.
        activePattern = pattern
        title = pattern.displayName()
        phase = 0
        self.gain = gain
        self.speed = speed
        self.sharp = sharp
        if !pattern.loop { try clock.setRemaining(min(clock.remaining, pattern.durationMS / 1000 / speed)) }
        do { try schedule() } catch {
            interrupt(error.localizedDescription)
            throw error
        }
    }
    func adjust(gain: Double, speed: Double, sharp: Double) throws {
        guard !guardEnabled else { return }
        tick()
        self.gain = gain
        self.speed = speed
        self.sharp = sharp
        if state == .playing { try schedule() }
    }
    func setRemaining(_ seconds: Double) throws {
        try clock.setRemaining(seconds)
        remaining = clock.remaining
        if state == .playing { try schedule() }
    }
    func stream(_ intensity: Double, sharpness: Double, source: String) throws {
        guard foreground else {
            throw LoomError.unavailable(NSLocalizedString("error.foreground", comment: ""))
        }
        if streamSource != source {
            willAcquire?(source)
            stop(reason: "replaced", notifyExternal: false)
            kind = source
            try driver.prepare()
            streamSource = source
            state = .preparing
        }
        try driver.stream(intensity: intensity, sharpness: sharpness)
        level = intensity
        // Streaming sources have their own audio/touch monotonic clocks and hard duration bounds.
        state = .preparing
        holdScreen()
    }
    func stopStream() {
        streamSource = nil
        driver.stop()
        level = 0
        if driver.shutdownPending { state = .failed } else if state == .preparing { state = .idle }
        restoreScreen()
    }
    func playRoutine(_ r: Routine, resolver: @escaping (String) -> HapticPattern?, pro: Bool) throws {
        let ps = r.items.compactMap { resolver($0.patternID) }
        try Validation.routine(r, patterns: ps)
        guard ps.allSatisfy({ Entitlements.canPlay($0, pro: pro) }) else { throw LoomError.entitlement }
        stop()
        self.resolver = resolver
        self.routine = r
        routineIndex = 0
        try startRoutineStep(r, 0)
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
        do { try startRoutineStep(r, i) } catch { interrupt(error.localizedDescription) }
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
