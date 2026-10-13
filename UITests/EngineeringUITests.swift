import XCTest

/// Acceptance criteria are observable user outcomes. UUID only isolates the actual persistence store.
@MainActor final class EngineeringAcceptanceTests: JourneyCase {
    func testJapaneseAppearanceSheetUpdatesAndDismisses() {
        launch("ja"); enter("ホーム")
        for mode in ["ダーク", "ライト"] {
            tap(app.tabBars.buttons["マイページ"])
            tap(named("テーマと外観"))
            let choice = app.segmentedControls.buttons[mode]
            tap(choice)
            wait("selected == true", on: choice)
            // Retain the native title and segmented control for visual contrast verification.
            capture("theme-sheet-" + mode)
            let done = app.buttons["完了"]
            tap(done)
            wait("exists == false", on: done)
            let home = app.tabBars.buttons["ホーム"]
            XCTAssertTrue(home.isHittable)
            tap(home)
            wait("selected == true", on: home)
            XCTAssertTrue(app.buttons["hapticStop"].isHittable)
        }
    }
    func testEnglishCoreControlsAndStrengthTestAreReachable() {
        launch(); enter()
        XCTAssertTrue(app.buttons["hapticStart"].isHittable)
        XCTAssertTrue(app.buttons["hapticStop"].isHittable)
        tap(app.buttons["Adjust feel"])
        XCTAssertTrue(app.buttons["homeTestStrength"].waitForExistence(timeout: 5))
        tap(app.buttons["Done"])
        XCTAssertTrue(app.buttons["hapticStop"].isHittable)
        capture("acceptance-core-controls")
    }
    func testJapaneseUserCanReachStrengthTestWithoutKnowingChineseLabels() {
        launch("ja"); enter("ホーム")
        XCTAssertTrue(app.buttons["hapticStart"].isHittable)
        XCTAssertTrue(app.buttons["hapticStop"].isHittable)
        tap(app.buttons["感触を調整"])
        XCTAssertTrue(app.buttons["homeTestStrength"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["homeTestStrength"].label.contains("強さ"))
        capture("acceptance-japanese-test-entry")
    }
    func testChineseUserCanReachOutputAndLanguageSettings() {
        launch("zh-Hans"); enter("首页")
        tap(app.tabBars.buttons["我的"])
        tap(app.buttons["设置"])
        let language = app.descendants(matching: .any).matching(identifier: "settingsLanguage").firstMatch
        // Form virtualizes rows below the viewport at large text sizes; reach it as a user would.
        reach(language)
        XCTAssertTrue(language.isHittable, "Language settings must be reachable, including after scrolling")
        let output = app.buttons["触觉输出设备"]
        // Return to the first settings row; it may be virtualized above the language row.
        for _ in 0..<6 {
            if output.exists && output.isHittable { break }
            app.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(output.exists && output.isHittable)
        tap(output)
        let scan = app.buttons["outputScan"]
        reach(scan)
        XCTAssertTrue(scan.isHittable)
        let test = app.buttons["outputTest"]
        reach(test)
        XCTAssertTrue(test.isHittable)
        capture("acceptance-chinese-settings")
    }
}

@MainActor final class EngineeringSystemTests: JourneyCase {
    func testActualBundledMusicLoadAndLibraryReplacement() {
        launch(); enter()
        tap(app.tabBars.buttons["Music"])
        tap(app.buttons["track.t01"])
        XCTAssertTrue(app.buttons["Start following"].waitForExistence(timeout: 20), "Real decoding/analysis must complete")
        tap(app.buttons["musicLibrary"])
        tap(app.buttons["library.t02"])
        XCTAssertTrue(app.buttons["Start following"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Change"].exists)
        capture("system-music-replacement")
    }
    func testSeededRandomTabTransitionsNeverLoseIndependentStop() {
        launch(); enter()
        var state: UInt64 = 0xA11CE
        let tabs = ["Home", "Music", "Create", "My"]
        for step in 0..<24 {
            state = state &* 6364136223846793005 &+ 1
            let tab = tabs[Int((state >> 32) % 4)]
            tap(app.tabBars.buttons[tab])
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected, "seed=A11CE step=\(step) tab=\(tab)")
            tap(app.tabBars.buttons["Home"])
            XCTAssertTrue(app.buttons["hapticStop"].isHittable, "seed=A11CE step=\(step)")
            tap(app.buttons["hapticStop"])
        }
        app.terminate(); launch()
        XCTAssertTrue(app.buttons["hapticStop"].waitForExistence(timeout: 8))
        capture("system-random-navigation-restart")
    }
}
