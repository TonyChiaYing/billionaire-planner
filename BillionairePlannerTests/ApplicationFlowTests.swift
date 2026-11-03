import XCTest
import SwiftData
import PlannerCore
@testable import BillionairePlanner

/// 以固定時鐘＋記憶體資料驗證主要流程（不需要畫面）
@MainActor
final class ApplicationFlowTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return c
    }()
    // 2026-11-04（週三）15:00 台北
    let now = Date(timeIntervalSince1970: 1_793_775_600)

    override func setUp() async throws {
        container = try PlannerContainer.inMemory()
        context = ModelContext(container)
        UndoCenter.shared.clear()
    }

    func planner(_ offsetMinutes: Double = 0) -> Planner {
        var s = PlannerSettings()
        s.dayStartMinute = 7 * 60
        s.dayEndMinute = 22 * 60
        return Planner(context, now: now.addingTimeInterval(offsetMinutes * 60), calendar: calendar, settings: s)
    }

    func readyGoal(_ title: String = "讀完 12 本書") -> Goal {
        let p = planner()
        let g = p.createGoal(title: title, horizon: .long, outcome: "書架上多 12 本讀完的書")
        p.addStrategy(g, title: "每天睡前讀 20 分")
        p.addAction(title: "讀 20 頁", kind: .personal, goal: g, estimate: 25)
        return g
    }

    /// AC-01
    func testProgressiveGoalBecomesExecutable() {
        let p = planner()
        let g = p.createGoal(title: "學西班牙文", horizon: .medium, outcome: "能點餐")
        XCTAssertEqual(g.status, .draft)
        XCTAssertEqual(p.requestFocus(g), .needsStrategyAndAction)
        p.addStrategy(g, title: "Duolingo")
        p.addAction(title: "一課", kind: .personal, goal: g, estimate: 15)
        XCTAssertEqual(g.status, .active)
        XCTAssertEqual(p.requestFocus(g), .focused)
        XCTAssertNotNil(p.tomorrowDraft(from: p.today).included.first { $0.candidate.title == "一課" })
    }

    /// AC-02
    func testSixthFocusBlockedWithoutTouchingOthers() {
        let p = planner()
        let goals = (0..<6).map { readyGoal("G\($0)") }
        for g in goals.prefix(3) { XCTAssertEqual(p.requestFocus(g), .focused) }
        XCTAssertEqual(p.requestFocus(goals[3]), .focusedAboveRecommended(count: 4))
        _ = p.requestFocus(goals[4])
        let before = goals.map { ($0.title, $0.status, $0.isFocus) }
        XCTAssertEqual(p.requestFocus(goals[5]), .blocked)
        XCTAssertFalse(goals[5].isFocus)
        XCTAssertEqual(goals.prefix(5).map(\.isFocus), [true, true, true, true, true])
        XCTAssertEqual(goals.map(\.title), before.map { $0.0 })
        p.replaceFocus(goals[0], with: goals[5])
        XCTAssertTrue(goals[5].isFocus)
        XCTAssertFalse(goals[0].isFocus)
        XCTAssertEqual(goals[0].status, .active)   // 被替換的不被改動狀態
    }

    /// AC-03
    func testSwitchStrategyPreservesHistory() {
        let p = planner()
        let g = readyGoal()
        let a = p.strategies(for: g.id).first!
        let done = p.openActions(for: g.id).first!
        let placement = p.plan(done, on: p.today)
        p.complete(placement)
        p.recordEvidence(g, kind: .numeric, value: 1, note: "讀完第一本")
        let b = p.switchStrategy(g, toTitle: "通勤聽書", reason: "睡前太累")
        XCTAssertEqual(a.status, .retired)
        XCTAssertEqual(b.status, .active)
        XCTAssertEqual(done.strategyID, a.id)                          // 歷史行動仍指向 A
        XCTAssertEqual(p.evidence(for: g.id).first?.strategyID, a.id)
        XCTAssertEqual(p.evidence(for: g.id).count, 1)                 // 進度不歸零
    }

    /// AC-05
    func testTemplateOverrideOnlyAffectsToday() {
        let p = planner()
        let t = p.createDefaultTemplate()
        t.weekdays = [1, 2, 3, 4, 5, 6, 7]
        p.ensureDayPrepared(p.today)
        let block = p.dayBlocks(on: p.today).first { $0.kind == .work }!
        let item = p.templateItems(t).first { $0.id == block.sourceTemplateItemID }!
        let originalStart = item.startMinute
        p.editDayBlock(block, title: "改到下午開會", kind: .work, start: 14 * 60, duration: 60)
        XCTAssertEqual(item.startMinute, originalStart)
        let tomorrow = p.today.adding(days: 1, calendar: calendar)
        p.ensureDayPrepared(tomorrow)
        XCTAssertTrue(p.dayBlocks(on: tomorrow).contains { $0.startMinute == originalStart && $0.kind == .work })
        p.pushBlockToTemplate(block)                                    // 明確選擇才更新模板
        XCTAssertEqual(item.startMinute, 14 * 60)
    }

    /// AC-08
    func testUrgentInsertPreviewApplyUndo() {
        let p = planner()
        let g = readyGoal()
        let a1 = p.openActions(for: g.id).first!
        let flex = p.plan(a1, on: p.today, startMinute: 16 * 60, duration: 60)
        let doneAction = p.addAction(title: "已完成的", kind: .work, goal: nil, estimate: 30)
        let done = p.plan(doneAction, on: p.today, startMinute: 16 * 60 + 30, duration: 30)
        p.complete(done)
        let lockedAction = p.addAction(title: "鎖定的", kind: .personal, goal: nil, estimate: 30)
        let locked = p.plan(lockedAction, on: p.today, startMinute: 20 * 60, duration: 30, commitment: .locked)

        let preview = p.replanPreview(insertStart: 16 * 60, duration: 60, on: p.today)
        XCTAssertEqual(preview.changes.map(\.slotID), [flex.id])
        XCTAssertTrue(preview.immovableConflicts.contains(done.id))
        let expected = preview.changes[0].selectedOption!

        p.quickInsert(title: "客戶急件", kind: .work, urgency: 2, estimate: 60, startMinute: 16 * 60, preview: preview, on: p.today)
        XCTAssertEqual(flex.startMinute, expected.newStart)            // 預覽 = 實際
        XCTAssertEqual(done.startMinute, 16 * 60 + 30)
        XCTAssertEqual(locked.startMinute, 20 * 60)
        XCTAssertEqual(p.placements(on: p.today).count, 4)

        p.undoLast()
        XCTAssertEqual(flex.startMinute, 16 * 60)
        XCTAssertEqual(p.placements(on: p.today).count, 3)
        XCTAssertFalse(context.all(ActionItem.self).contains { $0.title == "客戶急件" })
    }

    /// AC-09
    func testMissedNeedsDispositionNotFailure() {
        let p = planner()
        let g = readyGoal()
        let a = p.openActions(for: g.id).first!
        let placement = p.plan(a, on: p.today, startMinute: 14 * 60, duration: 30)
        p.recordEvidence(g, kind: .note, value: nil, note: "既有成果")
        XCTAssertTrue(p.needsDisposition(placement))
        p.dispose(placement, .tomorrow)
        XCTAssertEqual(a.carryoverCount, 1)
        XCTAssertEqual(p.placements(on: p.today.adding(days: 1, calendar: calendar)).count, 1)
        XCTAssertNotEqual(g.status, .completed)
        XCTAssertEqual(g.status, .active)
        XCTAssertEqual(p.evidence(for: g.id).count, 1)                 // 成果不被扣除
    }

    /// AC-06（Application 層）：過載只提出方案，不自動改
    func testOverloadOffersProposalsAndAppliesOnlyChosen() {
        let p = planner()
        for i in 0..<6 {
            let a = p.addAction(title: "工作 \(i)", kind: .work, goal: nil, estimate: 150)
            p.plan(a, on: p.today, duration: 150)
        }
        let c = p.capacity(for: p.today)
        XCTAssertEqual(c.state, .overloaded)
        let proposals = OverloadAdvisor.proposals(for: p.capacityInput(for: p.today), assessment: c)
        XCTAssertGreaterThanOrEqual(proposals.count, 2)
        XCTAssertEqual(p.placements(on: p.today).filter(\.isActiveToday).count, 6)
        p.apply(proposals.first { $0.kind == .moveToTomorrow }!, on: p.today)
        XCTAssertLessThan(p.placements(on: p.today).filter(\.isActiveToday).count, 6)
        p.undoLast()
        XCTAssertEqual(p.placements(on: p.today).filter(\.isActiveToday).count, 6)
    }

    /// AC-10
    func testWorkCloseGivesEveryItemADestination() {
        let p = planner()
        let w1 = p.addAction(title: "報表", kind: .work, goal: nil, estimate: 30)
        let w2 = p.addAction(title: "回信", kind: .work, goal: nil, estimate: 15)
        let p1 = p.plan(w1, on: p.today)
        let p2 = p.plan(w2, on: p.today)
        p.closeWork(day: p.today, choices: [p1.id: .tomorrow, p2.id: .waiting], dates: [:], squeezedNote: "")
        XCTAssertTrue(p.openWorkItems(on: p.today).isEmpty)
        XCTAssertEqual(w2.status, .waiting)
        XCTAssertNotNil(p.existingReview(for: p.today)?.workClosedAt)

        let g = readyGoal()
        let a = p.openActions(for: g.id).first!
        let gp = p.plan(a, on: p.today)
        p.complete(gp)
        XCTAssertEqual(p.outcomeCandidates(on: p.today).count, 1)
        p.closeEvening(day: p.today, evidence: [EveningEvidenceInput(goalID: g.id, kind: .note, value: nil, note: "讀了 20 頁", actionID: a.id)],
                       energy: 3, blockers: "", blockedGoalIDs: [], principle: "", isRestDay: false, note: "")
        XCTAssertEqual(p.evidence(for: g.id).count, 1)
        XCTAssertNotNil(p.existingReview(for: p.today)?.eveningClosedAt)
    }

    /// AC-12 / AC-13
    func testRestartAndDeadlineHistory() {
        let p = planner()
        let g = readyGoal()
        p.recordEvidence(g, kind: .numeric, value: 3, note: "")
        let d1 = calendar.date(byAdding: .month, value: 1, to: now)!
        let d2 = calendar.date(byAdding: .month, value: 2, to: now)!
        p.changeDeadline(g, to: d1, reason: "")
        p.changeDeadline(g, to: d2, reason: "加班")
        let h = p.deadlineHistory(for: g.id)
        XCTAssertEqual(h.map(\.newDeadline), [d1, d2])
        XCTAssertEqual(h[1].oldDeadline, d1)
        XCTAssertEqual(h[1].reason, "加班")

        let e = RecoveryEpisode(goalID: g.id, cycleNumber: 1, signals: [])
        context.insert(e)
        p.restartCycle(g, reason: "重新開始", episode: e)
        p.restartCycle(g, reason: "重複按", episode: e)                  // 不會產生第二個週期
        XCTAssertEqual(g.cycleNumber, 2)
        p.recordEvidence(g, kind: .numeric, value: 1, note: "")
        g.outcomeTarget = 12
        XCTAssertEqual(p.outcomeProgress(g).text, "4 / 12 ")
        XCTAssertEqual(p.outcomeProgress(g, cycleOnly: true).text, "1 / 12 ")
    }

    /// AC-11（Application 層）：單次延後不建立恢復介入
    func testSingleDeferralDoesNotOpenRecovery() {
        let p = planner()
        let g = readyGoal()
        g.cycleStartedAt = now.addingTimeInterval(-30 * 86_400)
        let a = p.openActions(for: g.id).first!
        p.dispose(p.plan(a, on: p.today), .tomorrow)
        p.evaluateRecoveryPrompts()
        XCTAssertNil(p.openEpisode(for: g))
    }

    /// AC-14（Application 層）：同日不重複
    func testRecoveryPromptNotRepeatedSameDay() {
        let p = planner()
        let g = readyGoal()
        g.cycleStartedAt = now.addingTimeInterval(-30 * 86_400)
        let a = p.openActions(for: g.id).first!
        for i in 0..<3 {
            let pl = p.plan(a, on: p.today.adding(days: -i, calendar: calendar))
            p.dispose(pl, .later)
        }
        let review = p.review(for: p.today)
        review.eveningClosedAt = now
        review.blockedGoalIDs = [g.id]
        let y = p.review(for: p.today.adding(days: -1, calendar: calendar))
        y.eveningClosedAt = now.addingTimeInterval(-86_400)
        y.blockedGoalIDs = [g.id]
        p.evaluateRecoveryPrompts()
        let e = try! XCTUnwrap(p.openEpisode(for: g))
        XCTAssertGreaterThanOrEqual(Set(e.signals.map(\.kind)).count, 2)
        p.dismiss(e)
        p.evaluateRecoveryPrompts()
        XCTAssertNil(p.openEpisode(for: g))
    }

    /// AC-07（Application 層）
    func testEstimateSuggestionFromHistory() {
        let p = planner()
        let g = readyGoal()
        XCTAssertNil(p.estimateSuggestion(title: "讀 20 頁", goalID: g.id, kind: .personal, userEstimate: nil))
        for m in [20, 25, 30] {
            let a = p.addAction(title: "讀 20 頁", kind: .personal, goal: g, estimate: nil)
            a.status = .done
            a.actualMinutes = m
            a.completedAt = now
        }
        XCTAssertEqual(p.estimateSuggestion(title: "讀 20 頁", goalID: g.id, kind: .personal, userEstimate: nil)?.minutes, 25)
        XCTAssertNil(p.estimateSuggestion(title: "讀 20 頁", goalID: g.id, kind: .personal, userEstimate: 40))
    }

    /// AC-16：匯出不需網路、包含主要實體
    func testExportContainsData() throws {
        _ = readyGoal()
        let json = try JSONSerialization.jsonObject(with: DataExporter.json(context)) as? [String: Any]
        XCTAssertEqual((json?["goals"] as? [Any])?.count, 1)
        XCTAssertEqual((json?["strategies"] as? [Any])?.count, 1)
    }
}
