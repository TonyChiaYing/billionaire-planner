import XCTest

/// UAT-01／02／03／04／05 的畫面層回歸測試（macOS）。
/// 以記憶體資料庫啟動（-uiTesting），不會碰到使用者的真實資料。
/// 所有入口都用 accessibility identifier 尋找「按鈕」元素再啟動，不依賴座標。
final class UATAccessibilityUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // V201-UAT-02：-uiTesting 時 App 自行把視窗置中於主螢幕；同時忽略先前保存的視窗狀態
        app.launchArguments = ["-uiTesting", "YES", "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
                               "-fineTimeMode", "NO", "-dayStartMinute", "420", "-dayEndMinute", "1320"]
        app.launch()
        app.activate()
        // 無頭 CI 工作階段有時不會自動開出主視窗：用標準選單「檔案 → 新增視窗」開一個（使用者環境不受影響）
        if !app.windows.firstMatch.waitForExistence(timeout: 3) {
            app.menuBars.menuBarItems["檔案"].click()
            app.menuBars.menuItems["新增視窗"].click()
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8), "主視窗沒有出現")
        let entry = app.descendants(matching: .any)["tab.today"].firstMatch
        let hittable = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: entry)
        if XCTWaiter.wait(for: [hittable], timeout: 8) != .completed {
            saveDiagnostics("setUp")
            XCTFail("主要入口不可點擊（視窗可能在螢幕外）：\(windowFrames())")
        }
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 { saveDiagnostics("failure") }
        app.terminate()
    }

    func windowFrames() -> String {
        app.windows.allElementsBoundByIndex.map { "\($0.frame)" }.joined(separator: ", ")
    }

    /// 失敗時保存螢幕截圖、視窗 frame 與無障礙樹（V201-UAT-02）
    func saveDiagnostics(_ tag: String) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bp-ui-diag")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = "\(name)-\(tag)".replacingOccurrences(of: " ", with: "_")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(base).png"))
        let info = "windows=\(windowFrames())\nscreen=\(XCUIScreen.main.screenshot().image.size)\n\n\(app.debugDescription)"
        try? info.write(to: dir.appendingPathComponent("\(base).txt"), atomically: true, encoding: .utf8)
        print("diag=\(dir.path)")
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
            saveDiagnostics("tab-\(ids[title] ?? title)")
            XCTFail("找不到分頁 \(title)；windows=\(windowFrames())")
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

    /// V201-UAT-01：套用前後容量文字的已安排時間一致（同一行動只算一次）
    func testV201UAT01_CapacityNotDoubleCountedAfterApply() {
        createGoalToFinishStep()
        let cap = element("wizard.capacity")
        XCTAssertTrue(cap.waitForExistence(timeout: 5))
        func text(_ e: XCUIElement) -> String { (e.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? e.label }
        let before = text(cap)
        XCTAssertTrue(before.hasPrefix("安排前預估"), before)
        button("wizard.focusAndToday").click()
        let after = element("wizard.capacity")
        XCTAssertTrue(after.waitForExistence(timeout: 5))
        let afterText = text(after)
        XCTAssertTrue(afterText.hasPrefix("今天實際"), afterText)
        func load(_ s: String) -> String { s.components(separatedBy: "已安排 ").last?.components(separatedBy: "／").first ?? s }
        XCTAssertEqual(load(afterText), load(before), "before=\(before) after=\(afterText)")
    }

    func testUAT01_LaterHasNoSideEffects() {
        createGoalToFinishStep()
        button("wizard.later").click()
        let header = element("goals.focusHeader")
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        let text = [header.label, header.value as? String ?? "", header.title].joined(separator: " ")
        XCTAssertTrue(text.contains("0/5") || app.staticTexts["焦點目標 0/5"].exists, "焦點數不是 0：\(text)")
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

    // MARK: V202-DAILY-02／03：做完之後的今天頁與晚間日結

    func testV202DAILY_AllDoneShowsNextStepPromptAndEveningListsDone() {
        createGoalToFinishStep()
        button("wizard.focusAndToday").click()
        button("wizard.done").click()
        openTab("今天")
        button("today.complete").click()
        XCTAssertTrue(element("today.allDone").waitForExistence(timeout: 5), "做完後不應顯示「還沒有安排」")
        XCTAssertTrue(button("today.writeNextStep").exists)
        openTab("回顧")
        button("review.evening").click()
        XCTAssertTrue(element("evening.done.item").waitForExistence(timeout: 5), "晚間日結沒有列出已完成的行動")
    }
}
