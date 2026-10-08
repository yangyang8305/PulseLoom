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

/// Real XCUI gestures. The UUID only isolates storage; no Pro/haptic/backend result is injected.
@MainActor class JourneyCase: XCTestCase {
    var app = XCUIApplication()
    var storageID = UUID().uuidString
    var step = 0
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        capture("end-" + name)
        app.terminate()
    }
    func capture(_ label: String) {
        step += 1
        let tag = String(format: "%02d", step) + "-" + label
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "FLOW-" + tag; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "TREE-" + tag; tree.lifetime = .keepAlways; add(tree)
    }
    func launch(_ language: String = "en", corrupt: Bool = false) {
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "ja" ? "ja_JP" : language == "zh-Hans" ? "zh_CN" : "en_US"]
        app.launchEnvironment["PULSELOOM_UI_TEST_ID"] = storageID
        if corrupt { app.launchEnvironment["PULSELOOM_CORRUPT_LIBRARY_FIXTURE"] = "1" }
        app.launch()
    }
    func enter(_ tab: String = "Home") {
        tap(app.buttons["welcomeEnter"])
        XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 8))
    }
    func reach(_ e: XCUIElement) {
        // Give a newly presented sheet or system picker time to populate before
        // swiping: an early swipe can dismiss the sheet instead of revealing a row.
        _ = e.waitForExistence(timeout: 5)
        for _ in 0..<9 {
            if e.exists && e.isHittable { return }
            app.swipeUp(velocity: .slow)
        }
        XCTFail("Unreachable control: \(e)")
    }
    func tap(_ e: XCUIElement) {
        reach(e)
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    func named(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }
    func text(_ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }
    func wait(_ predicate: String, on element: XCUIElement, seconds: Double = 8) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: seconds), .completed, predicate)
    }
    func setName(_ value: String) {
        let field = app.textFields["patternName"]; tap(field)
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        field.typeText(value)
        tap(app.buttons["editorKeyboardDone"])
        wait("exists == false", on: app.keyboards.firstMatch)
        XCTAssertEqual(field.value as? String, value)
    }
    func create(_ title: String, exerciseUndo: Bool = false) {
        tap(app.tabBars.buttons["Create"])
        tap(app.segmentedControls.buttons["Arrange"])
        XCTAssertTrue(text("4 segments").exists)
        if exerciseUndo {
            tap(app.buttons["Add segment"])
            XCTAssertTrue(text("5 segments").exists)
            capture("create-added-segment")
            tap(app.buttons["More options"])
            tap(app.buttons["Undo"])
            XCTAssertTrue(text("4 segments").exists)
            XCTAssertFalse(text("5 segments").exists)
            capture("create-undo-restored-four")
        }
        setName(title)
        tap(app.buttons["savePattern"])
        wait("label CONTAINS 'Saved'", on: app.buttons["savePattern"])
        capture("create-saved-" + title)
    }
    func saved() {
        tap(app.tabBars.buttons["My"])
        tap(named("My patterns"))
        XCTAssertTrue(app.navigationBars["My patterns"].waitForExistence(timeout: 5))
    }
    func privacy() {
        tap(app.tabBars.buttons["My"]); tap(app.buttons["Settings"])
        tap(app.buttons["Privacy & data"])
    }
}

@MainActor final class UserJourneyTests: JourneyCase {
    func test01FirstLaunchAndHomeVisibleFailureStopRestart() {
        launch(); capture("01-first-entry")
        enter(); tap(app.buttons["preset.p01"])
        XCTAssertTrue(app.staticTexts["currentPattern"].label.contains("Still"))
        tap(app.buttons["hapticStart"])
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), "Simulator must report the unavailable actuator, not a fake successful vibration")
        XCTAssertTrue(app.alerts.firstMatch.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'iPhone' OR label CONTAINS[c] 'haptic'")).count > 0)
        capture("01-real-hardware-unavailable")
        tap(app.alerts.buttons["Done"])
        XCTAssertTrue(app.buttons["hapticStart"].label.contains("Start"))
        tap(app.buttons["preset.p02"])
        XCTAssertFalse(app.staticTexts["currentPattern"].label.contains("Still"))
        let selection = app.staticTexts["currentPattern"].label
        tap(app.buttons["hapticStop"])
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.buttons["hapticStart"].label.contains("Start"))
        capture("01-switch-and-stop")
        app.terminate(); launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["welcomeEnter"].exists)
        XCTAssertEqual(app.staticTexts["currentPattern"].label, selection)
        capture("01-restart-keeps-selection-not-playing")
    }
    func test02CreateEditUndoSaveAndFindAfterRestart() {
        launch(); enter(); create("Journey Original", exerciseUndo: true)
        app.terminate(); launch(); saved()
        tap(named("Journey Original"))
        XCTAssertTrue(text("Journey Original").waitForExistence(timeout: 5))
        XCTAssertTrue(text("2.0").exists, "Saved duration after undo must remain the original two seconds")
        capture("02-saved-work-reopened-after-restart")
    }
    func test03OriginalExportToFilesAndImportAgain() {
        let title = "Roundtrip Original " + String(storageID.prefix(6))
        let fileName = "PulseLoom-pattern-" + String(storageID.prefix(8))
        launch(); enter(); create(title)
        saved(); tap(named(title)); tap(app.buttons["Export"])
        capture("03-native-share-sheet")
        // UIKit exposes share actions as collection-view cells, not buttons.
        let saveToFiles = app.cells["Save to Files"]
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 8))
        tap(saveToFiles)
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 8))
        tap(filename)
        let oldFilename = filename.value as? String ?? ""
        filename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldFilename.count))
        filename.typeText(fileName)
        wait("value == '\(fileName)'", on: filename)
        capture("03-native-save-location")
        if app.buttons["On My iPhone"].exists { tap(app.buttons["On My iPhone"]) }
        tap(save)
        if app.alerts.buttons["Replace"].waitForExistence(timeout: 1) { app.alerts.buttons["Replace"].tap() }
        wait("exists == false", on: save)
        app.terminate(); launch(); saved(); tap(app.buttons["Import patterns"])
        let browse = app.tabBars["DOC.browsingModeTabBar"].buttons["Browse"]
        XCTAssertTrue(browse.waitForExistence(timeout: 10))
        tap(browse)
        let navigation = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 8))
        let locations = navigation.buttons["Browse"]
        if locations.waitForExistence(timeout: 3) { tap(locations) }
        let local = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'On My iPhone'")
        )
        let localReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            local.allElementsBoundByIndex.contains { $0.isHittable }
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [localReady], timeout: 8), .completed)
        guard let localLocation = local.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("On My iPhone is not reachable in the system Files picker")
            return
        }
        tap(localLocation)
        capture("03-native-import-picker")
        // Select the current, visible file cell; remote picker hierarchies can
        // retain obscured collections from a previous browsing location.
        let documents = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", fileName))
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            documents.allElementsBoundByIndex.contains { $0.isHittable }
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed)
        guard let document = documents.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("The exported document is not reachable in On My iPhone")
            return
        }
        tap(document)
        wait("exists == true", on: app.navigationBars["My patterns"])
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).count, 2)
        capture("03-two-works-after-native-import")
        app.terminate(); launch(); saved()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).count, 2)
        capture("03-import-persists-after-restart")
    }
    func test04PaidPresetExportIsBlockedWithoutShareSheet() {
        launch(); enter(); tap(app.buttons["All presets"])
        let search = app.searchFields.firstMatch; tap(search); search.typeText("Rolling")
        if app.keyboards.buttons["Search"].exists { app.keyboards.buttons["Search"].tap() }
        capture("04-paid-preset-search")
        tap(app.buttons["info.circle"])
        tap(app.buttons["Export"])
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.firstMatch.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'export' OR label CONTAINS[c] 'paid'")).count > 0)
        XCTAssertFalse(app.buttons["Save to Files"].exists)
        capture("04-paid-export-denied")
    }
    func test05MusicSampleLoadPickerCancelAndReplacement() {
        launch(); enter(); tap(app.tabBars.buttons["Music"])
        tap(app.buttons["demoMusic"])
        XCTAssertTrue(text("Petal-Steps").waitForExistence(timeout: 15))
        XCTAssertTrue(text("00:48").exists)
        capture("05-local-sample-loaded")
        tap(app.buttons["Change"])
        capture("05-system-source-picker")
        tap(app.buttons["Cancel"])
        XCTAssertTrue(text("Petal-Steps").waitForExistence(timeout: 5))
        XCTAssertTrue(text("00:48").exists)
        capture("05-picker-cancel-keeps-original")
        tap(app.buttons["demoMusic"])
        XCTAssertTrue(text("Petal-Steps").waitForExistence(timeout: 15))
        capture("05-sample-reload")
    }
    func test06ClearRemovesSavedAndOpenDraftAfterRestart() {
        launch(); enter(); create("Erase This Work")
        privacy(); tap(app.buttons["Delete local creations and records"])
        capture("06-clear-confirmation")
        tap(app.buttons["Delete"])
        app.terminate(); launch()
        if app.buttons["welcomeEnter"].waitForExistence(timeout: 2) { enter() }
        saved()
        XCTAssertTrue(text("Your first pattern starts here.").waitForExistence(timeout: 5))
        XCTAssertFalse(text("Erase This Work").exists)
        capture("06-restart-empty-library")
        tap(app.tabBars.buttons["Create"])
        let field = app.textFields["patternName"]; reach(field)
        XCTAssertNotEqual(field.value as? String, "Erase This Work")
        app.terminate(); launch(); saved()
        XCTAssertTrue(text("Your first pattern starts here.").waitForExistence(timeout: 5))
        capture("06-no-draft-resurrection")
    }
    func test07CorruptLibraryRecoveryUIAndRestart() {
        launch(corrupt: true)
        capture("07-corrupt-library-before-recovery")
        tap(app.buttons["recoveryRestorePrevious"])
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["currentPattern"].label.contains("Recovered fixture"))
        capture("07-restored-real-previous-file")
        app.terminate(); launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["currentPattern"].label.contains("Recovered fixture"))
        saved(); XCTAssertTrue(named("Recovered fixture").exists)
        capture("07-recovery-survives-restart")
    }
}

@MainActor final class LayoutJourneyTests: JourneyCase {
    func testEnglishTabsAndAppearance() throws { try inspect("en", tabs: ["Home", "Music", "Create", "My"], theme: "Themes & appearance", modes: ["Light", "Dark"], done: "Done") }
    func testChineseTabsAndAppearance() throws { try inspect("zh-Hans", tabs: ["首页", "音乐", "创作", "我的"], theme: "主题与外观", modes: ["浅色", "深色"], done: "完成") }
    func testJapaneseTabsAndAppearance() throws { try inspect("ja", tabs: ["ホーム", "音楽", "作成", "マイページ"], theme: "テーマと外観", modes: ["ライト", "ダーク"], done: "完了") }
    func inspect(_ lang: String, tabs: [String], theme: String, modes: [String], done: String) throws {
        launch(lang); capture("layout-" + lang + "-welcome"); enter(tabs[0])
        for mode in modes {
            tap(app.tabBars.buttons[tabs[3]]); tap(named(theme))
            tap(app.segmentedControls.buttons[mode])
            XCTAssertTrue(app.segmentedControls.buttons[mode].isSelected)
            tap(app.buttons[done])
            for (index, title) in tabs.enumerated() {
                let tab = app.tabBars.buttons[title]; tap(tab)
                wait("selected == true", on: tab)
                XCTAssertTrue(tab.isSelected)
                XCTAssertEqual(app.tabBars.buttons.count, 4)
                let screen = app.windows.firstMatch.frame
                for item in app.tabBars.buttons.allElementsBoundByIndex {
                    XCTAssertTrue(item.isHittable)
                    XCTAssertTrue(screen.insetBy(dx: -1, dy: -1).contains(item.frame))
                }
                if index == 0 {
                    XCTAssertTrue(app.buttons["hapticStart"].isHittable)
                    XCTAssertTrue(app.buttons["hapticStop"].isHittable)
                }
                capture("layout-\(lang)-\(mode)-tab\(index)")
                // Diagnostic collection, NOT an accessibility pass. Retain every issue.
                // One issue must not hide the other pages/languages from the evidence.
                var findings: [String] = []
                if #available(iOS 17.0, *) {
                    try app.performAccessibilityAudit(for: .all) { issue in
                        findings.append(String(describing: issue))
                        return true
                    }
                }
                let result: [String: Any] = ["language": lang, "appearance": mode, "tab": title,
                    "status": findings.isEmpty ? "no_issues_reported" : "issues_detected",
                    "diagnostic_only": true, "issue_count": findings.count, "issues": findings]
                let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "ACCESSIBILITY-\(lang)-\(mode)-tab\(index)"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }
}
