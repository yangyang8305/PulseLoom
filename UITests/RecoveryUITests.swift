import XCTest

/// A corrupt file is seeded only into an isolated UUID-named DEBUG test directory.
/// Real parsing, startup routing and recovery run normally; no success state is injected.
final class RecoveryUITests: XCTestCase {
    func testAUD06RecoveryIsReachableBeforeOnboardingAndRestoresBackup() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["PULSELOOM_UI_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["PULSELOOM_CORRUPT_LIBRARY_FIXTURE"] = "1"
        app.launch()
        defer { app.terminate() }
        let restore = app.buttons["recoveryRestorePrevious"]
        XCTAssertTrue(restore.waitForExistence(timeout: 8), "AUD-06: recovery cannot be hidden behind onboarding writes to an unreadable library")
        restore.tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["currentPattern"].label.contains("Recovered fixture"))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["currentPattern"].label.contains("Recovered fixture"))
    }
}
