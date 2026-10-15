import XCTest
import CoreHaptics
import PulseLoomCore
@testable import PulseLoom

@MainActor private final class TouchPlayer: HapticPlayerIO {
    var completionHandler: ((Error?) -> Void)?
    var loopEnabled = false
    var loopEnd = 0.0
    func start(atTime: TimeInterval) throws {}
    func stop(atTime: TimeInterval) throws {}
    func sendParameters(_ parameters: [CHHapticDynamicParameter], atTime: TimeInterval) throws {}
}
@MainActor private final class TouchEngine: HapticEngineIO {
    var stoppedHandler: ((CHHapticEngine.StoppedReason) -> Void)?
    var resetHandler: (() -> Void)?
    var isMutedForHaptics = false
    var controllerTone: ControllerTone? { nil }
    func start() throws {}
    func stop(completion: @escaping (Error?) -> Void) { completion(nil) }
    func makeAdvancedPlayer(with pattern: CHHapticPattern) throws -> any HapticPlayerIO { TouchPlayer() }
}
@MainActor final class FirstTouchTests: XCTestCase {
    private var root: URL!
    private var time = 0.0
    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        AppLanguage.apply("system", persist: false)
    }
    private func fixture(supported: Bool = true) throws -> (AppModel, FirstTouchSession) {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let driver = HapticDriver(makeEngine: { TouchEngine() }, supportsHaptics: { supported },
                                  isForeground: { true }, thermalSafe: { true })
        let playback = PlaybackCoordinator(driver: driver, now: { self.time })
        // Keep service tests on the injected phone even if a physical controller is connected.
        playback.outputs.controllers.select(.phone)
        let app = AppModel(library: LibraryStore(root: root), playback: playback)
        return (app, FirstTouchSession(app: app))
    }
    private func complete(_ app: AppModel, _ session: FirstTouchSession) {
        time += 1
        app.playback.tick()
        session.playbackChanged()
        XCTAssertEqual(session.stage, .feedback)
    }
    func testSaveRequiresCompletedRealOutputAndSurvivesLibraryReload() throws {
        let (app, session) = try fixture()
        session.save()
        XCTAssertNil(app.prefs.firstTouchGain)
        session.start()
        XCTAssertEqual(session.stage, .playing)
        session.save()
        XCTAssertFalse(app.prefs.onboarded)
        complete(app, session)
        session.adjust(stronger: true)
        XCTAssertEqual(session.gain, 0.45, accuracy: 0.001)
        XCTAssertEqual(app.playback.state, .completed, "Adjusting must not start output")
        session.start(); complete(app, session); session.save()
        XCTAssertTrue(app.prefs.onboarded)
        XCTAssertEqual(app.prefs.firstTouchGain, 0.45)
        XCTAssertEqual(LibraryStore(root: root).snapshot.preferences.gain, 0.45)
        XCTAssertEqual(session.stage, .saved)
        session.stop()
    }
    func testUnavailableDeviceCannotBecomeSuccessfulExperience() throws {
        let (app, session) = try fixture(supported: false)
        XCTAssertNotNil(session.availabilityError)
        session.stop()
        XCTAssertNil(session.message, "Opening device help before testing is not an interrupted test")
        session.start(); session.save()
        XCTAssertEqual(session.stage, .ready)
        XCTAssertNotNil(session.message)
        XCTAssertNil(app.prefs.firstTouchGain)
        XCTAssertFalse(app.prefs.onboarded)
        session.stop()
    }
    func testStopInterruptionAndReplacementInvalidateFeedbackWithoutStoppingNewOwner() throws {
        let (app, session) = try fixture()
        session.start(); session.stop(); session.save()
        XCTAssertNil(app.prefs.firstTouchGain)
        session.start(); app.playback.interrupt(T("error.interruption")); session.playbackChanged()
        XCTAssertEqual(session.stage, .ready)
        session.start(); complete(app, session)
        try app.playback.begin(HapticPattern(name: "Other"), duration: 10, gain: 0.5)
        session.playbackChanged(); session.save(); session.stop()
        XCTAssertNil(app.prefs.firstTouchGain)
        XCTAssertTrue(app.playback.isPlaying, "A stale first-touch screen cannot stop a replacement session")
        session.stopByUser()
        XCTAssertFalse(app.playback.isPlaying, "An explicit Stop action must stop the current output")
    }
    func testLevelsAreBoundedAndNoComfortIsAssumedAtEitherLimit() throws {
        let (app, session) = try fixture()
        for _ in 0..<7 { session.start(); complete(app, session); session.adjust(stronger: true) }
        XCTAssertEqual(session.gain, 1)
        XCTAssertEqual(session.message, T("touch.ceiling"))
        XCTAssertNil(app.prefs.firstTouchGain)
        for _ in 0..<8 { session.start(); complete(app, session); session.adjust(stronger: false) }
        XCTAssertEqual(session.gain, 0.1)
        XCTAssertEqual(session.message, T("touch.minimum"))
        XCTAssertNil(app.prefs.firstTouchGain)
        session.stop()
    }
    func testLegacyPreferencesAndInvalidCalibration() throws {
        var original = Preferences(); original.gain = 0.8; original.onboarded = true
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "firstTouchGain")
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.gain, 0.8)
        XCTAssertNil(restored.firstTouchGain)
        XCTAssertEqual(Preferences().gain, 0.35)
        let (app, _) = try fixture()
        XCTAssertThrowsError(try app.library.preferences { $0.firstTouchGain = 2 })
        XCTAssertNil(app.prefs.firstTouchGain)
    }
    func testChineseMessagesCoverOutputStorageNetworkAndUnknownSDKFailures() {
        AppLanguage.apply("zh-Hans", persist: false)
        let samples: [Error] = [
            LoomError.unavailable("No haptic output is available."),
            LoomError.unavailable("Selected controller is disconnected."),
            LoomError.invalid("Audio must be at most 30 MB."),
            LoomError.storage("Injected disk failure"),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet),
            NSError(domain: "SDK.Private", code: -4810, userInfo: [NSLocalizedDescriptionKey: "Raw English failure"])
        ]
        for error in samples {
            let message = UserFacingError.message(error)
            XCTAssertNotEqual(message, error.localizedDescription)
            XCTAssertNotNil(message.range(of: "[\\p{Han}]", options: .regularExpression))
            XCTAssertFalse(message.contains("Raw English"))
        }
        let englishBundle = Bundle(path: Bundle.main.path(forResource: "en", ofType: "lproj")!)!
        let englishThermal = englishBundle.localizedString(forKey: "error.thermal", value: nil, table: nil)
        XCTAssertEqual(UserFacingError.message(LoomError.unavailable(englishThermal)), T("error.thermal"))
        let restricted = englishBundle.localizedString(forKey: "export.restricted", value: nil, table: "Recovery")
        XCTAssertEqual(UserFacingError.message(LoomError.invalid(restricted)),
                       AppLanguage.bundle.localizedString(forKey: "export.restricted", value: nil, table: "Recovery"))
        XCTAssertEqual(UserFacingError.message(LoomError.unavailable("Haptic shutdown is not confirmed: SDK failure")), T("error.outputStopping"))
        XCTAssertTrue(UserFacingError.message(samples[0]).contains("输出设备"))
        XCTAssertTrue(UserFacingError.message(samples[1]).contains("重新连接"))
        XCTAssertEqual(UserFacingError.message(LoomError.unavailable(T("error.thermal"))), T("error.thermal"))
        AppLanguage.apply("ja", persist: false)
        XCTAssertEqual(UserFacingError.message(samples[0]), T("error.outputUnavailable"))
        AppLanguage.apply("en", persist: false)
        XCTAssertEqual(UserFacingError.message(samples[0]), T("error.outputUnavailable"))
    }
}
