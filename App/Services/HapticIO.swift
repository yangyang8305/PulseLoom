import CoreHaptics
import Foundation
import Combine
import GameController
import PulseLoomCore

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
    convenience init() throws { self.init(engine: try CHHapticEngine()) }
    init(engine: CHHapticEngine) {
        self.engine = engine
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


// MARK: - System GameController haptics (no undocumented Bluetooth packets)

enum HapticOutputChoice: Hashable {
    case automatic, phone, controller(UUID)
}
struct ControllerOutputDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let family: String
    /// System capability, not a claim of verified physical rumble.
    let supportsHaptics: Bool
    let localities: [String]
}
enum HapticRoutePolicy {
    static func choose(
        _ choice: HapticOutputChoice, devices: [ControllerOutputDevice], phoneSupported: Bool
    ) throws -> UUID? {
        switch choice {
        case .automatic:
            if let first = devices.first(where: { $0.supportsHaptics }) { return first.id }
            guard phoneSupported else { throw LoomError.unavailable("No haptic output is available.") }
            return nil
        case .phone:
            guard phoneSupported else { throw LoomError.unavailable("iPhone Core Haptics unavailable.") }
            return nil
        case .controller(let id):
            guard let device = devices.first(where: { $0.id == id }) else {
                throw LoomError.unavailable("Selected controller is disconnected.")
            }
            guard device.supportsHaptics else {
                throw LoomError.unavailable("Selected controller has no public haptic output.")
            }
            return id
        }
    }
}

/// Tracks GCController objects only for their connection lifetime.
@MainActor final class ControllerHapticsManager: ObservableObject {
    @Published private(set) var devices: [ControllerOutputDevice] = []
    @Published private(set) var choice: HapticOutputChoice = .automatic
    var onRemoved: ((Set<UUID>) -> Void)?
    var onChoiceChanged: (() -> Void)?
    private var entries: [UUID: GCController] = [:]
    private var observers: [NSObjectProtocol] = []
    init() {
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in Task { @MainActor in self?.refresh() } })
        }
        refresh()
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    func refresh() {
        var next: [UUID: GCController] = [:]
        var found: [ControllerOutputDevice] = []
        for controller in GCController.controllers() {
            let id = entries.first(where: { $0.value === controller })?.key ?? UUID()
            next[id] = controller
            let localities = controller.haptics?.supportedLocalities ?? []
            let family: String
            if controller.extendedGamepad is GCDualSenseGamepad { family = "DualSense" }
            else if controller.extendedGamepad is GCXboxGamepad { family = "Xbox" }
            else { family = "Game Controller" }
            found.append(ControllerOutputDevice(
                id: id, name: controller.vendorName ?? family, family: family,
                supportsHaptics: localities.contains(.default),
                localities: localities.map { String(describing: $0) }.sorted()))
        }
        let removed = Set(entries.keys).subtracting(next.keys)
        entries = next
        devices = found
        if !removed.isEmpty { onRemoved?(removed) }
    }
    func select(_ value: HapticOutputChoice) {
        guard choice != value else { return }
        choice = value
        onChoiceChanged?()
    }
    func discover() {
        refresh()
        GCController.startWirelessControllerDiscovery(completionHandler: { [weak self] in
            Task { @MainActor in self?.refresh() }
        })
    }
    func suspendDiscovery() { GCController.stopWirelessControllerDiscovery() }
    func resolve(phoneSupported: Bool) throws -> (UUID?, GCController?) {
        let id = try HapticRoutePolicy.choose(choice, devices: devices, phoneSupported: phoneSupported)
        guard let id else { return (nil, nil) }
        guard let controller = entries[id] else {
            throw LoomError.unavailable("Controller disconnected before playback.")
        }
        return (id, controller)
    }
    func name(for id: UUID) -> String {
        devices.first(where: { $0.id == id })?.name ?? "Controller"
    }
}

/// Exactly one active output per session; a disconnect stops rather than silently rerouting.
@MainActor final class HapticOutputRouter {
    let controllers: ControllerHapticsManager
    private let phone: HapticDriver
    private var active: HapticDriver
    private var activeID: UUID?
    private var drivers: [UUID: HapticDriver] = [:]
    private var retiring: [UUID: HapticDriver] = [:]
    private(set) var activeName = "iPhone"
    var interrupted: ((String) -> Void)?
    var windowCompleted: (() -> Void)?
    var routeInvalidated: ((String) -> Void)?
    var supported: Bool { phone.supported || controllers.devices.contains(where: { $0.supportsHaptics }) }
    var shutdownPending: Bool {
        active.shutdownPending || retiring.values.contains(where: { $0.shutdownPending })
    }
    init(phone: HapticDriver, controllers: ControllerHapticsManager? = nil) {
        self.phone = phone
        self.active = phone
        self.controllers = controllers ?? ControllerHapticsManager()
        configure(phone, id: nil)
        self.controllers.onRemoved = { [weak self] ids in self?.disconnect(ids) }
        self.controllers.onChoiceChanged = { [weak self] in
            self?.routeInvalidated?("Output changed. Playback stopped; start again.")
        }
    }
    private func configure(_ driver: HapticDriver, id: UUID?) {
        driver.interrupted = { [weak self] reason in
            guard let self, self.activeID == id else { return }
            self.interrupted?(reason)
        }
        driver.windowCompleted = { [weak self] in
            guard let self, self.activeID == id else { return }
            self.windowCompleted?()
        }
    }
    private func disconnect(_ removed: Set<UUID>) {
        if let id = activeID, removed.contains(id) {
            routeInvalidated?("Controller disconnected. Playback stopped; select output and restart.")
        }
        for id in removed {
            guard let driver = drivers.removeValue(forKey: id) else { continue }
            retiring[id] = driver
            driver.terminationConfirmed = { [weak self] in self?.retiring.removeValue(forKey: id) }
            driver.retire()
        }
        if let id = activeID, removed.contains(id) {
            activeID = nil
            active = phone
            activeName = "iPhone"
        }
    }
    func prepare() throws {
        controllers.refresh()
        let (id, controller) = try controllers.resolve(phoneSupported: phone.supported)
        guard !shutdownPending else {
            throw LoomError.unavailable("Previous output shutdown unconfirmed. Wait before restarting.")
        }
        if id != activeID {
            guard active.stop() else {
                throw LoomError.unavailable("Previous output stop could not be confirmed.")
            }
            activeID = id
            if let id, let controller {
                if let cached = drivers[id] {
                    active = cached
                } else {
                    let driver = HapticDriver(
                        makeEngine: { [weak controller] in
                            guard let haptics = controller?.haptics,
                                haptics.supportedLocalities.contains(.default),
                                let engine = haptics.createEngine(withLocality: .default) else {
                                throw LoomError.unavailable("Could not create controller haptic engine.")
                            }
                            return AppleHapticEngine(engine: engine)
                        },
                        supportsHaptics: { [weak controller] in
                            controller?.haptics?.supportedLocalities.contains(.default) ?? false
                        })
                    configure(driver, id: id)
                    drivers[id] = driver
                    active = driver
                }
                activeName = controllers.name(for: id)
            } else {
                active = phone
                activeName = "iPhone"
            }
        }
        try active.prepare()
    }
    func play(
        _ p: HapticPattern, phase: Double, length: Double, sessionElapsed: Double,
        sessionLimit: Double, gain: Double, speed: Double, sharp: Double
    ) throws {
        try active.play(p, phase: phase, length: length, sessionElapsed: sessionElapsed,
                        sessionLimit: sessionLimit, gain: gain, speed: speed, sharp: sharp)
    }
    func stream(intensity: Double, sharpness: Double) throws {
        try active.stream(intensity: intensity, sharpness: sharpness)
    }
    @discardableResult func stop() -> Bool {
        let ok = active.stop()
        return ok && !shutdownPending
    }
}
