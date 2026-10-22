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
    /// Non-nil for game controllers: they only accept plain patterns (baked-in intensity, no curves)
    /// and each actuator type needs its own frequency mapping.
    var controllerTone: ControllerTone? { get }
}
extension HapticEngineIO {
    var controllerTone: ControllerTone? { nil }
    var simplePatterns: Bool { controllerTone != nil }
}
/// Measured on the owner's hardware (2026-10-09): DualSense voice coils feel strongest at low
/// sharpness; Xbox eccentric motors (triggers + handles) feel strongest at high sharpness.
enum ControllerTone { case voiceCoil, motor }

/// What was last handed to Core Haptics. Short of feeling the motor, a readout of this is the
/// only honest evidence of whether full power was actually requested.
struct HapticDispatch: Equatable {
    var target = "iPhone"
    /// "pattern" for scheduled windows, "stream" for manual/music/recording control.
    var kind: String
    var events: Int
    /// Highest event intensity multiplied by the highest intensity-control value in the window.
    var peakIntensity: Double
    /// Highest event sharpness after the texture offset.
    var sharpness: Double
    var date = Date()
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
    /// Controller engines (DualSense, Xbox) are driven by the GameController haptics service; the
    /// phone-only options (haptics-only audio path, idle auto-shutdown) break their XPC session.
    private let tone: ControllerTone?
    private var controller: Bool { tone != nil }
    /// Game controllers (DualSense, Xbox) reject advanced players and parameter curves: the first
    /// advanced player request tears down the gamecontrollerd haptics XPC session (NSCocoaError 4097,
    /// then CoreHaptics -4810 for everything after). Apple Developer Forums thread 773615.
    var controllerTone: ControllerTone? { tone }
    init(engine: CHHapticEngine, tone: ControllerTone? = nil) {
        self.engine = engine
        self.tone = tone
        if tone == nil {
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
        }
    }
    func start() throws {
        DiagLog.write("engine start")
        do { try engine.start(); DiagLog.write("engine started") } catch {
            let e = error as NSError
            DiagLog.write("engine start FAILED domain=\(e.domain) code=\(e.code) \(e.localizedDescription) info=\(e.userInfo)")
            throw LoomError.diagnostic("\(e.localizedDescription) (\(e.domain) \(e.code))")
        }
    }
    func stop(completion: @escaping (Error?) -> Void) { engine.stop(completionHandler: completion) }
    func makeAdvancedPlayer(with pattern: CHHapticPattern) throws -> any HapticPlayerIO {
        if controller {
            // Never ask a controller engine for an advanced player: the request itself kills the session.
            do {
                let basic = try engine.makePlayer(with: pattern)
                DiagLog.write("controller basic player created duration=\(pattern.duration)")
                return BasicHapticPlayer(basic, duration: pattern.duration)
            } catch {
                let e = error as NSError
                DiagLog.write("controller basic player FAILED domain=\(e.domain) code=\(e.code) \(e.localizedDescription)")
                throw error
            }
        }
        return AppleHapticPlayer(try engine.makeAdvancedPlayer(with: pattern))
    }
}

@MainActor private final class BasicHapticPlayer: HapticPlayerIO {
    private let player: any CHHapticPatternPlayer
    private let duration: TimeInterval
    private var finish: DispatchWorkItem?
    var completionHandler: ((Error?) -> Void)?
    var loopEnabled = false
    var loopEnd: TimeInterval = 0
    init(_ player: any CHHapticPatternPlayer, duration: TimeInterval) { self.player = player; self.duration = duration }
    func start(atTime: TimeInterval) throws {
        try player.start(atTime: atTime)
        scheduleFinish()
    }
    /// Basic players cannot loop by themselves; restart at the end of each pass while looping.
    private func scheduleFinish() {
        finish?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.loopEnabled, (try? self.player.start(atTime: CHHapticTimeImmediate)) != nil {
                self.scheduleFinish()
            } else {
                self.completionHandler?(nil)
            }
        }
        finish = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, duration), execute: work)
    }
    func stop(atTime: TimeInterval) throws {
        finish?.cancel(); finish = nil
        try player.stop(atTime: atTime)
    }
    func sendParameters(_ parameters: [CHHapticDynamicParameter], atTime: TimeInterval) throws {
        try player.sendParameters(parameters, atTime: atTime)
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
            guard phoneSupported else { throw LoomError.failure(.outputUnavailable) }
            return nil
        case .phone:
            guard phoneSupported else { throw LoomError.failure(.outputUnavailable) }
            return nil
        case .controller(let id):
            guard let device = devices.first(where: { $0.id == id }) else {
                throw LoomError.failure(.controllerDisconnected)
            }
            guard device.supportsHaptics else {
                throw LoomError.failure(.controllerUnsupported)
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
    private let enumerate: @MainActor () -> [GCController]
    init(enumerate: (@MainActor () -> [GCController])? = nil) {
        self.enumerate = enumerate ?? { GCController.controllers() }
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
        for controller in enumerate() {
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
        DiagLog.write("controllers: " + found.map { "\($0.name) family=\($0.family) haptics=\($0.supportsHaptics) localities=\($0.localities)" }.joined(separator: " | "))
        let removed = Set(entries.keys).subtracting(next.keys)
        entries = next
        if devices != found { devices = found }
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
            throw LoomError.failure(.controllerDisconnected)
        }
        return (id, controller)
    }
    func name(for id: UUID) -> String {
        devices.first(where: { $0.id == id })?.name ?? "Controller"
    }
    /// The first connected controller with haptics, for the calibration probe.
    var firstHapticController: GCController? {
        devices.first(where: { $0.supportsHaptics }).flatMap { entries[$0.id] }
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
    private(set) var lastFallbackReason: String?
    var selectedName: String {
        switch controllers.choice {
        case .automatic:
            return controllers.devices.first(where: { $0.supportsHaptics })?.name ?? "iPhone"
        case .phone:
            return "iPhone"
        case .controller(let id):
            return controllers.devices.first(where: { $0.id == id })?.name
                ?? T("output.disconnected")
        }
    }
    var interrupted: ((String) -> Void)?
    var windowCompleted: (() -> Void)?
    var dispatched: ((HapticDispatch) -> Void)?
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
            self?.routeInvalidated?(T("error.interruption"))
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
        driver.dispatched = { [weak self] dispatch in
            guard let self, self.activeID == id else { return }
            var labeled = dispatch
            labeled.target = self.activeName
            self.dispatched?(labeled)
        }
    }
    private func disconnect(_ removed: Set<UUID>) {
        if let id = activeID, removed.contains(id) {
            routeInvalidated?(T("error.controllerDisconnected"))
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
        lastFallbackReason = nil
        controllers.refresh()
        let (id, controller) = try controllers.resolve(phoneSupported: phone.supported)
        guard !shutdownPending else {
            throw LoomError.failure(.outputStopping)
        }
        if id != activeID {
            guard active.stop() else {
                throw LoomError.failure(.outputStopping)
            }
            activeID = id
            if let id, let controller {
                if let cached = drivers[id] {
                    active = cached
                } else {
                    let driver = HapticDriver(
                        makeEngine: { [weak controller] in
                            let family = self.controllers.devices.first(where: { $0.id == id })?.family ?? ""
                            let tone: ControllerTone = family == "DualSense" ? .voiceCoil : .motor
                            // Drive every actuator the controller offers (Xbox: handles + both triggers).
                            let locality: GCHapticsLocality = controller?.haptics?.supportedLocalities.contains(.all) == true ? .all : .default
                            DiagLog.write("create controller engine: family=\(family) tone=\(tone) locality=\(locality.rawValue) localities=\(controller?.haptics?.supportedLocalities.map { "\($0.rawValue)" } ?? [])")
                            guard let haptics = controller?.haptics,
                                haptics.supportedLocalities.contains(locality),
                                let engine = haptics.createEngine(withLocality: locality) else {
                                DiagLog.write("create controller engine FAILED (nil)")
                                throw LoomError.failure(.outputStart)
                            }
                            return AppleHapticEngine(engine: engine, tone: tone)
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
        DiagLog.write("prepare: choice=\(controllers.choice) resolved=\(id.map { controllers.name(for: $0) } ?? "iPhone") phoneSupported=\(phone.supported)")
        do {
            try active.prepare()
        } catch {
            DiagLog.write("prepare FAILED: \(error.localizedDescription)")
            // Only an automatic choice may fall back. A failed engine shutdown
            // must remain quarantined, not silently start another output.
            guard id != nil, controllers.choice == .automatic, phone.supported,
                !active.shutdownPending, active.stop() else { throw error }
            activeID = nil
            active = phone
            activeName = "iPhone"
            lastFallbackReason = UserFacingError.message(error)
            try phone.prepare()
        }
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
        // A disconnected controller can have an asynchronously failing stop.
        // Explicit Stop retries quarantined retiring engines as well.
        for driver in Array(retiring.values) { driver.stop() }
        return ok && !shutdownPending
    }
}
