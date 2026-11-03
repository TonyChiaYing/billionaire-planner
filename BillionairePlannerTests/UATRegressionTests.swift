import XCTest
import SwiftData
import PlannerCore
@testable import BillionairePlanner

/// v2.0.0.0 UAT 回饋的回歸測試（Application 層）。畫面與可及性另見 BillionairePlannerUITests。
@MainActor
final class UATRegressionTests: XCTestCase {
    var context: ModelContext!
    let now = Date(timeIntervalSince1970: 1_793_775_600)   // 2026-11-04 15:00 台北
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return c
    }()

    override func setUp() async throws {
        context = ModelContext(try PlannerContainer.inMemory())
    }

    func planner(_ minutes: Double = 0) -> Planner {
        var s = PlannerSettings()
        s.dayStartMinute = 7 * 60
        s.dayEndMinute = 22 * 60
        return Planner(context, now: now.addingTimeInterval(minutes * 60), calendar: calendar, settings: s)
    }

    func runningGoal(_ title: String = "[UT] 完成 5 公里路跑") -> Goal {
        let p = planner()
        let g = p.createGoal(title: title, horizon: .medium, outcome: "能在 35 分鐘內完成 5 公里")
        p.addStrategy(g, title: "每週二、四下班後跑步")
        p.addAction(title: "今天快走與慢跑交替 25 分鐘", kind: .personal, goal: g, estimate: 25)
        return g
    }

    // MARK: UAT-01（AC-01、AC-02）

    func testUAT01_FocusAndTodayInOneConfirmation() {
        let p = planner()
        let g = runningGoal()
        let r = p.finishSetup(g, choice: .focusAndToday)
        XCTAssertEqual(r, SetupFinishResult(focus: .focused, plannedToday: true))
        XCTAssertTrue(g.isFocus)
        XCTAssertEqual(p.placements(on: p.today).count, 1)
    }

    func testUAT01_LaterHasNoSideEffects() {
        let p = planner()
        let g = runningGoal()
        XCTAssertEqual(p.finishSetup(g, choice: .later), SetupFinishResult(focus: nil, plannedToday: false))
        XCTAssertFalse(g.isFocus)
        XCTAssertTrue(p.placements(on: p.today).isEmpty)
    }

    func testUAT01_FocusOnlyDoesNotPlan() {
        let p = planner()
        let g = runningGoal()
        XCTAssertEqual(p.finishSetup(g, choice: .focusOnly).plannedToday, false)
        XCTAssertTrue(g.isFocus)
        XCTAssertTrue(p.placements(on: p.today).isEmpty)
    }

    func testUAT01_FocusFullChangesNothingThenTodayOnlyWorks() {
        let p = planner()
        for i in 0..<5 { _ = p.finishSetup(runningGoal("G\(i)"), choice: .focusOnly) }
        let g = runningGoal()
        let before = p.focusGoals.map(\.id)
        XCTAssertEqual(p.finishSetup(g, choice: .focusAndToday), SetupFinishResult(focus: .blocked, plannedToday: false))
        XCTAssertFalse(g.isFocus)
        XCTAssertEqual(p.focusGoals.map(\.id), before)
        XCTAssertTrue(p.placements(on: p.today).isEmpty)
        XCTAssertEqual(p.finishSetup(g, choice: .todayOnly).plannedToday, true)
        XCTAssertFalse(g.isFocus)
    }

    func testUAT01_DraftWithoutActionCannotBeFocused() {
        let p = planner()
        let g = p.createGoal(title: "草稿", horizon: .short, outcome: "x")
        XCTAssertEqual(p.finishSetup(g, choice: .focusAndToday), SetupFinishResult(focus: .needsStrategyAndAction, plannedToday: false))
        XCTAssertFalse(g.isFocus)
    }

    // MARK: UAT-02（AC-04、AC-10）

    func testUAT02_CompletedActionDoesNotBecomeOutcomeByDefault() {
        let p = planner()
        let g = runningGoal()
        let placement = p.plan(p.openActions(for: g.id).first!, on: p.today)
        p.complete(placement)
        let candidates = p.outcomeCandidates(on: p.today)
        XCTAssertEqual(candidates.count, 1)
        // 預設什麼都不勾 → 不產生成果
        let none = p.eveningEvidence(candidates: candidates, confirmed: [:], extraGoalID: nil, extraNote: "")
        p.closeEvening(day: p.today, evidence: none, energy: nil, blockers: "", blockedGoalIDs: [], principle: "",
                       isRestDay: false, note: "")
        XCTAssertTrue(p.evidence(for: g.id).isEmpty)
    }

    func testUAT02_SelectedButEmptyNoteIsNotSavedAndTitleIsNeverUsed() {
        let p = planner()
        let g = runningGoal()
        p.complete(p.plan(p.openActions(for: g.id).first!, on: p.today))
        let c = p.outcomeCandidates(on: p.today)
        XCTAssertTrue(p.eveningEvidence(candidates: c, confirmed: [c[0].id: "   "], extraGoalID: nil, extraNote: "").isEmpty)
        let saved = p.eveningEvidence(candidates: c, confirmed: [c[0].id: "第一次連續慢跑 10 分鐘"], extraGoalID: nil, extraNote: "")
        XCTAssertEqual(saved.map(\.note), ["第一次連續慢跑 10 分鐘"])
        XCTAssertFalse(saved.contains { $0.note == c[0].action.title })
    }

    // MARK: UAT-04

    func testUAT04_StopWithoutRecordingClearsFocusState() {
        let p = planner()
        let g = runningGoal()
        let pl = p.plan(p.openActions(for: g.id).first!, on: p.today)
        p.start(pl)
        XCTAssertTrue(p.isFocusing(pl))
        p.cancelFocus(pl)
        XCTAssertFalse(p.isFocusing(pl))
        XCTAssertNil(pl.startedAt)
        XCTAssertEqual(p.actionMap()[pl.actionID]?.actualMinutes, 0)
        XCTAssertEqual(p.actionMap()[pl.actionID]?.status, .planned)
    }

    func testUAT04_BackgroundContinueKeepsOriginalStartAndUnderOneMinuteRecordsZero() {
        let p = planner()
        let g = runningGoal()
        let pl = p.plan(p.openActions(for: g.id).first!, on: p.today)
        p.start(pl)
        let first = pl.startedAt
        planner(5).start(pl)                       // 背景繼續後再打開，不重設
        XCTAssertEqual(pl.startedAt, first)
        XCTAssertEqual(planner(5).focusElapsedMinutes(pl), 5)
        p.logFocus(pl, minutes: 0, markDone: true) // 不足 1 分：記 0
        XCTAssertEqual(p.actionMap()[pl.actionID]?.actualMinutes, 0)
        XCTAssertNil(pl.startedAt)
        XCTAssertTrue(pl.isDone)
    }

    // MARK: UAT-05（AC-06）

    func testUAT05_LowLoadWithoutRestIsComfortableButFlagsRest() {
        let p = planner()
        let g = runningGoal()
        p.plan(p.openActions(for: g.id).first!, on: p.today)
        let c = p.capacity(for: p.today)
        XCTAssertEqual(c.state, .comfortable)
        XCTAssertTrue(c.missingRest)
        _ = p.createDefaultTemplate()
        p.applyTemplate(p.activeTemplate!, to: p.today)
        XCTAssertFalse(p.capacity(for: p.today).missingRest)
    }
}
