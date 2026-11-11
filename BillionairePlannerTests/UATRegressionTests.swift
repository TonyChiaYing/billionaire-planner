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

    // MARK: V201-UAT-01：建立完成畫面的容量只算一次

    func testV201UAT01_PreApplyEstimateEqualsPostApplyActual() {
        let p = planner()
        let other = p.createGoal(title: "[UT] 其他", horizon: .short, outcome: "x")
        _ = p.addStrategy(other, title: "s")
        p.plan(p.addAction(title: "既有行動", kind: .personal, goal: other, estimate: 80), on: p.today)
        let g = runningGoal()
        let before = p.setupCapacity(for: g)
        XCTAssertTrue(before.isEstimate)
        XCTAssertEqual(before.assessment.loadMinutes, p.capacity(for: p.today).loadMinutes + 25)
        XCTAssertTrue(p.finishSetup(g, choice: .focusAndToday).plannedToday)
        let after = p.setupCapacity(for: g)
        XCTAssertFalse(after.isEstimate)
        XCTAssertEqual(after.assessment.loadMinutes, before.assessment.loadMinutes, "25 分鐘行動被重複計算")
        XCTAssertEqual(after.assessment.loadMinutes, p.capacity(for: p.today).loadMinutes)
    }

    func testV201UAT01_OtherBranchesDoNotChangeActualCapacity() {
        for choice in [SetupFinishChoice.focusOnly, .later] {
            let p = planner()
            let g = runningGoal("[UT] \(choice)")
            let actual = p.capacity(for: p.today).loadMinutes
            _ = p.finishSetup(g, choice: choice)
            XCTAssertEqual(p.capacity(for: p.today).loadMinutes, actual)
            XCTAssertTrue(p.setupCapacity(for: g).isEstimate)
        }
    }

    // MARK: V201-UAT-03：缺漏提示只描述真正缺少的部分

    func testV201UAT03_MissingSetupLabels() {
        let p = planner()
        let both = p.createGoal(title: "[UT] 空", horizon: .short, outcome: "x")
        XCTAssertEqual(p.missingSetup(both).label, "需要策略與下一步")
        let strategyOnly = p.createGoal(title: "[UT] 有策略", horizon: .short, outcome: "x")
        _ = p.addStrategy(strategyOnly, title: "s")
        XCTAssertEqual(p.missingSetup(strategyOnly).label, "需要下一步")
        let actionOnly = p.createGoal(title: "[UT] 有行動", horizon: .short, outcome: "x")
        _ = p.addAction(title: "a", kind: .personal, goal: actionOnly, estimate: 10)
        XCTAssertEqual(p.missingSetup(actionOnly).label, "需要策略")
        XCTAssertNil(p.missingSetup(runningGoal()).label)
    }

    func testV201UAT03_CompletedActionLeavesOnlyActionMissing() {
        let p = planner()
        let g = runningGoal()
        p.plan(p.openActions(for: g.id).first!, on: p.today)
        p.complete(p.placements(on: p.today).first!)
        XCTAssertEqual(p.missingSetup(g), .action)
    }

    // MARK: V202-DAILY：日常使用順暢度

    /// 昨天排了沒做的行動 → 今天出現在「需要處置」，不會消失
    func overdueSetup() -> (Planner, Goal, PlanPlacement) {
        let p = planner()
        let g = runningGoal()
        let pl = p.plan(p.openActions(for: g.id).first!, on: p.today.adding(days: -1, calendar: calendar))
        return (p, g, pl)
    }

    func testV202DAILY01_YesterdaysUnfinishedShowsAsOverdue() {
        let (p, _, pl) = overdueSetup()
        XCTAssertEqual(p.overduePlacements().map(\.id), [pl.id])
        XCTAssertEqual(p.capacity(for: p.today).loadMinutes, 0, "不自動排進今天")
    }

    func testV202DAILY01_OverdueTomorrowMeansTodayPlusOne() {
        let (p, _, pl) = overdueSetup()
        p.dispose(pl, .tomorrow)
        XCTAssertEqual(pl.disposition, .tomorrow)
        XCTAssertTrue(p.placements(on: p.today).isEmpty)
        XCTAssertEqual(p.placements(on: p.today.adding(days: 1, calendar: calendar)).count, 1)
        XCTAssertTrue(p.overduePlacements().isEmpty)
    }

    func testV202DAILY01_OverdueLaterLandsOnToday() {
        let (p, _, pl) = overdueSetup()
        p.dispose(pl, .later)
        XCTAssertEqual(pl.disposition, .later)
        XCTAssertEqual(p.placements(on: p.today).count, 1)
        XCTAssertTrue(p.overduePlacements().isEmpty)
    }

    func testV202DAILY01_OverdueStartNowReusesTodaysPlacement() {
        let (q, _, pl) = overdueSetup()
        q.plan(q.actionMap()[pl.actionID]!, on: q.today)   // 今天已經有同一個行動
        q.dispose(pl, .startNow)
        let today = q.placements(on: q.today).filter { $0.actionID == pl.actionID }
        XCTAssertEqual(today.count, 1, "不重複安排")
        XCTAssertNotNil(today.first?.startedAt)
        XCTAssertEqual(pl.disposition, .startNow)
    }

    func testV202DAILY01_OverdueCancelAndNotNeededStayOnOriginalDay() {
        let (p, _, pl) = overdueSetup()
        p.dispose(pl, .cancelToday)
        XCTAssertEqual(pl.disposition, .cancelToday)
        XCTAssertTrue(p.placements(on: p.today).isEmpty)
        XCTAssertTrue(p.overduePlacements().isEmpty)
    }

    func testV202DAILY01_DraftCarriesOverdueOnceWithGoalName() {
        let (p, g, _) = overdueSetup()
        g.isFocus = true
        let draft = p.tomorrowDraft(from: p.today)
        let titles = draft.included.map(\.candidate.title)
        XCTAssertEqual(titles.filter { $0 == "今天快走與慢跑交替 25 分鐘" }.count, 1, "同一行動只出現一次：\(titles)")
        XCTAssertEqual(draft.included.first?.candidate.goalTitle, g.title)
    }

    func testV202DAILY02_CompletedLastActionPromptsNextStep() {
        let p = planner()
        let g = runningGoal()
        p.plan(p.openActions(for: g.id).first!, on: p.today)
        XCTAssertTrue(p.goalsNeedingNextStep(after: p.today).isEmpty)
        p.complete(p.placements(on: p.today).first!)
        XCTAssertEqual(p.goalsNeedingNextStep(after: p.today).map(\.id), [g.id])
        p.addAction(title: "下一次 30 分鐘", kind: .personal, goal: g, estimate: 30)
        XCTAssertTrue(p.goalsNeedingNextStep(after: p.today).isEmpty)
    }

    // MARK: V203-REVIEW：重開回顧不重複記錄

    func testV203REVIEW01_ReclosingEveningDoesNotDuplicateOutcome() {
        let p = planner()
        let g = runningGoal()
        p.complete(p.plan(p.openActions(for: g.id).first!, on: p.today))
        let c = p.outcomeCandidates(on: p.today)
        let ev = p.eveningEvidence(candidates: c, confirmed: [c[0].id: "第一次連續慢跑 10 分鐘"], extraGoalID: nil, extraNote: "")
        p.closeEvening(day: p.today, evidence: ev, energy: 4, blockers: "", blockedGoalIDs: [], principle: "", isRestDay: false, note: "n")
        XCTAssertEqual(p.recordedOutcome(for: c[0].action.id)?.note, "第一次連續慢跑 10 分鐘")
        // 再按一次完成（同樣的輸入）
        p.closeEvening(day: p.today, evidence: ev, energy: 4, blockers: "", blockedGoalIDs: [], principle: "", isRestDay: false, note: "n")
        XCTAssertEqual(p.evidence(for: g.id).count, 1)
        XCTAssertEqual(p.existingReview(for: p.today)?.energy, 4)
    }

    func testV203REVIEW02_RecompletingWeeklyUpdatesSingleDecision() {
        let p = planner()
        let g = runningGoal()
        g.isFocus = true
        let s = p.activeStrategy(for: g.id)!
        let w = p.weeklyReview(for: p.weekStart)
        p.completeWeekly(w, decisions: [(g, s, "continue", "")], capacityNote: "", note: "")
        p.completeWeekly(w, decisions: [(g, s, "tweak", "週四太累")], capacityNote: "出差", note: "")
        let all = p.context.all(StrategyDecision.self).filter { $0.goalID == g.id }
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(p.weeklyDecision(w, goalID: g.id)?.decision, "tweak")
        XCTAssertEqual(p.weeklyDecision(w, goalID: g.id)?.reason, "週四太累")
        XCTAssertEqual(w.nextWeekCapacityNote, "出差")
    }

    // MARK: V204：版面縮放與使用教學

    func testV204ZOOM_StepsClampAndLabels() {
        XCTAssertEqual(UIZoom.clamp(1.0), 1.0)
        XCTAssertEqual(UIZoom.clamp(3.0), 1.5)
        XCTAssertEqual(UIZoom.clamp(0.1), 0.8)
        XCTAssertEqual(UIZoom.clamp(1.04), 1.0)
        XCTAssertEqual(UIZoom.zoomIn(1.0), 1.1)
        XCTAssertEqual(UIZoom.zoomOut(1.0), 0.9)
        XCTAssertEqual(UIZoom.zoomIn(1.5), 1.5, "最大值不再放大")
        XCTAssertEqual(UIZoom.zoomOut(0.8), 0.8, "最小值不再縮小")
        XCTAssertEqual(UIZoom.label(1.2), "120%")
        var z = 1.0
        for _ in 0..<10 { z = UIZoom.zoomIn(z) }
        XCTAssertEqual(z, 1.5)
    }

    func testV204TUTORIAL_PagesCoverCoreFlowWithExamples() {
        let pages = Tutorial.pages
        XCTAssertEqual(pages.map(\.id), Array(0..<pages.count))
        XCTAssertTrue(pages.allSatisfy { !$0.title.isEmpty && !$0.example.isEmpty && !$0.steps.isEmpty })
        let tabs = Set(pages.compactMap(\.tab))
        XCTAssertEqual(tabs, Set(AppTab.allCases), "每個分頁都要有教學")
        XCTAssertTrue(Tutorial.exampleGoal.hasPrefix("[範例]"), "範例資料要一眼看得出是範例")
    }
}
