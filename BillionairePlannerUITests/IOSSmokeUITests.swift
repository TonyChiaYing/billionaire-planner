#if os(iOS)
import XCTest

/// V205-IOS：iPhone 模擬器上的主要流程。以記憶體資料庫啟動（-uiTesting），不碰真實資料。
/// 每個畫面都存截圖，並檢查表單沒有超出螢幕（V205-IOS-01）。
final class IOSSmokeUITests: XCTestCase {
    var app: XCUIApplication!
    let diag = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bp-ios-diag")

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: diag, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-fineTimeMode", "NO", "-dayStartMinute", "420", "-dayEndMinute", "1320"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15), "沒有出現分頁列")
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 { shot("failure") }
        print("ios-diag=\(diag.path)")
        app.terminate()
    }

    func shot(_ tag: String) {
        let base = "\(name)-\(tag)".replacingOccurrences(of: " ", with: "_")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: diag.appendingPathComponent("\(base).png"))
        if tag == "failure" {
            try? app.debugDescription.write(to: diag.appendingPathComponent("\(base).txt"), atomically: true, encoding: .utf8)
        }
    }

    var screenWidth: CGFloat { app.windows.firstMatch.frame.width }

    func tab(_ title: String) {
        let b = app.tabBars.buttons[title]
        XCTAssertTrue(b.waitForExistence(timeout: 5), "找不到分頁 \(title)")
        b.tap()
    }

    func el(_ id: String, timeout: TimeInterval = 5) -> XCUIElement {
        let e = app.descendants(matching: .any)[id].firstMatch
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "找不到 \(id)")
        return e
    }

    /// 元素完整在螢幕寬度內（表單沒有被切掉）
    func assertFits(_ e: XCUIElement, _ what: String) {
        XCTAssertGreaterThanOrEqual(e.frame.minX, -1, "\(what) 左邊超出螢幕：\(e.frame)")
        XCTAssertLessThanOrEqual(e.frame.maxX, screenWidth + 1, "\(what) 右邊超出螢幕：\(e.frame) / 螢幕寬 \(screenWidth)")
    }

    func type(_ id: String, _ text: String) {
        let f = el(id)
        f.tap()
        f.typeText(text)
    }

    func testIOS_AllTabsOpen() {
        for t in ["今天", "目標", "回顧", "思考"] {
            tab(t)
            XCTAssertTrue(app.navigationBars[t].waitForExistence(timeout: 5), "\(t) 沒有標題列")
            shot("tab-\(t)")
        }
    }

    func testIOS_CreateGoalPlanTodayAndComplete() {
        tab("目標")
        el("goals.new").tap()
        let title = el("wizard.title")
        assertFits(title, "建立目標的名稱欄")
        shot("wizard-1")
        type("wizard.title", "UT Run 5K")
        type("wizard.outcome", "5K under 35 min")
        el("wizard.next").tap()
        el("wizard.skip").tap()
        type("wizard.strategy", "Run Tue and Thu")
        type("wizard.action", "Walk-run 25 min")
        el("wizard.next").tap()
        let both = el("wizard.focusAndToday")
        assertFits(both, "加入焦點並安排今天")
        shot("wizard-4")
        both.tap()
        el("wizard.done").tap()
        tab("今天")
        XCTAssertTrue(app.staticTexts["Walk-run 25 min"].firstMatch.waitForExistence(timeout: 5))
        let done = el("today.complete")
        assertFits(done, "完成按鈕")
        done.tap()
        XCTAssertTrue(el("today.allDone").exists)
        shot("today-done")
    }

    func testIOS_EveningCloseFitsScreen() {
        tab("回顧")
        el("review.evening").tap()
        let done = el("evening.done")
        assertFits(done, "完成日結")
        shot("evening")
    }

    func testIOS_SettingsZoomAndTutorial() {
        tab("今天")
        let gear = app.navigationBars.buttons["設定"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5), "找不到設定按鈕")
        gear.tap()
        let zoomIn = el("zoom.in")
        assertFits(zoomIn, "放大按鈕")
        zoomIn.tap()
        XCTAssertEqual(el("zoom.value").label, "110%")
        shot("settings-zoom")
        el("settings.tutorial").tap()
        let title = el("tutorial.title")
        assertFits(title, "教學標題")
        assertFits(el("tutorial.next"), "教學的下一步")
        shot("tutorial-1")
        var pages = 1
        while app.buttons["tutorial.next"].exists && pages < 20 {
            app.buttons["tutorial.next"].tap()
            pages += 1
        }
        XCTAssertEqual(pages, 10)
        shot("tutorial-last")
        el("tutorial.finish").tap()
    }
}
#endif
