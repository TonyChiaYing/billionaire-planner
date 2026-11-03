import Foundation
import SwiftData
import PlannerCore

/// Application 層：所有會改變資料的操作都經過這裡（View 只呈現與輸入）。
/// 領域判斷（容量、落後、恢復、重排、草案）交給 PlannerCore 的純函式。
@MainActor
struct Planner {
    let context: ModelContext
    var now: Date = Date()
    var calendar: Calendar = .current
    var settings: PlannerSettings = .load()

    init(_ context: ModelContext, now: Date = Date(), calendar: Calendar = .current, settings: PlannerSettings = .load()) {
        self.context = context
        self.now = now
        self.calendar = calendar
        self.settings = settings
    }

    var today: LocalDay { LocalDay(now, calendar: calendar) }

    func save() { try? context.save() }

    // MARK: - 查詢

    var goals: [Goal] { context.all(Goal.self).sorted { $0.createdAt < $1.createdAt } }
    var focusGoals: [Goal] {
        goals.filter { $0.isFocus && $0.isOpen }.sorted { $0.focusRank < $1.focusRank }
    }
    func goal(_ id: UUID?) -> Goal? {
        guard let id else { return nil }
        return context.all(Goal.self).first { $0.id == id }
    }
    func strategies(for goalID: UUID) -> [Strategy] {
        context.all(Strategy.self).filter { $0.goalID == goalID }.sorted { $0.startedAt < $1.startedAt }
    }
    func activeStrategy(for goalID: UUID) -> Strategy? {
        strategies(for: goalID).last { $0.status == .active }
    }
    func milestones(for goalID: UUID) -> [Milestone] {
        context.all(Milestone.self).filter { $0.goalID == goalID && !$0.isArchived }.sorted { $0.order < $1.order }
    }
    func actions(for goalID: UUID) -> [ActionItem] {
        context.all(ActionItem.self).filter { $0.goalID == goalID }.sorted { $0.createdAt < $1.createdAt }
    }
    func openActions(for goalID: UUID) -> [ActionItem] {
        actions(for: goalID).filter { $0.status.isOpen && $0.status != .waiting }
    }
    func evidence(for goalID: UUID) -> [OutcomeEvidence] {
        context.all(OutcomeEvidence.self).filter { $0.goalID == goalID && !$0.isReversed }.sorted { $0.recordedAt > $1.recordedAt }
    }
    func deadlineHistory(for goalID: UUID) -> [DeadlineRevision] {
        context.all(DeadlineRevision.self).filter { $0.goalID == goalID }.sorted { $0.changedAt < $1.changedAt }
    }
    func actionMap() -> [UUID: ActionItem] {
        Dictionary(context.all(ActionItem.self).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    func placements(on day: LocalDay) -> [PlanPlacement] {
        let key = day.description
        return context.all(PlanPlacement.self).filter { $0.dayKey == key }.sorted(by: Planner.placementOrder)
    }
    func dayBlocks(on day: LocalDay) -> [DayBlock] {
        let key = day.description
        return context.all(DayBlock.self).filter { $0.dayKey == key && !$0.isRemoved }.sorted { $0.startMinute < $1.startMinute }
    }
    func review(for day: LocalDay) -> DailyReview {
        if let r = context.all(DailyReview.self).first(where: { $0.dayKey == day.description }) { return r }
        let r = DailyReview(day: day)
        context.insert(r)
        return r
    }
    func existingReview(for day: LocalDay) -> DailyReview? {
        context.all(DailyReview.self).first { $0.dayKey == day.description }
    }

    static func placementOrder(_ a: PlanPlacement, _ b: PlanPlacement) -> Bool {
        switch (a.startMinute, b.startMinute) {
        case let (x?, y?): return x != y ? x < y : a.order < b.order
        case (_?, nil): return true
        case (nil, _?): return false
        default:
            let pa = a.period.map { DayPeriod.allCases.firstIndex(of: $0) ?? 0 } ?? 3
            let pb = b.period.map { DayPeriod.allCases.firstIndex(of: $0) ?? 0 } ?? 3
            return pa != pb ? pa < pb : a.order < b.order
        }
    }

    func isExecutable(_ goal: Goal) -> Bool {
        FocusPolicy.isExecutable(hasActiveStrategy: activeStrategy(for: goal.id) != nil,
                                 openActionCount: openActions(for: goal.id).count)
    }

    /// 目標還缺什麼（V201-UAT-03）：只描述真正缺少的結構
    enum MissingSetup: Equatable {
        case none, strategy, action, both
        var label: String? {
            switch self {
            case .none: nil
            case .strategy: "需要策略"
            case .action: "需要下一步"
            case .both: "需要策略與下一步"
            }
        }
    }

    func missingSetup(_ goal: Goal) -> MissingSetup {
        switch (activeStrategy(for: goal.id) == nil, openActions(for: goal.id).isEmpty) {
        case (false, false): .none
        case (true, false): .strategy
        case (false, true): .action
        case (true, true): .both
        }
    }

    // MARK: - 進度（雙重呈現）

    func outcomeProgress(_ goal: Goal, cycleOnly: Bool = false) -> OutcomeProgress {
        let ev = evidence(for: goal.id).filter { !cycleOnly || $0.cycleNumber == goal.cycleNumber }
        let ms = milestones(for: goal.id)
        return OutcomeProgress.compute(target: goal.outcomeTarget, unit: goal.outcomeUnit,
                                       numericValues: ev.filter { $0.kind == .numeric }.compactMap(\.value),
                                       milestonesDone: ms.filter { $0.completedAt != nil }.count,
                                       milestonesTotal: ms.count, evidenceCount: ev.count)
    }

    func actionTrend(_ goal: Goal) -> ActionTrend {
        let acts = actions(for: goal.id)
        let ids = Set(acts.map(\.id))
        let weekAgo = today.adding(days: -6, calendar: calendar)
        let planned7 = context.all(PlanPlacement.self).filter { ids.contains($0.actionID) && $0.day >= weekAgo && $0.day <= today }.count
        let completions = acts.compactMap { a in a.completedAt.map { (date: $0, minutes: Optional(a.actualMinutes)) } }
        return ActionTrend.compute(completions: completions, plannedLast7: planned7, now: now)
    }

    func deadlineRisk(_ goal: Goal) -> DeadlineRisk {
        DeadlineRisk.assess(deadline: goal.deadline, startedAt: goal.cycleStartedAt,
                            progress: outcomeProgress(goal).fraction, now: now)
    }

    // MARK: - 估時建議（AC-07）

    func estimateSuggestion(title: String, goalID: UUID?, kind: ItemContext, userEstimate: Int?) -> EstimateSuggestion? {
        guard settings.estimateSuggestions else { return nil }
        let history = context.all(ActionItem.self)
            .filter { $0.status == .done && $0.actualMinutes > 0 }
            .map { EstimateSample(title: $0.title, goalID: $0.goalID, context: $0.kind, actualMinutes: $0.actualMinutes,
                                  completedAt: $0.completedAt ?? $0.createdAt) }
        return EstimateSuggester.suggest(title: title, goalID: goalID, context: kind, userEstimate: userEstimate, history: history)
    }

    func plannedMinutes(_ p: PlanPlacement, action: ActionItem?) -> Int {
        p.durationMinutes ?? action?.estimateMinutes ?? settings.defaultEstimateMinutes
    }

    // MARK: - 容量（PRD 7.4）

    func capacityInput(for day: LocalDay) -> CapacityInput {
        let blocks = dayBlocks(on: day)
        let actions = actionMap()
        let items = placements(on: day).filter(\.isActiveToday).map { p -> CapacityItem in
            let a = actions[p.actionID]
            return CapacityItem(id: p.id, title: a?.title ?? "", minutes: plannedMinutes(p, action: a),
                                context: a?.kind ?? .personal, isHighEnergy: a?.isHighEnergy ?? false, isLocked: p.isLocked || p.isDone)
        }
        return CapacityInput(availableMinutes: settings.availableMinutes,
                             fixedWorkMinutes: blocks.filter { $0.kind == .work }.reduce(0) { $0 + $1.durationMinutes },
                             restMinutes: blocks.filter { $0.kind.isProtected }.reduce(0) { $0 + $1.durationMinutes },
                             items: items)
    }

    func capacity(for day: LocalDay) -> CapacityAssessment {
        CapacityCalculator.assess(capacityInput(for: day), policy: settings.capacityPolicy)
    }
}
