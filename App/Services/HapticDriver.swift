import CoreHaptics
import Foundation
import PulseLoomCore
import UIKit

/// Single owner for all hardware output. Pattern events are scheduled by Core Haptics, not a UI timer.
@MainActor final class HapticDriver {
    var interrupted: ((String) -> Void)?
    var windowCompleted: (() -> Void)?
    private var engine: (any HapticEngineIO)?
    private var player: (any HapticPlayerIO)?
    private var generation: UInt64 = 0
    private var streaming = false
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
        guard supported else {
            throw LoomError.unavailable(NSLocalizedString("error.unsupported", comment: ""))
        }
        guard isForeground() else {
            throw LoomError.unavailable(NSLocalizedString("error.foreground", comment: ""))
        }
        guard thermalSafe() else {
            throw LoomError.unavailable(NSLocalizedString("error.thermal", comment: ""))
        }
        if engine == nil {
            let e = try makeEngine()
            e.stoppedHandler = { [weak self] reason in
                Task { @MainActor in
                    guard let self else { return }
                    self.player = nil
                    self.streaming = false
                    self.generation &+= 1
                    if reason != .idleTimeout && reason != .notifyWhenFinished {
                        self.interrupted?("Haptic engine stopped: \(reason.rawValue)")
                    }
                }
            }
            e.resetHandler = { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.player = nil
                    self.engine = nil
                    self.streaming = false
                    self.generation &+= 1
                    self.interrupted?(NSLocalizedString("error.engineReset", comment: ""))
                }
            }
            engine = e
        }
        try engine?.start()
    }
    func play(
        _ p: HapticPattern, phase: Double, length: Double, sessionElapsed: Double, sessionLimit: Double,
        gain: Double, speed: Double, sharp: Double
    ) throws {
        try Validation.pattern(p, requireName: false)
        try prepare()
        try stopPlayer()
        guard let engine else { throw LoomError.unavailable("Haptic engine could not be prepared.") }
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
                        .init(parameterID: .hapticSharpness, value: Float(sharp)),
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
        let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
        let newPlayer = try engine.makeAdvancedPlayer(with: pattern)
        generation &+= 1
        let expected = generation
        newPlayer.completionHandler = { [weak self] error in
            Task { @MainActor in
                guard let self, self.generation == expected else { return }
                if let error {
                    self.interrupted?(error.localizedDescription)
                } else {
                    self.windowCompleted?()
                }
            }
        }
        player = newPlayer
        streaming = false
        try newPlayer.start(atTime: CHHapticTimeImmediate)
    }
    private func params(_ s: Segment, gain: Double, sharp: Double) -> [CHHapticEventParameter] {
        [
            .init(parameterID: .hapticIntensity, value: Float(s.gain * gain)),
            .init(parameterID: .hapticSharpness, value: Float(min(1, max(0, s.sharp + sharp - 0.25)))),
        ]
    }
    func stream(intensity: Double, sharpness: Double) throws {
        if !streaming {
            try prepare()
            try stopPlayer()
            guard let engine else { throw LoomError.unavailable("Haptic engine unavailable.") }
            let e = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 1),
                    .init(parameterID: .hapticSharpness, value: 0),
                ], relativeTime: 0, duration: 1)
            let p = try engine.makeAdvancedPlayer(
                with: CHHapticPattern(
                    events: [e],
                    parameters: [.init(parameterID: .hapticIntensityControl, value: 0, relativeTime: 0)]))
            p.loopEnabled = true
            p.loopEnd = 1
            player = p
            try p.start(atTime: CHHapticTimeImmediate)
            streaming = true
        }
        try player?.sendParameters(
            [
                .init(
                    parameterID: .hapticIntensityControl, value: Float(min(1, max(0, intensity))),
                    relativeTime: 0),
                .init(
                    parameterID: .hapticSharpnessControl, value: Float(min(1, max(0, sharpness))),
                    relativeTime: 0),
            ], atTime: CHHapticTimeImmediate)
    }
    private func stopPlayer() throws {
        generation &+= 1
        let old = player
        player = nil
        streaming = false
        try old?.stop(atTime: CHHapticTimeImmediate)
    }
    func stop() { do { try stopPlayer() } catch { interrupted?(error.localizedDescription) } }
}
