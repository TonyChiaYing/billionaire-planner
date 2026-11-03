import XCTest
@testable import PlannerCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }

final class EstimateSuggestionTests: XCTestCase {
    let goal = UUID()
    func sample(_ m: Int, title: String = "讀書 30 頁", cancelled: Bool = false, inferred: Bool = false) -> EstimateSample {
        EstimateSample(title: title, goalID: goal, context: .personal, actualMinutes: m, completedAt: daysAgo(1),
                       wasCancelled: cancelled, isInferred: inferred)
    }

    func testFewerThanThreeSamplesNoSuggestion() {
        XCTAssertNil(EstimateSuggester.suggest(title: "讀書", goalID: goal, context: .personal, userEstimate: nil,
                                               history: [sample(30), sample(40)]))
    }

    func testMedianResistsOutlierAndExplainsBasis() {
        let s = EstimateSuggester.suggest(title: "讀書", goalID: goal, context: .personal, userEstimate: nil,
                                          history: [sample(30), sample(35), sample(32), sample(400)])
        XCTAssertEqual(s?.minutes, 35)
        XCTAssertEqual(s?.sampleCount, 4)
        XCTAssertTrue(s?.basis.contains("4 筆") ?? false)
        XCTAssertTrue(s?.basis.contains("30–400") ?? false)
    }

    func testUserEstimateNeverOverwritten() {
        XCTAssertNil(EstimateSuggester.suggest(title: "讀書", goalID: goal, context: .personal, userEstimate: 20,
                                               history: [sample(30), sample(30), sample(30)]))
    }

    func testCancelledAndInferredExcluded() {
        XCTAssertNil(EstimateSuggester.suggest(title: "讀書", goalID: goal, context: .personal, userEstimate: nil,
                                               history: [sample(30), sample(30), sample(30, cancelled: true), sample(30, inferred: true)]))
    }

    func testSimilarTitlesWithoutGoalMatch() {
        let h = ["寫週報", "寫週報初稿", "寫週報與整理"].map {
            EstimateSample(title: $0, goalID: nil, context: .work, actualMinutes: 20, completedAt: daysAgo(2))
        }
        XCTAssertEqual(EstimateSuggester.suggest(title: "寫週報", goalID: nil, context: .work, userEstimate: nil, history: h)?.minutes, 20)
    }
}

final class LagDetectionTests: XCTestCase {
    func input(_ build: (inout GoalLagInput) -> Void) -> GoalLagInput {
        var i = GoalLagInput(lifecycle: .active, createdAt: daysAgo(60))
        build(&i)
        return i
    }

    /// AC-11：一次延期或一天沒用不會觸發
    func testSingleMissOrIdleDayDoesNotTrigger() {
        let one = input { $0.deferralDates = [daysAgo(1)]; $0.periods = [CommittedPeriod(hadCommitment: true, evidenceCount: 1)] }
        guard case .onTrack = LagDetector.assess(one, now: now) else { return XCTFail() }
        let idle = input { $0.periods = [CommittedPeriod(hadCommitment: false, evidenceCount: 0)] }
        guard case .onTrack = LagDetector.assess(idle, now: now) else { return XCTFail() }
    }

    func testPauseWaitingAndNoDataExcluded() {
        guard case .notApplicable = LagDetector.assess(input { $0.lifecycle = .paused; $0.deferralDates = Array(repeating: daysAgo(1), count: 5) }, now: now) else { return XCTFail() }
        guard case .notApplicable = LagDetector.assess(input { $0.isWaitingOnExternal = true }, now: now) else { return XCTFail() }
        let fresh = GoalLagInput(lifecycle: .active, createdAt: daysAgo(2))
        XCTAssertEqual(LagDetector.assess(fresh, now: now), .insufficientData)
    }

    func testRestPeriodsDoNotCount() {
        let i = input {
            $0.periods = [CommittedPeriod(hadCommitment: true, evidenceCount: 0),
                          CommittedPeriod(hadCommitment: true, evidenceCount: 0, isPlannedRest: true)]
            $0.deferralDates = [daysAgo(1), daysAgo(2), daysAgo(3)]
        }
        guard case .onTrack(let s) = LagDetector.assess(i, now: now) else { return XCTFail() }
        XCTAssertEqual(s.map(\.kind), [.repeatedDeferrals])
    }

    func testTwoIndependentSignalsTriggerWithReadableEvidence() {
        let i = input {
            $0.periods = [CommittedPeriod(hadCommitment: true, evidenceCount: 0), CommittedPeriod(hadCommitment: true, evidenceCount: 0)]
            $0.deferralDates = [daysAgo(1), daysAgo(3), daysAgo(6), daysAgo(20)]
        }
        guard case .mayNeedRecovery(let signals) = LagDetector.assess(i, now: now) else { return XCTFail() }
        XCTAssertEqual(Set(signals.map(\.kind)), [.noEvidenceInCommittedPeriods, .repeatedDeferrals])
        XCTAssertTrue(signals.first { $0.kind == .repeatedDeferrals }!.evidence.contains("3 次"))
        XCTAssertEqual(LagDetector.assess(i, now: now), LagDetector.assess(i, now: now))   // 穩定
    }

    func testUserDeclarationIsEnough() {
        guard case .mayNeedRecovery = LagDetector.assess(input { $0.userDeclaredNeedsRecovery = true }, now: now) else { return XCTFail() }
    }
}

final class RecoveryTests: XCTestCase {
    func testSmallestChangeFirst() {
        XCTAssertEqual(RecoveryPlanner.rankedOptions().first, .shrinkNextStep)
        XCTAssertEqual(RecoveryPlanner.rankedOptions().last, .restartCycle)
        XCTAssertFalse(RecoveryPlanner.rankedOptions(hasDeadlineOrMilestone: false).contains(.moveMilestoneOrDeadline))
    }

    /// AC-12：重新開始只新增週期，累積成果不歸零
    func testRestartPreservesAccumulatedEvidence() {
        let cycle = GoalCycle(number: 1, startedAt: daysAgo(30)).restarted(at: now)
        XCTAssertEqual(cycle.number, 2)
        let points = [EvidencePoint(recordedAt: daysAgo(20), value: 3, cycle: 1),
                      EvidencePoint(recordedAt: daysAgo(10), value: 2, cycle: 1),
                      EvidencePoint(recordedAt: now, value: 1, cycle: 2)]
        let split = CycleViews.split(points, currentCycle: cycle.number)
        XCTAssertEqual(split.cumulativeValue, 6)
        XCTAssertEqual(split.cycleValue, 1)
        XCTAssertEqual(split.cumulativeCount, 3)
    }

    /// AC-13：期限歷史只增不改
    func testDeadlineHistoryAppends() {
        let d1 = daysAgo(-30), d2 = daysAgo(-60)
        var h = DeadlineHistory.appending([], newDeadline: d1, at: daysAgo(10))
        h = DeadlineHistory.appending(h, newDeadline: d2, at: now, reason: "工作量變大")
        XCTAssertEqual(h.count, 2)
        XCTAssertEqual(h[1].oldDeadline, d1)
        XCTAssertEqual(h[1].newDeadline, d2)
        XCTAssertEqual(h[1].reason, "工作量變大")
        XCTAssertEqual(h[0].newDeadline, d1)   // 舊紀錄不被改寫
        XCTAssertEqual(DeadlineHistory.appending(h, newDeadline: d2, at: now).count, 2)   // 同值不重複
    }

    func testDeadlineRisk() {
        XCTAssertEqual(DeadlineRisk.assess(deadline: nil, startedAt: daysAgo(10), progress: 0, now: now), .none)
        XCTAssertEqual(DeadlineRisk.assess(deadline: daysAgo(1), startedAt: daysAgo(10), progress: 0.9, now: now), .high)
        XCTAssertEqual(DeadlineRisk.assess(deadline: daysAgo(-3), startedAt: daysAgo(30), progress: 0.2, now: now), .high)
        XCTAssertEqual(DeadlineRisk.assess(deadline: daysAgo(-50), startedAt: daysAgo(50), progress: 0.1, now: now), .medium)
        XCTAssertEqual(DeadlineRisk.assess(deadline: daysAgo(-50), startedAt: daysAgo(50), progress: 0.5, now: now), .low)
    }
}

final class ReplanTests: XCTestCase {
    let done = PlannedSlot(title: "已完成", start: 540, duration: 30, state: .done)
    let locked = PlannedSlot(title: "鎖定", start: 600, duration: 30, state: .locked)
    let flex = PlannedSlot(title: "彈性", start: 630, duration: 60)
    let later = PlannedSlot(title: "不受影響", start: 900, duration: 60)

    /// AC-08：只動衝突區段；完成、鎖定、不受影響的都不變
    func testOnlyConflictWindowChanges() {
        let slots = [done, locked, flex, later]
        let p = LocalReplanner.preview(slots: slots, insertStart: 540, insertDuration: 150)
        XCTAssertEqual(p.changes.map(\.slotID), [flex.id])
        XCTAssertEqual(Set(p.immovableConflicts), [done.id, locked.id])
        let applied = LocalReplanner.apply(p, to: slots).slots
        XCTAssertEqual(applied.first { $0.id == done.id }, done)
        XCTAssertEqual(applied.first { $0.id == locked.id }, locked)
        XCTAssertEqual(applied.first { $0.id == later.id }, later)
        let moved = applied.first { $0.id == flex.id }!
        XCTAssertGreaterThanOrEqual(moved.start, 690)
        XCTAssertFalse(moved.overlaps(later.start, later.end))
    }

    func testPreviewEqualsCommittedAndUndoRestores() {
        let slots = [flex, later]
        let p = LocalReplanner.preview(slots: slots, insertStart: 640, insertDuration: 30)
        let change = p.changes[0]
        let applied = LocalReplanner.apply(p, to: slots).slots.first { $0.id == flex.id }!
        XCTAssertEqual(applied.start, change.selectedOption?.newStart)
        XCTAssertEqual(applied.duration, change.selectedOption?.newDuration)
        XCTAssertEqual(slots, [flex, later])   // 原計畫（復原來源）未被改動
    }

    func testNoRoomProposesTradeoffNotDeletion() {
        let slots = [PlannedSlot(title: "晚上", start: 1380, duration: 50)]
        var p = LocalReplanner.preview(slots: slots, insertStart: 1380, insertDuration: 60)
        XCTAssertEqual(p.changes[0].selected, .moveToTomorrow)
        let r = LocalReplanner.apply(p, to: slots)
        XCTAssertEqual(r.movedToTomorrow, [slots[0].id])
        p.changes[0].selected = .keep
        XCTAssertEqual(LocalReplanner.apply(p, to: slots).slots, slots)
    }
}

final class InterventionAndFocusTests: XCTestCase {
    let today = LocalDay(year: 2027, month: 1, day: 15)

    /// AC-14：處理或延後後，冷卻期內不重複；風險升級才可再提示
    func testSuppressionAndEscalation() {
        let snoozed = InterventionRecord(key: "g1", level: .deadline, outcome: .snoozed, at: now, severity: 2,
                                         snoozeUntil: now.addingTimeInterval(86_400))
        XCTAssertFalse(InterventionGate.shouldShow(key: "g1", level: .deadline, severity: 2, now: now.addingTimeInterval(3600),
                                                   today: today, history: [snoozed]))
        XCTAssertTrue(InterventionGate.shouldShow(key: "g1", level: .deadline, severity: 3, now: now.addingTimeInterval(3600),
                                                  today: today, history: [snoozed]))
        XCTAssertTrue(InterventionGate.shouldShow(key: "g1", level: .deadline, severity: 2, now: now.addingTimeInterval(2 * 86_400),
                                                  today: today, history: [snoozed]))
        let dismissed = InterventionRecord(key: "w", level: .weekly, outcome: .dismissed, at: now, severity: 1)
        XCTAssertFalse(InterventionGate.shouldShow(key: "w", level: .weekly, severity: 1, now: now.addingTimeInterval(8 * 86_400),
                                                   today: today, history: [dismissed]))
        let handled = InterventionRecord(key: "d", level: .daily, outcome: .handled, at: now, severity: 1, planningDay: today)
        XCTAssertFalse(InterventionGate.shouldShow(key: "d", level: .daily, severity: 1, now: now, today: today, history: [handled]))
        XCTAssertTrue(InterventionGate.shouldShow(key: "d", level: .daily, severity: 1, now: now,
                                                  today: today.adding(days: 1, calendar: Calendar(identifier: .gregorian)), history: [handled]))
        XCTAssertTrue(InterventionGate.shouldShow(key: "new", level: .daily, severity: 1, now: now, today: today, history: [handled]))
    }

    /// AC-02
    func testFocusLimit() {
        XCTAssertEqual(FocusPolicy.check(currentFocusCount: 2), .allowed)
        XCTAssertEqual(FocusPolicy.check(currentFocusCount: 3), .allowedAboveRecommended(count: 4))
        XCTAssertEqual(FocusPolicy.check(currentFocusCount: 5), .blocked)
        XCTAssertFalse(FocusPolicy.isExecutable(hasActiveStrategy: true, openActionCount: 0))
        XCTAssertTrue(FocusPolicy.isExecutable(hasActiveStrategy: true, openActionCount: 1))
    }

    /// AC-09：錯過＝需要處置，不是失敗
    func testMissedNeedsDisposition() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let day = LocalDay(now, calendar: cal)
        let nowMinute = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        XCTAssertTrue(MissedDetector.needsDisposition(day: day, startMinute: nowMinute - 30, durationMinutes: 15, isDone: false,
                                                      isStarted: false, isDisposed: false, now: now, calendar: cal))
        XCTAssertFalse(MissedDetector.needsDisposition(day: day, startMinute: nowMinute - 30, durationMinutes: 15, isDone: true,
                                                       isStarted: false, isDisposed: false, now: now, calendar: cal))
        XCTAssertFalse(MissedDetector.needsDisposition(day: day, startMinute: nil, durationMinutes: nil, isDone: false,
                                                       isStarted: false, isDisposed: false, now: now, calendar: cal))
        XCTAssertTrue(MissedDetector.needsDisposition(day: day.adding(days: -1, calendar: cal), startMinute: nil, durationMinutes: nil,
                                                      isDone: false, isStarted: false, isDisposed: false, now: now, calendar: cal))
        XCTAssertEqual(Disposition.allCases.count, 6)
    }

    func testGoalOrdering() {
        let a = GoalRankInput(id: UUID(), hasPlacementToday: false, risk: .high, userRank: 0, lastActivity: nil)
        let b = GoalRankInput(id: UUID(), hasPlacementToday: true, risk: .none, userRank: 2, lastActivity: nil)
        let c = GoalRankInput(id: UUID(), hasPlacementToday: false, risk: .high, userRank: 1, lastActivity: now)
        XCTAssertEqual(GoalOrdering.sort([a, b, c]), [b.id, a.id, c.id])
    }

    /// AC-04：成果與行動是兩種指標
    func testDualProgressSeparate() {
        let o = OutcomeProgress.compute(target: 12, unit: "本", numericValues: [3, 2], milestonesDone: 0, milestonesTotal: 0, evidenceCount: 2)
        XCTAssertEqual(o.fraction!, 5.0 / 12.0, accuracy: 0.001)
        XCTAssertEqual(o.text, "5 / 12 本")
        XCTAssertNil(OutcomeProgress.compute(target: nil, unit: "", numericValues: [], milestonesDone: 0, milestonesTotal: 0, evidenceCount: 4).fraction)
        let t = ActionTrend.compute(completions: [(daysAgo(1), 30), (daysAgo(10), 20), (daysAgo(40), 10)], plannedLast7: 3, now: now)
        XCTAssertEqual(t.done7, 1)
        XCTAssertEqual(t.done30, 2)
        XCTAssertEqual(t.minutes30, 50)
    }

    func testLocalDayAcrossDST() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let before = LocalDay(year: 2026, month: 3, day: 7)
        XCTAssertEqual(before.adding(days: 1, calendar: cal), LocalDay(year: 2026, month: 3, day: 8))
        XCTAssertEqual(before.adding(days: 2, calendar: cal), LocalDay(year: 2026, month: 3, day: 9))
        XCTAssertEqual(LocalDay("2026-03-08"), LocalDay(year: 2026, month: 3, day: 8))
        XCTAssertNil(LocalDay("2026-13-01"))
        XCTAssertEqual(LocalDay(year: 2026, month: 3, day: 8).description, "2026-03-08")
    }
}
