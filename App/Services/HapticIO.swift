import CoreHaptics
import Foundation

/// Injectable OS boundary. Tests exercise HapticDriver itself; no CoreHaptics output is simulated as accepted hardware output.
@MainActor protocol HapticPlayerIO: AnyObject {
    var completionHandler: ((Error?) -> Void)? { get set }
    var loopEnabled: Bool { get set }
    var loopEnd: TimeInterval { get set }
    func start(atTime: TimeInterval) throws
    func stop(atTime: TimeInterval) throws
    func sendParameters(_ parameters: [CHHapticDynamicParameter], atTime: TimeInterval) throws
}

@MainActor protocol HapticEngineIO: AnyObject {
    var stoppedHandler: ((CHHapticEngine.StoppedReason) -> Void)? { get set }
    var resetHandler: (() -> Void)? { get set }
    var isMutedForHaptics: Bool { get set }
    func start() throws
    func stop(completion: @escaping (Error?) -> Void)
    func makeAdvancedPlayer(with pattern: CHHapticPattern) throws -> any HapticPlayerIO
}

@MainActor final class AppleHapticEngine: HapticEngineIO {
    private let engine: CHHapticEngine
    var stoppedHandler: ((CHHapticEngine.StoppedReason) -> Void)? {
        didSet { engine.stoppedHandler = stoppedHandler ?? { _ in } }
    }
    var resetHandler: (() -> Void)? { didSet { engine.resetHandler = resetHandler ?? {} } }
    var isMutedForHaptics: Bool {
        get { engine.isMutedForHaptics }
        set { engine.isMutedForHaptics = newValue }
    }
    init() throws {
        engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
    }
    func start() throws { try engine.start() }
    func stop(completion: @escaping (Error?) -> Void) { engine.stop(completionHandler: completion) }
    func makeAdvancedPlayer(with pattern: CHHapticPattern) throws -> any HapticPlayerIO {
        AppleHapticPlayer(try engine.makeAdvancedPlayer(with: pattern))
    }
}

@MainActor private final class AppleHapticPlayer: HapticPlayerIO {
    private let player: any CHHapticAdvancedPatternPlayer
    var completionHandler: ((Error?) -> Void)? { didSet { player.completionHandler = completionHandler ?? { _ in } } }
    var loopEnabled: Bool {
        get { player.loopEnabled }
        set { player.loopEnabled = newValue }
    }
    var loopEnd: TimeInterval {
        get { player.loopEnd }
        set { player.loopEnd = newValue }
    }
    init(_ player: any CHHapticAdvancedPatternPlayer) { self.player = player }
    func start(atTime: TimeInterval) throws { try player.start(atTime: atTime) }
    func stop(atTime: TimeInterval) throws { try player.stop(atTime: atTime) }
    func sendParameters(_ parameters: [CHHapticDynamicParameter], atTime: TimeInterval) throws {
        try player.sendParameters(parameters, atTime: atTime)
    }
}
