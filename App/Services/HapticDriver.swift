import CoreHaptics
import Foundation
import PulseLoomCore
import UIKit

/// Single owner for all hardware output. Pattern events are scheduled by Core Haptics, not a UI timer.
@MainActor final class HapticDriver {
    var interrupted: ((String) -> Void)?
    var terminationConfirmed: (() -> Void)?
    var windowCompleted: (() -> Void)?
    var dispatched: ((HapticDispatch) -> Void)?
    private var engine: (any HapticEngineIO)?
    private var player: (any HapticPlayerIO)?
    private var generation: UInt64 = 0
    private var streaming = false
    private enum Termination { case none, inFlight, failed }
    private var termination: Termination = .none
    private var engineEpoch = UUID()
    private var notifyingFailure = false
    var shutdownPending: Bool { termination != .none }
    private let makeEngine: @MainActor () throws -> any HapticEngineIO
    private let supportsHaptics: @MainActor () -> Bool
    private let isForeground: @MainActor () -> Bool
    private let thermalSafe: @MainActor () -> Bool
    init(
        makeEngine: (@MainActor () throws -> any HapticEngineIO)? = nil,
        supportsHaptics: (@MainActor () -> Bool)? = nil,
        isForeground: (@MainActor () -> Bool)? = nil,
        thermalSafe: (@MainActor () -> Bool)? = nil
    ) {
        self.makeEngine = makeEngine ?? { try AppleHapticEngine() }
        self.supportsHaptics = supportsHaptics ?? { CHHapticEngine.capabilitiesForHardware().supportsHaptics }
        self.isForeground = isForeground ?? { UIApplication.shared.applicationState == .active }
        self.thermalSafe = thermalSafe ?? {
            let state = ProcessInfo.processInfo.thermalState
            return state != .serious && state != .critical
        }
    }
    var supported: Bool { supportsHaptics() }
    func prepare() throws {
        guard !shutdownPending else {
            throw LoomError.failure(.outputStopping)
        }
        guard supported else {
            throw LoomError.unavailable(T("error.unsupported"))
        }
        guard thermalSafe() else {
            throw LoomError.unavailable(T("error.thermal"))
        }
        if engine == nil {
            let e = try makeEngine()
            let epoch = UUID()
            engineEpoch = epoch
            e.stoppedHandler = { [weak self] reason in
                Task { @MainActor in
                    guard let self, self.engineEpoch == epoch else { return }
                    // A stopped callback is also positive termination confirmation.
                    if self.shutdownPending {
                        self.releaseTerminatedEngine(epoch: epoch)
                        return
                    }
                    self.player = nil
                    self.streaming = false
                    self.generation &+= 1
                    if reason != .idleTimeout && reason != .notifyWhenFinished {
                        DiagLog.write("engine stopped reason=\(reason.rawValue)")
                        self.reportFailure(T("error.interruption"))
                    }
                }
            }
            e.resetHandler = { [weak self] in
                Task { @MainActor in
                    guard let self, self.engineEpoch == epoch else { return }
                    self.releaseTerminatedEngine(epoch: epoch)
                    self.reportFailure(T("error.engineReset"))
                }
            }
            engine = e
        }
        do { try engine?.start() } catch {
            quarantineOutput()
            throw error
        }
    }
    func play(
        _ p: HapticPattern, phase: Double, length: Double, sessionElapsed: Double, sessionLimit: Double,
        gain: Double, speed: Double, sharp: Double
    ) throws {
        try Validation.pattern(p, requireName: false)
        try prepare()
        try stopPlayer()
        guard let engine else { throw LoomError.failure(.outputStart) }
        let duration = min(10, max(0.01, length))
        let cycle = p.durationMS / 1000
        let speed = min(2, max(0.5, speed))
        let gain = min(1, max(0, gain))
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []
        if p.mode == .curve {
            events = [
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        .init(parameterID: .hapticIntensity, value: 1),
                        .init(parameterID: .hapticSharpness, value: Float(Self.texture(p.sharpness, sharp))),
                    ], relativeTime: 0, duration: duration)
            ]
        } else {
            // Reconstruct the current phase and enough complete cycles for this window.
            let base = phase.truncatingRemainder(dividingBy: cycle)
            var start = -base / speed
            repeat {
                var cursor = start
                for s in p.segments {
                    let d = s.duration / 1000 / speed
                    if s.type == .transient {
                        if cursor >= 0 && cursor < duration {
                            events.append(
                                CHHapticEvent(
                                    eventType: .hapticTransient, parameters: params(s, gain: 1, sharp: sharp),
                                    relativeTime: cursor))
                        }
                    } else {
                        let a = max(0, cursor)
                        let b = min(duration, cursor + d)
                        if b > a {
                            events.append(
                                CHHapticEvent(
                                    eventType: .hapticContinuous,
                                    parameters: params(s, gain: 1, sharp: sharp), relativeTime: a,
                                    duration: b - a))
                        }
                    }
                    cursor += (s.duration + s.gap) / 1000 / speed
                }
                start += cycle / speed
            } while start < duration && p.loop
            if events.isEmpty {
                events = [
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [.init(parameterID: .hapticIntensity, value: 0)], relativeTime: 0,
                        duration: duration)
                ]
            }
        }
        // Combine curve shape, overall intensity and fades in one channel. Never schedule competing intensity curves.
        let n = max(1, Int(ceil(duration / 0.02)))
        var points: [(Double, Float)] = []
        for i in 0...n {
            let t = min(duration, Double(i) * 0.02)
            let base = p.mode == .curve ? PatternMath.level(p, at: phase + t * speed) : 1
            let fade = PatternMath.envelope(
                elapsed: sessionElapsed + t, remaining: sessionLimit - sessionElapsed - t,
                fadeIn: p.fadeIn / 1000, fadeOut: p.fadeOut / 1000)
            points.append((t, Float(base * gain * fade)))
        }
        var i = 0
        while i < points.count - 1 {
            let end = min(i + 15, points.count - 1)
            let origin = points[i].0
            let cps = points[i...end].map {
                CHHapticParameterCurve.ControlPoint(relativeTime: $0.0 - origin, value: $0.1)
            }
            curves.append(
                CHHapticParameterCurve(
                    parameterID: .hapticIntensityControl, controlPoints: cps, relativeTime: origin))
            i = end
        }
        if engine.simplePatterns {
            // Bake the intensity channel (curve shape × gain × fades) into the events themselves.
            let level: (Double) -> Float = { t in
                let i = min(points.count - 1, max(0, Int((t / 0.02).rounded())))
                return points[i].1
            }
            let tone = engine.controllerTone ?? .motor
            let controllerIntensity: (Float) -> Float = { v in v <= 0 ? 0 : Float(pow(Double(min(1, v)), tone == .voiceCoil ? 0.55 : 0.7)) }
            let controllerSharpness: (Float) -> Float = { s in Self.controllerSharpness(s, tone: tone) }
            if p.mode == .curve {
                events = stride(from: 0.0, to: duration, by: 0.05).map { t in
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            .init(parameterID: .hapticIntensity, value: controllerIntensity(level(t))),
                            .init(parameterID: .hapticSharpness, value: controllerSharpness(Float(Self.texture(p.sharpness, sharp)))),
                        ], relativeTime: t, duration: min(0.05, duration - t))
                }
            } else {
                events = events.map { e in
                    let scaled = e.eventParameters.map { q in
                        switch q.parameterID {
                        case .hapticIntensity: return CHHapticEventParameter(parameterID: .hapticIntensity, value: controllerIntensity(q.value * level(e.relativeTime)))
                        case .hapticSharpness: return CHHapticEventParameter(parameterID: .hapticSharpness, value: controllerSharpness(q.value))
                        default: return q
                        }
                    }
                    return e.type == .hapticTransient
                        ? CHHapticEvent(eventType: .hapticTransient, parameters: scaled, relativeTime: e.relativeTime)
                        : CHHapticEvent(eventType: .hapticContinuous, parameters: scaled, relativeTime: e.relativeTime, duration: e.duration)
                }
            }
            curves = []
        }
        let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
        let newPlayer = try engine.makeAdvancedPlayer(with: pattern)
        generation &+= 1
        let expected = generation
        newPlayer.completionHandler = { [weak self] error in
            Task { @MainActor in
                guard let self, self.generation == expected else { return }
                if let error {
                    self.interrupted?(UserFacingError.message(error, fallback: "error.interruption"))
                } else {
                    self.windowCompleted?()
                }
            }
        }
        player = newPlayer
        streaming = false
        do {
            try newPlayer.start(atTime: CHHapticTimeImmediate)
            DiagLog.write("player started events=\(events.count) curves=\(curves.count) length=\(duration)")
        } catch {
            let e = error as NSError
            DiagLog.write("player start FAILED domain=\(e.domain) code=\(e.code) \(e.localizedDescription)")
            quarantineOutput()
            throw error
        }
        let peakEvent = events.map { Self.value(.hapticIntensity, in: $0) }.max() ?? 0
        let peakSharp = events.map { Self.value(.hapticSharpness, in: $0) }.max() ?? 0
        let peakControl = points.map { Double($0.1) }.max() ?? 0
        dispatched?(HapticDispatch(
            kind: "pattern", events: events.count, peakIntensity: peakEvent * peakControl,
            sharpness: peakSharp))
    }
    private static func value(_ id: CHHapticEvent.ParameterID, in event: CHHapticEvent) -> Double {
        Double(event.eventParameters.first { $0.parameterID == id }?.value ?? 0)
    }
    private func params(_ s: Segment, gain: Double, sharp: Double) -> [CHHapticEventParameter] {
        [
            .init(parameterID: .hapticIntensity, value: Float(s.gain * gain)),
            .init(parameterID: .hapticSharpness, value: Float(Self.texture(s.sharp, sharp))),
        ]
    }
    /// Texture slider semantics: 0.5 plays a segment's own sharpness; the ends shift it by ±0.5.
    static func texture(_ base: Double, _ offset: Double) -> Double {
        min(1, max(0, base + (offset - 0.5)))
    }
    /// Phone sharpness (0–1) → controller sharpness. Voice coils (DualSense) only feel strong at low
    /// frequency; eccentric motors (Xbox) only at high frequency, so the texture slider moves within
    /// each actuator's strong band instead of across the whole range.
    static func controllerSharpness(_ s: Float, tone: ControllerTone) -> Float {
        let v = min(1, max(0, s))
        switch tone {
        case .voiceCoil: return v * 0.3
        case .motor: return 0.75 + v * 0.25
        }
    }
    private static func controls(intensity: Double, sharpness: Double) -> [CHHapticDynamicParameter] {
        [
            .init(
                parameterID: .hapticIntensityControl, value: Float(min(1, max(0, intensity))),
                relativeTime: 0),
            .init(
                parameterID: .hapticSharpnessControl, value: Float(min(1, max(0, sharpness))),
                relativeTime: 0),
        ]
    }
    func stream(intensity: Double, sharpness: Double) throws {
        guard !shutdownPending else {
            throw LoomError.failure(.outputStopping)
        }
        // Preparing discovers the actuator; even the first render must use its calibration.
        if !streaming {
            try prepare()
            try stopPlayer()
        }
        let tone = engine?.controllerTone
        let controls = Self.controls(
            intensity: tone != nil ? pow(min(1, max(0, intensity)), tone == .voiceCoil ? 0.55 : 0.7) : intensity,
            sharpness: tone.map { Double(Self.controllerSharpness(Float(sharpness), tone: $0)) } ?? sharpness)
        if !streaming {
            guard let engine else { throw LoomError.failure(.outputStart) }
            let e = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 1),
                    .init(parameterID: .hapticSharpness, value: 0),
                ], relativeTime: 0, duration: 1)
            // No pattern-level parameter: a looped pattern replays its own parameter events every
            // cycle, which would pull the level back to that value each second.
            let p = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [e], parameters: []))
            p.loopEnabled = true
            p.loopEnd = 1
            player = p
            // Prime the level before the first render; the authoritative send follows start().
            try? p.sendParameters(controls, atTime: CHHapticTimeImmediate)
            do { try p.start(atTime: CHHapticTimeImmediate) } catch {
                quarantineOutput()
                throw error
            }
            streaming = true
        }
        do { try player?.sendParameters(controls, atTime: CHHapticTimeImmediate) } catch {
            quarantineOutput()
            throw error
        }
        dispatched?(HapticDispatch(
            kind: "stream", events: 1, peakIntensity: Double(controls[0].value),
            sharpness: Double(controls[1].value)))
    }
    private func stopPlayer() throws {
        guard !shutdownPending else {
            throw LoomError.failure(.outputStopping)
        }
        generation &+= 1
        // Retain both handles until stop succeeds; losing the handle is not a stop.
        do {
            try player?.stop(atTime: CHHapticTimeImmediate)
            player = nil
            streaming = false
        } catch {
            quarantineOutput()
            throw error
        }
    }
    private func quarantineOutput() {
        generation &+= 1
        streaming = false
        if termination == .none { termination = .failed }
        // Independent best-effort mitigations while awaiting engine shutdown.
        engine?.isMutedForHaptics = true
        player?.loopEnabled = false
        try? player?.sendParameters([
            .init(parameterID: .hapticIntensityControl, value: 0, relativeTime: 0)
        ], atTime: CHHapticTimeImmediate)
        requestEngineTermination()
    }
    private func requestEngineTermination() {
        guard termination == .failed, let engine else { return }
        termination = .inFlight
        let epoch = engineEpoch
        engine.stop { [weak self] error in
            Task { @MainActor in
                guard let self, self.engineEpoch == epoch, self.shutdownPending else { return }
                if let error {
                    self.termination = .failed
                    // Reporting may call coordinator.interrupt -> stop. That is not an explicit retry.
                    DiagLog.write("engine stop FAILED \(error.localizedDescription)")
                    self.reportFailure(T("error.outputStopping"))
                } else {
                    self.releaseTerminatedEngine(epoch: epoch)
                }
            }
        }
    }
    private func releaseTerminatedEngine(epoch: UUID) {
        guard engineEpoch == epoch else { return }
        engineEpoch = UUID()
        generation &+= 1
        engine?.stoppedHandler = nil
        engine?.resetHandler = nil
        player?.completionHandler = nil
        player = nil
        engine = nil
        streaming = false
        termination = .none
        terminationConfirmed?()
    }
    private func reportFailure(_ message: String) {
        guard !notifyingFailure else { return }
        notifyingFailure = true
        interrupted?(message)
        notifyingFailure = false
    }
    /// Force an unused/disconnected controller engine to stop, retaining it until confirmation.
    func retire() {
        if shutdownPending { requestEngineTermination(); return }
        do { try stopPlayer() } catch { reportFailure(UserFacingError.message(error, fallback: "error.outputStopping")); return }
        guard engine != nil else { terminationConfirmed?(); return }
        engine?.isMutedForHaptics = true
        termination = .failed
        requestEngineTermination()
    }
    @discardableResult func stop() -> Bool {
        if shutdownPending {
            if !notifyingFailure { requestEngineTermination() }
            return false
        }
        do { try stopPlayer() } catch { reportFailure(UserFacingError.message(error, fallback: "error.outputStopping")) }
        return !shutdownPending
    }
}
