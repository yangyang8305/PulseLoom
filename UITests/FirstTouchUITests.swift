import XCTest

@MainActor final class FirstTouchUITests: JourneyCase {
    func testChineseUnavailableDeviceOffersHelpWithoutClaimingComfort() {
        launch("zh-Hans")
        tap(app.buttons["welcomeFirstTouch"])
        XCTAssertTrue(app.staticTexts["firstTouchDevice"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["firstTouchUnavailable"].exists)
        XCTAssertFalse(app.buttons["firstTouchPlay"].isEnabled)
        XCTAssertFalse(app.buttons["firstTouchComfortable"].exists)
        let reason = app.staticTexts["firstTouchUnavailable"].label
        XCTAssertTrue(reason.contains("输出设备"))
        let check = app.buttons["firstTouchCheckDevice"]
        XCTAssertTrue(check.label.contains("检查或更换输出设备"))
        tap(check)
        XCTAssertTrue(app.navigationBars["触觉输出设备"].waitForExistence(timeout: 5))
        capture("first-touch-unavailable-device-help")
    }
    func testSkipRetainsGentlerDefaultAfterRestart() {
        launch("zh-Hans"); enter("首页")
        let intensity = app.descendants(matching: .any).matching(identifier: "homeIntensity").firstMatch
        XCTAssertTrue(intensity.waitForExistence(timeout: 5))
        XCTAssertEqual(intensity.value as? String, "35%")
        app.terminate(); launch("zh-Hans")
        XCTAssertTrue(app.buttons["hapticStop"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["welcomeEnter"].exists)
        XCTAssertTrue(intensity.waitForExistence(timeout: 5))
        XCTAssertEqual(intensity.value as? String, "35%")
        capture("first-touch-skip-persists-default")
    }
    func testChineseMusicOutputErrorIsActionableAndLocalized() {
        launch("zh-Hans"); enter("首页")
        tap(app.tabBars.buttons["音乐"])
        tap(app.buttons["track.t01"])
        XCTAssertTrue(app.buttons["开始跟随"].waitForExistence(timeout: 20))
        tap(app.buttons["开始跟随"])
        let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "当前没有可用的触感输出")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 8))
        XCTAssertTrue(message.label.contains("输出设备"))
        XCTAssertFalse(app.staticTexts["No haptic output is available."].exists)
        let check = app.buttons["musicCheckOutput"]
        reach(check)
        XCTAssertTrue(check.isHittable)
        tap(check)
        XCTAssertTrue(app.navigationBars["触觉输出设备"].waitForExistence(timeout: 5))
        capture("music-localized-output-error")
    }
    func testEnglishFirstTouchEntryIsLocalized() {
        launch(); tap(app.buttons["welcomeFirstTouch"])
        XCTAssertTrue(app.navigationBars["First touch experience"].waitForExistence(timeout: 8))
        wait("hittable == true", on: app.buttons["firstTouchStop"], seconds: 5)
        XCTAssertTrue(app.buttons["firstTouchStop"].isHittable, "Stop must be reachable without scrolling")
        XCTAssertFalse(app.buttons["firstTouchComfortable"].exists)
        capture("first-touch-english")
    }
    func testJapaneseFirstTouchEntryIsLocalized() {
        launch("ja"); tap(app.buttons["welcomeFirstTouch"])
        XCTAssertTrue(app.navigationBars["はじめての触覚体験"].waitForExistence(timeout: 8))
        wait("hittable == true", on: app.buttons["firstTouchStop"], seconds: 5)
        XCTAssertTrue(app.buttons["firstTouchStop"].isHittable, "Stop must be reachable without scrolling")
        XCTAssertFalse(app.buttons["firstTouchComfortable"].exists)
        capture("first-touch-japanese")
    }
}
