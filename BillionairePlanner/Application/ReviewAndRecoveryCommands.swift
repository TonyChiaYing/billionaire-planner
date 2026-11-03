import Foundation
import SwiftData
import PlannerCore

/// 下班整理：每個未完成工作都要有去向（AC-10）
enum WorkCloseChoice: String, CaseIterable, Identifiable {
    case done, tomorrow, waiting, notNeeded, laterDate
    var id: String { rawValue }
    var label: String {
        switch self {
        case .done: "其實完成了"
        case .tomorrow: "延續到明天"
        case .waiting: "委派／等待中"
        case .notNeeded: "不再需要"
        case .laterDate: "另定日期"
        }
    }
}

struct OutcomeCandidate: Identifiable {
    let placement: PlanPlacement
    let action: ActionItem
    let goal: Goal
    var id: UUID { placement.id }
}

struct DeadlinePrompt: Identifiable {
    let goal: Goal
    let risk: DeadlineRisk
    var id: UUID { goal.id }
}

struct EveningEvidenceInput {
    var goalID: UUID
    var kind: EvidenceKind
    var value: Double?
    var note: String
    var actionID: UUID?
}

extension Planner {
    // MARK: - 下班整理（1–2 分鐘）

    func openWorkItems(on day: LocalDay) -> [PlanPlacement] {
        let actions = actionMap()
        return placements(on: day).filter { p in
            !p.isDone && p.isActiveToday && actions[p.actionID]?.kind == .work
        }
    }

    func closeWork(day: LocalDay, choices: [UUID: WorkCloseChoice], dates: [UUID: Date], squeezedNote: String) {
        let ps = placements(on: day)
        for (id, choice) in choices {
            guard let p = ps.first(where: { $0.id == id }) else { continue }
            switch choice {
            case .done: complete(p)
            case .tomorrow: carry(p, to: day.adding(days: 1, calendar: calendar))
            case .waiting:
                p.disposition = .cancelToday
                p.dispositionAt = now
                if let a = actionMap()[p.actionID] { a.status = .waiting }
            case .notNeeded: dispose(p, .notNeeded)
            case .laterDate:
                let target = LocalDay(dates[id] ?? now.addingTimeInterval(86_400 * 2), calendar: calendar)
                carry(p, to: target)
            }
        }
        let r = review(for: day)
        r.workClosedAt = now
        r.squeezedNote = squeezedNote.trimmed
        save()
    }

    // MARK: - 晚間日結（2–4 分鐘）

    /// 已完成的個人目標行動 → 成果候選（需使用者確認）
    func outcomeCandidates(on day: LocalDay) -> [OutcomeCandidate] {
        let actions = actionMap()
        return placements(on: day).compactMap { p -> OutcomeCandidate? in
            guard p.isDone, let a = actions[p.actionID], let g = goal(a.goalID) else { return nil }
            return OutcomeCandidate(placement: p, action: a, goal: g)
        }
    }

    func closeEvening(day: LocalDay, evidence: [EveningEvidenceInput], energy: Int?, blockers: String,
                      blockedGoalIDs: [UUID], principle: String, isRestDay: Bool, note: String) {
        for e in evidence {
            guard let g = goal(e.goalID) else { continue }
            recordEvidence(g, kind: e.kind, value: e.value, note: e.note, actionID: e.actionID)
        }
        if !principle.trimmed.isEmpty {
            let p = Principle(text: principle.trimmed)
            p.createdAt = now
            p.goalID = blockedGoalIDs.first
            context.insert(p)
        }
        let r = review(for: day)
        r.energy = energy
        r.blockers = blockers.trimmed
        r.blockedGoalIDs = blockedGoalIDs
        r.isRestDay = isRestDay
        r.note = note.trimmed
        r.eveningClosedAt = now
        r.draftGeneratedAt = now
        save()
    }

    // MARK: - 每週回顧

    var weekStart: LocalDay {
        // 以週一為一週開始
        let wd = today.weekday(in: calendar)   // 1=日
        let offset = (wd + 5) % 7
        return today.adding(days: -offset, calendar: calendar)
    }

    func weeklyReview(for start: LocalDay) -> WeeklyReview {
        if let w = context.all(WeeklyReview.self).first(where: { $0.weekStartKey == start.description }) { return w }
        let w = WeeklyReview(weekStart: start)
        context.insert(w)
        return w
    }

    func deferralCount(_ goal: Goal, days: Int) -> Int {
        let ids = Set(actions(for: goal.id).map(\.id))
        let from = now.addingTimeInterval(-Double(days) * 86_400)
        return context.all(PlanPlacement.self).filter {
            ids.contains($0.actionID) && ($0.disposition?.countsAsDeferral ?? false) && ($0.dispositionAt ?? .distantPast) >= from
        }.count
    }

    func completeWeekly(_ w: WeeklyReview, decisions: [(goal: Goal, strategy: Strategy, decision: String, reason: String)],
                        capacityNote: String, note: String) {
        for d in decisions {
            let rec = StrategyDecision(goalID: d.goal.id, strategyID: d.strategy.id, decision: d.decision, reason: d.reason.trimmed)
            rec.decidedAt = now
            rec.weeklyReviewID = w.id
            context.insert(rec)
            switch d.decision {
            case "pause": setStrategy(d.strategy, status: .paused, reason: d.reason)
            default: break   // tweak / replace 由使用者在目標頁完成
            }
        }
        w.nextWeekCapacityNote = capacityNote.trimmed
        w.note = note.trimmed
        w.completedAt = now
        logIntervention(key: "weekly", level: .weekly, outcome: .handled, severity: 1)
        save()
    }

    // MARK: - 落後訊號（AC-11）

    func lagInput(_ goal: Goal) -> GoalLagInput {
        let ids = Set(actions(for: goal.id).map(\.id))
        let ps = context.all(PlanPlacement.self).filter { ids.contains($0.actionID) }
        let ev = evidence(for: goal.id)
        let reviews = context.all(DailyReview.self)

        // 最近 4 個 7 天週期（舊 → 新）
        var periods: [CommittedPeriod] = []
        for w in (0..<4).reversed() {
            let end = today.adding(days: -7 * w, calendar: calendar)
            let start = end.adding(days: -6, calendar: calendar)
            let committed = ps.contains { $0.day >= start && $0.day <= end }
            let startDate = start.start(in: calendar), endDate = end.adding(days: 1, calendar: calendar).start(in: calendar)
            let count = ev.filter { $0.recordedAt >= startDate && $0.recordedAt < endDate }.count
            let restDays = reviews.filter { r in r.isRestDay && (LocalDay(r.dayKey).map { $0 >= start && $0 <= end } ?? false) }.count
            if startDate >= goal.createdAt.addingTimeInterval(-86_400) || committed {
                periods.append(CommittedPeriod(hadCommitment: committed, evidenceCount: count, isPlannedRest: restDays >= 5))
            }
        }

        // 里程碑或數值目標的預測延誤
        var slip: Int? = nil
        if let deadline = goal.deadline, let target = goal.outcomeTarget, target > 0 {
            let value = ev.filter { $0.kind == .numeric }.compactMap(\.value).reduce(0, +)
            let elapsed = max(1, now.timeIntervalSince(goal.cycleStartedAt) / 86_400)
            let rate = value / elapsed
            if rate > 0, value < target {
                let projected = now.addingTimeInterval((target - value) / rate * 86_400)
                slip = Int(projected.timeIntervalSince(deadline) / 86_400)
            }
        } else if let late = milestones(for: goal.id).first(where: { $0.completedAt == nil && ($0.targetDate ?? .distantFuture) < now }),
                  let t = late.targetDate {
            slip = Int(now.timeIntervalSince(t) / 86_400)
        }

        // 近 14 天：有安排這個目標、而且當天過載
        var shortfall = 0
        for back in 0..<14 {
            let d = today.adding(days: -back, calendar: calendar)
            guard ps.contains(where: { $0.dayKey == d.description }) else { continue }
            if capacity(for: d).state == .overloaded { shortfall += 1 }
        }

        let lastTwo = reviews.filter { $0.eveningClosedAt != nil }.sorted { $0.dayKey > $1.dayKey }.prefix(2)
        let blocked = lastTwo.filter { $0.blockedGoalIDs.contains(goal.id) }.count
        let deferrals = ps.filter { $0.disposition?.countsAsDeferral ?? false }.compactMap(\.dispositionAt)

        return GoalLagInput(lifecycle: goal.status, createdAt: goal.cycleStartedAt, isWaitingOnExternal: goal.isWaiting,
                            periods: periods, deferralDates: deferrals, milestoneForecastSlipDays: slip,
                            capacityShortfallDays: shortfall, blockedReportsInLastTwoReviews: blocked)
    }

    func lagAssessment(_ goal: Goal) -> LagAssessment {
        LagDetector.assess(lagInput(goal), now: now)
    }

    func openEpisode(for goal: Goal) -> RecoveryEpisode? {
        context.all(RecoveryEpisode.self).first { $0.goalID == goal.id && $0.status == .open }
    }

    /// 每日層：開啟 App 時評估焦點目標；受抑制規則管控，不會同日重複
    func evaluateRecoveryPrompts() {
        guard settings.recoveryPrompts else { return }
        for g in goals where g.status == .active {
            guard openEpisode(for: g) == nil else { continue }
            guard case .mayNeedRecovery(let signals) = lagAssessment(g) else { continue }
            let key = "recovery:\(g.id.uuidString)"
            guard InterventionGate.shouldShow(key: key, level: .daily, severity: signals.count, now: now, today: today,
                                              history: interventionHistory()) else { continue }
            let e = RecoveryEpisode(goalID: g.id, cycleNumber: g.cycleNumber, signals: signals)
            e.openedAt = now
            e.snapshotDeadline = g.deadline
            e.snapshotStrategyID = activeStrategy(for: g.id)?.id
            context.insert(e)
            logIntervention(key: key, level: .daily, outcome: .shown, severity: signals.count)
        }
        save()
    }

    func interventionHistory() -> [InterventionRecord] { context.all(InterventionEvent.self).map(\.record) }

    func logIntervention(key: String, level: InterventionLevel, outcome: InterventionOutcome, severity: Int, snoozeUntil: Date? = nil) {
        let e = InterventionEvent(key: key, level: level, outcome: outcome, severity: severity, day: today)
        e.at = now
        e.snoozeUntil = snoozeUntil
        context.insert(e)
        save()
    }

    // MARK: - 恢復（PRD 7.10）

    /// 使用者完成所選方案後才結案；重複呼叫不會重複
    func resolve(_ e: RecoveryEpisode, with option: RecoveryOption, reason: String) {
        guard e.status == .open || e.status == .snoozed else { return }
        e.status = .resolved
        e.chosenOptionRaw = option.rawValue
        e.reason = reason.trimmed
        e.closedAt = now
        logIntervention(key: "recovery:\(e.goalID.uuidString)", level: .daily, outcome: .handled, severity: e.signals.count)
        save()
    }

    func snooze(_ e: RecoveryEpisode, days: Int) {
        e.status = .snoozed
        e.snoozeUntil = now.addingTimeInterval(Double(days) * 86_400)
        logIntervention(key: "recovery:\(e.goalID.uuidString)", level: .daily, outcome: .snoozed, severity: e.signals.count,
                        snoozeUntil: e.snoozeUntil)
    }

    func dismiss(_ e: RecoveryEpisode) {
        e.status = .dismissed
        e.closedAt = now
        logIntervention(key: "recovery:\(e.goalID.uuidString)", level: .daily, outcome: .dismissed, severity: e.signals.count)
    }

    /// 重新開始：新週期、保留全部歷史；同一 episode 重複確認不會產生第二個週期（AC-12）
    func restartCycle(_ goal: Goal, reason: String, episode: RecoveryEpisode? = nil) {
        if let episode, episode.status == .resolved, episode.chosenOption == .restartCycle { return }
        let next = GoalCycle(number: goal.cycleNumber, startedAt: goal.cycleStartedAt).restarted(at: now)
        goal.cycleNumber = next.number
        goal.cycleStartedAt = next.startedAt
        if goal.status == .paused { goal.status = isExecutable(goal) ? .active : .draft }
        goal.pausedUntil = nil
        if let episode { resolve(episode, with: .restartCycle, reason: reason) }
        else {
            let e = RecoveryEpisode(goalID: goal.id, cycleNumber: next.number, signals: [])
            e.status = .resolved
            e.chosenOptionRaw = RecoveryOption.restartCycle.rawValue
            e.reason = reason.trimmed
            e.closedAt = now
            context.insert(e)
        }
        save()
    }

    // MARK: - 期限層介入

    func deadlinePromptGoals() -> [DeadlinePrompt] {
        guard settings.deadlinePrompts else { return [] }
        return focusGoals.compactMap { g -> DeadlinePrompt? in
            let risk = deadlineRisk(g)
            guard risk >= .medium,
                  InterventionGate.shouldShow(key: "deadline:\(g.id.uuidString)", level: .deadline, severity: risk.rawValue,
                                              now: now, today: today, history: interventionHistory()) else { return nil }
            return DeadlinePrompt(goal: g, risk: risk)
        }
    }

    func weeklyPromptDue() -> Bool {
        guard settings.weeklyPrompts else { return false }
        let key = weekStart.description
        if context.all(WeeklyReview.self).contains(where: { $0.weekStartKey == key && $0.completedAt != nil }) { return false }
        return InterventionGate.shouldShow(key: "weekly", level: .weekly, severity: 1, now: now, today: today,
                                           history: interventionHistory())
    }
}
