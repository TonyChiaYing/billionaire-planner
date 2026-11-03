import XCTest

/// UAT-01／02／03／04／05 的畫面層回歸測試（macOS）。
/// 以記憶體資料庫啟動（-uiTesting），不會碰到使用者的真實資料。
/// 所有入口都用 accessibility identifier 尋找「按鈕」元素再啟動，不依賴座標。
final class UATAccessibilityUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-fineTimeMode", "NO", "-dayStartMinute", "420", "-dayEndMinute", "1320"]
        app.launch()
        app.activate()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: 工具

    func button(_ id: String, timeout: TimeInterval = 5) -> XCUIElement {
        let b = app.buttons[id].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: timeout), "找不到按鈕 \(id)（可能不是可執行的按鈕）")
        return b
    }

    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func openTab(_ title: String) {
        let ids = ["今天": "today", "目標": "goals", "回顧": "review", "思考": "think"]
        let byID = app.descendants(matching: .any)["tab.\(ids[title] ?? title)"].firstMatch
        let candidates = [byID, app.outlines.staticTexts[title].firstMatch, app.cells.staticTexts[title].firstMatch,
                          app.staticTexts[title].firstMatch]
        _ = byID.waitForExistence(timeout: 8)
        guard let row = candidates.first(where: { $0.exists }) else {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bp-ui-diag")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
            try? app.debugDescription.write(to: dir.appendingPathComponent("tree.txt"), atomically: true, encoding: .utf8)
            XCTFail("找不到分頁 \(title)；windows=\(app.windows.count)；diag=\(dir.path)")
            return
        }
        row.click()
    }

    func type(into id: String, _ text: String) {
        let field = element(id)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "找不到欄位 \(id)")
        field.click()
        field.typeText(text)
    }

    /// 走完三步建立目標，停在第 4 步（接下來要怎麼做？）
    func createGoalToFinishStep(title: String = "UT Run 5K", action: String = "Walk-run 25 min") {
        openTab("目標")
        button("goals.new").click()
        type(into: "wizard.title", title)
        type(into: "wizard.outcome", "5K under 35 min")
        button("wizard.next").click()
        button("wizard.skip").click()
        type(into: "wizard.strategy", "Run Tue and Thu")
        type(into: "wizard.action", action)
        button("wizard.next").click()
        XCTAssertTrue(button("wizard.focusAndToday").exists)
    }

    // MARK: UAT-03：核心入口是可啟動的按鈕

    func testUAT03_ReviewEntriesAreActivatableButtons() {
        openTab("回顧")
        for id in ["review.workClose", "review.evening", "review.draft", "review.weekly"] {
            button(id).click()
            XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5), "\(id) 沒有開啟表單")
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 5), "\(id) 的表單沒有關閉")
        }
    }

    func testUAT03_TemplateEntryIsActivatableButton() {
        openTab("今天")
        button("today.skeleton").click()
        button("skeleton.createTemplate").click()
        XCTAssertTrue(app.staticTexts["上午工作"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(button("skeleton.applyTemplate").exists)
    }

    // MARK: UAT-01：建立完成後一次確認就到今天

    func testUAT01_FocusAndTodayFromWizard() {
        createGoalToFinishStep()
        button("wizard.focusAndToday").click()
        button("wizard.done").click()
        openTab("今天")
        XCTAssertTrue(app.staticTexts["Walk-run 25 min"].firstMatch.waitForExistence(timeout: 5))
    }

    func testUAT01_LaterHasNoSideEffects() {
        createGoalToFinishStep()
        button("wizard.later").click()
        XCTAssertTrue(app.staticTexts["焦點目標 0/5"].firstMatch.waitForExistence(timeout: 5))
        openTab("今天")
        XCTAssertFalse(app.staticTexts["Walk-run 25 min"].firstMatch.waitForExistence(timeout: 2))
    }

    // MARK: UAT-04：停止但不記錄

    func testUAT04_StopWithoutRecordingClearsFocus() {
        createGoalToFinishStep()
        button("wizard.focusAndToday").click()
        button("wizard.done").click()
        openTab("今天")
        button("today.focus").click()
        button("focus.stopNoRecord").click()
        XCTAssertTrue(app.buttons["開始專注"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(element("today.focusing").exists)
    }

    // MARK: UAT-05：容量與休息分開

    func testUAT05_LowLoadShowsComfortableAndRestSeparately() {
        createGoalToFinishStep()
        button("wizard.focusAndToday").click()
        button("wizard.done").click()
        openTab("今天")
        XCTAssertTrue(app.staticTexts["容量：寬鬆"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["需要補休息"].firstMatch.exists)
    }

    // MARK: UAT-02：完成行動不會自動變成成果

    func testUAT02_EveningCloseWithoutSelectionCreatesNoOutcome() {
        createGoalToFinishStep()
        button("wizard.focusAndToday").click()
        button("wizard.done").click()
        openTab("今天")
        button("today.complete").click()
        openTab("回顧")
        button("review.evening").click()
        button("evening.done").click()
        if app.sheets.firstMatch.waitForExistence(timeout: 3) { app.typeKey(.escape, modifierFlags: []) }
        XCTAssertTrue(app.staticTexts["還沒有成果紀錄。"].firstMatch.waitForExistence(timeout: 5))
    }
}
