import XCTest

/// These scenarios require Xcode and an iOS Simulator. They have NOT been executed on Linux.
final class PulseLoomUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["PULSELOOM_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        let enter = app.buttons["welcomeEnter"]
        if enter.waitForExistence(timeout: 8) { enter.tap() }
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
    }
    override func tearDownWithError() throws { app.terminate() }
    func testExactlyFourApprovedTabs() {
        let tabs = app.tabBars.buttons
        XCTAssertEqual(tabs.count, 4)
        for title in ["Home", "Music", "Create", "My"] { XCTAssertTrue(tabs[title].exists) }
    }
    func testHomeHasPresetsAndIndependentStop() {
        XCTAssertTrue(app.buttons["preset.p02"].exists)
        XCTAssertTrue(app.buttons["hapticStart"].isHittable)
        XCTAssertTrue(app.buttons["hapticStop"].isHittable)
        app.buttons["preset.p01"].tap()
        XCTAssertTrue(app.staticTexts["currentPattern"].label.contains("Still"))
    }
    func testMusicIsOneTapAway() {
        app.tabBars.buttons["Music"].tap()
        XCTAssertTrue(app.buttons["Choose music"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["hapticStart"].exists)
    }
    func testCreateRetainsNameAcrossTabs() {
        app.tabBars.buttons["Create"].tap()
        let name = app.textFields["patternName"]
        if !name.isHittable { app.swipeUp() }
        name.tap()
        name.typeText("My touch")
        // Complete text entry through the same visible control as a user. The
        // keyboard must finish dismissing before coordinates for a tab are used.
        let done = app.buttons["editorKeyboardDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        let keyboardHidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardHidden], timeout: 5), .completed)
        let my = app.tabBars.buttons["My"]
        XCTAssertTrue(my.isHittable)
        my.tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        let create = app.tabBars.buttons["Create"]
        XCTAssertTrue(create.isHittable)
        create.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "My touch")
    }
    func testTimerChoiceAppliesWithoutSecondConfirmation() {
        app.buttons["timerButton"].tap()
        let choice = app.buttons["5 min"]
        XCTAssertTrue(choice.waitForExistence(timeout: 3))
        choice.tap()
        XCTAssertTrue(app.buttons["timerButton"].label.contains("5"))
    }
    func testEveryTabCanReturnHome() {
        for title in ["Music", "Create", "My"] {
            app.tabBars.buttons[title].tap()
            app.tabBars.buttons["Home"].tap()
            XCTAssertTrue(app.buttons["hapticStop"].exists)
        }
    }
    func testAllPresetsUsesSheet() {
        app.buttons["All presets"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["hapticStart"].exists)
    }
    func testMyKeepsSettingsAccessible() {
        app.tabBars.buttons["My"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 3))
    }
}
