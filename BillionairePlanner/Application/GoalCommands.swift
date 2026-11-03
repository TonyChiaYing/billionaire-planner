import Foundation
import SwiftData
import PlannerCore

/// UAT-01：建立目標第三步完成後的明確選擇（不自動設為焦點）
enum SetupFinishChoice: String, CaseIterable {
    case focusAndToday, focusOnly, todayOnly, later
}

struct SetupFinishResult: Equatable {
    var focus: FocusRequestResult?
    var plannedToday: Bool
}

enum FocusRequestResult: Equatable {
    case focused
    case focusedAboveRecommended(count: Int)
    case needsStrategyAndAction
    case blocked
}

extension Planner {
    // MARK: 漸進式建立（AC-01）

    @discardableResult
    func createGoal(title: String, horizon: GoalHorizon, outcome: String) -> Goal {
        let g = Goal(title: title.trimmed, horizon: horizon, outcomeDescription: outcome.trimmed)
        g.createdAt = now
        g.cycleStartedAt = now
        g.lastActivityAt = now
        context.insert(g)
        save()
        return g
    }

    /// 有策略＋下一步就從草稿變成可執行
    func refreshReadiness(_ goal: Goal) {
        if goal.status == .draft, isExecutable(goal) {
            goal.status = .active
            goal.activatedAt = now
        }
        goal.lastActivityAt = now
        save()
    }

    /// 完成建立：依使用者明確選擇加入焦點／安排今天；「稍後」不產生任何副作用
    @discardableResult
    func finishSetup(_ goal: Goal, choice: SetupFinishChoice) -> SetupFinishResult {
        switch choice {
        case .later:
            return SetupFinishResult(focus: nil, plannedToday: false)
        case .focusOnly:
            return SetupFinishResult(focus: requestFocus(goal), plannedToday: false)
        case .todayOnly:
            return SetupFinishResult(focus: nil, plannedToday: planFirstActionToday(goal))
        case .focusAndToday:
            let r = requestFocus(goal)
            switch r {
            case .focused, .focusedAboveRecommended:
                return SetupFinishResult(focus: r, plannedToday: planFirstActionToday(goal))
            default:
                return SetupFinishResult(focus: r, plannedToday: false)   // 焦點已滿或尚未可執行：什麼都不改
            }
        }
    }

    /// 把第一個下一步排進今天（已排過就不重複）
    func planFirstActionToday(_ goal: Goal) -> Bool {
        let placed = Set(placements(on: today).filter(\.isActiveToday).map(\.actionID))
        guard let a = openActions(for: goal.id).first(where: { !placed.contains($0.id) }) else { return false }
        plan(a, on: today)
        return true
    }

    /// 建立完成畫面的容量（V201-UAT-01）：下一步尚未排進今天 → 「安排前預估」（不寫入）；
    /// 已排進今天 → 今天的實際容量。同一個行動永遠只算一次。
    func setupCapacity(for goal: Goal) -> (assessment: CapacityAssessment, isEstimate: Bool) {
        let placed = Set(placements(on: today).filter(\.isActiveToday).map(\.actionID))
        let open = openActions(for: goal.id)
        guard let next = open.first(where: { !placed.contains($0.id) }), !open.contains(where: { placed.contains($0.id) }) else {
            return (capacity(for: today), false)
        }
        var input = capacityInput(for: today)
        input.items.append(CapacityItem(minutes: next.estimateMinutes ?? settings.defaultEstimateMinutes))
        return (CapacityCalculator.assess(input, policy: settings.capacityPolicy), true)
    }

    // MARK: 期限（只增不改，AC-13）

    func changeDeadline(_ goal: Goal, to newDeadline: Date?, reason: String, recoveryEpisodeID: UUID? = nil) {
        guard goal.deadline != newDeadline else { return }
        context.insert(DeadlineRevision(goalID: goal.id, oldDeadline: goal.deadline, newDeadline: newDeadline,
                                        reason: reason.trimmed, recoveryEpisodeID: recoveryEpisodeID))
        goal.deadline = newDeadline
        save()
    }

    // MARK: 里程碑

    @discardableResult
    func addMilestone(_ goal: Goal, title: String, targetDate: Date?) -> Milestone {
        let m = Milestone(goalID: goal.id, title: title.trimmed, targetDate: targetDate, order: milestones(for: goal.id).count)
        context.insert(m)
        goal.lastActivityAt = now
        save()
        return m
    }

    func setMilestone(_ m: Milestone, done: Bool) {
        m.completedAt = done ? now : nil
        save()
    }

    // MARK: 動態策略（AC-03）

    @discardableResult
    func addStrategy(_ goal: Goal, title: String, hypothesis: String = "") -> Strategy {
        let s = Strategy(goalID: goal.id, title: title.trimmed, hypothesis: hypothesis.trimmed)
        s.startedAt = now
        s.status = activeStrategy(for: goal.id) == nil ? .active : .proposed
        context.insert(s)
        save()
        refreshReadiness(goal)
        return s
    }

    /// 換策略：舊策略標為「已替換」，歷史行動與成果仍指向舊策略，目標進度不歸零
    @discardableResult
    func switchStrategy(_ goal: Goal, toTitle title: String, reason: String) -> Strategy {
        for old in strategies(for: goal.id) where old.status == .active {
            old.status = .retired
            old.endedAt = now
            old.decisionReason = reason.trimmed
        }
        let s = Strategy(goalID: goal.id, title: title.trimmed)
        s.startedAt = now
        context.insert(s)
        // 未完成的下一步改掛新策略；已完成的留在舊策略
        for a in openActions(for: goal.id) { a.strategyID = s.id }
        save()
        refreshReadiness(goal)
        return s
    }

    func activate(_ strategy: Strategy, in goal: Goal, reason: String = "") {
        for old in strategies(for: goal.id) where old.status == .active && old.id != strategy.id {
            old.status = .paused
            old.decisionReason = reason.trimmed
        }
        strategy.status = .active
        strategy.endedAt = nil
        save()
        refreshReadiness(goal)
    }

    func setStrategy(_ s: Strategy, status: StrategyStatus, reason: String) {
        s.status = status
        s.decisionReason = reason.trimmed
        if status == .retired || status == .succeeded { s.endedAt = now }
        save()
    }

    // MARK: 行動

    @discardableResult
    func addAction(title: String, kind: ItemContext, goal: Goal?, estimate: Int?, estimateSource: String = "user",
                   minimumVersion: String = "", milestoneID: UUID? = nil) -> ActionItem {
        let a = ActionItem(title: title.trimmed, kind: kind, goalID: goal?.id,
                           strategyID: goal.flatMap { activeStrategy(for: $0.id)?.id })
        a.createdAt = now
        a.estimateMinutes = estimate
        a.estimateSource = estimate == nil ? "" : estimateSource
        a.minimumVersion = minimumVersion.trimmed
        a.milestoneID = milestoneID
        a.status = goal == nil ? .inbox : .ready
        context.insert(a)
        save()
        if let goal { refreshReadiness(goal) }
        return a
    }

    func shrink(_ action: ActionItem, toMinutes minutes: Int, description: String) {
        action.minimumMinutes = minutes
        if !description.trimmed.isEmpty { action.minimumVersion = description.trimmed }
        action.estimateMinutes = minutes
        action.estimateSource = "user"
        save()
    }

    // MARK: 焦點（AC-02）

    func requestFocus(_ goal: Goal) -> FocusRequestResult {
        guard isExecutable(goal) else { return .needsStrategyAndAction }
        let current = focusGoals.filter { $0.id != goal.id && $0.status != .completed }.count
        switch FocusPolicy.check(currentFocusCount: current) {
        case .blocked: return .blocked
        case .allowedAboveRecommended(let n):
            setFocus(goal, rank: current)
            return .focusedAboveRecommended(count: n)
        case .allowed:
            setFocus(goal, rank: current)
            return .focused
        }
    }

    private func setFocus(_ goal: Goal, rank: Int) {
        goal.isFocus = true
        goal.focusRank = rank
        if goal.status == .draft { goal.status = .active; goal.activatedAt = now }
        save()
    }

    func unfocus(_ goal: Goal) {
        goal.isFocus = false
        goal.focusRank = 99
        renumberFocus()
    }

    /// 以新目標替換某個焦點（不刪除或改動被替換的目標，只取消焦點）
    func replaceFocus(_ old: Goal, with new: Goal) {
        let rank = old.focusRank
        old.isFocus = false
        old.focusRank = 99
        new.isFocus = true
        new.focusRank = rank
        if new.status == .draft { new.status = .active; new.activatedAt = now }
        renumberFocus()
    }

    func moveFocus(_ goal: Goal, by delta: Int) {
        var list = focusGoals
        guard let i = list.firstIndex(where: { $0.id == goal.id }) else { return }
        let j = min(max(0, i + delta), list.count - 1)
        guard i != j else { return }
        list.swapAt(i, j)
        for (n, g) in list.enumerated() { g.focusRank = n }
        save()
    }

    private func renumberFocus() {
        for (n, g) in focusGoals.enumerated() { g.focusRank = n }
        save()
    }

    // MARK: 成果證據

    @discardableResult
    func recordEvidence(_ goal: Goal, kind: EvidenceKind, value: Double?, note: String, actionID: UUID? = nil,
                        milestoneID: UUID? = nil) -> OutcomeEvidence {
        let e = OutcomeEvidence(goalID: goal.id, kind: kind, value: value, note: note.trimmed, cycleNumber: goal.cycleNumber)
        e.recordedAt = now
        e.actionID = actionID
        e.milestoneID = milestoneID
        e.strategyID = activeStrategy(for: goal.id)?.id
        e.unit = goal.outcomeUnit
        context.insert(e)
        goal.lastActivityAt = now
        save()
        return e
    }

    /// 反轉而不刪除（保留稽核紀錄）
    func reverse(_ e: OutcomeEvidence) {
        e.isReversed = true
        save()
    }

    // MARK: 生命週期

    func pause(_ goal: Goal, until reviewDate: Date?, reason: String) {
        goal.status = .paused
        goal.pausedUntil = reviewDate
        save()
    }

    func resume(_ goal: Goal) {
        goal.status = isExecutable(goal) ? .active : .draft
        goal.pausedUntil = nil
        save()
    }

    func complete(_ goal: Goal) {
        goal.status = .completed
        goal.completedAt = now
        goal.isFocus = false
        renumberFocus()
    }

    func archive(_ goal: Goal) {
        goal.status = .archived
        goal.archivedAt = now
        goal.isFocus = false
        renumberFocus()
    }

    func reopen(_ goal: Goal) {
        goal.status = isExecutable(goal) ? .active : .draft
        goal.completedAt = nil
        goal.archivedAt = nil
        save()
    }

    /// 遷移後手動連結（取代 v1 的標題關聯）
    func link(_ action: ActionItem, to goal: Goal) {
        action.goalID = goal.id
        action.strategyID = activeStrategy(for: goal.id)?.id
        save()
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
