import Foundation

// MARK: - 明日草案（PRD 7.3 / AC-06）

public enum DraftSource: Int, Sendable, Comparable, CaseIterable, Codable {
    case lockedCommitment = 0, templateFixed, carryover, focusAction, restBoundary, buffer

    public var label: String {
        switch self {
        case .lockedCommitment: "已承諾"
        case .templateFixed: "工作模板"
        case .carryover: "延續"
        case .focusAction: "焦點目標下一步"
        case .restBoundary: "休息／生活"
        case .buffer: "緩衝"
        }
    }

    public static func < (a: DraftSource, b: DraftSource) -> Bool { a.rawValue < b.rawValue }
}

public struct DraftCandidate: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var minutes: Int
    public var source: DraftSource
    public var context: ItemContext
    public var rank: Int

    public init(id: UUID = UUID(), title: String, minutes: Int, source: DraftSource,
                context: ItemContext = .personal, rank: Int = 0) {
        self.id = id
        self.title = title
        self.minutes = max(0, minutes)
        self.source = source
        self.context = context
        self.rank = rank
    }
}

public struct DraftEntry: Sendable, Equatable, Identifiable {
    public var id: UUID { candidate.id }
    public let candidate: DraftCandidate
    public let reason: String
}

public struct TomorrowDraft: Sendable, Equatable {
    public let fixed: [DraftEntry]       // 模板＋休息邊界（容量的前提）
    public let included: [DraftEntry]    // 建議承諾的彈性項目
    public let excluded: [DraftEntry]    // 裝不下，附原因
    public let capacity: CapacityAssessment
}

public enum TomorrowDrafter {
    public static func build(availableMinutes: Int, template: [DraftCandidate], rest: [DraftCandidate],
                             locked: [DraftCandidate], carryovers: [DraftCandidate], focusActions: [DraftCandidate],
                             policy: CapacityPolicy = CapacityPolicy()) -> TomorrowDraft {
        let fixedMinutes = template.reduce(0) { $0 + $1.minutes }
        let restMinutes = rest.reduce(0) { $0 + $1.minutes }
        let base = CapacityCalculator.assess(CapacityInput(availableMinutes: availableMinutes, fixedWorkMinutes: fixedMinutes,
                                                           restMinutes: restMinutes, items: []), policy: policy)
        var budget = base.committableMinutes
        var included: [DraftEntry] = []
        var excluded: [DraftEntry] = []

        // 已承諾事項永遠保留（就算超過也只標示，不刪）
        for c in locked {
            included.append(DraftEntry(candidate: c, reason: "你已承諾"))
            budget -= c.minutes
        }
        let flexible = carryovers.map { ($0, "昨天延續") }
            + focusActions.sorted { $0.rank < $1.rank }.map { ($0, "焦點目標的最小下一步") }
        for (c, why) in flexible {
            if c.minutes <= budget {
                included.append(DraftEntry(candidate: c, reason: why))
                budget -= c.minutes
            } else {
                excluded.append(DraftEntry(candidate: c, reason: "容量不足：還差 \(formatDuration(c.minutes - max(0, budget)))"))
            }
        }

        let items = included.map { CapacityItem(id: $0.id, title: $0.candidate.title, minutes: $0.candidate.minutes,
                                                context: $0.candidate.context, isLocked: $0.candidate.source == .lockedCommitment) }
        let capacity = CapacityCalculator.assess(CapacityInput(availableMinutes: availableMinutes, fixedWorkMinutes: fixedMinutes,
                                                               restMinutes: restMinutes, items: items), policy: policy)
        var fixed = template.map { DraftEntry(candidate: $0, reason: "工作模板固定區段") }
            + rest.map { DraftEntry(candidate: $0, reason: "受保護的休息／生活邊界") }
        if capacity.bufferMinutes > 0 {
            fixed.append(DraftEntry(candidate: DraftCandidate(title: "緩衝", minutes: capacity.bufferMinutes, source: .buffer),
                                    reason: "保留給不可預期的事"))
        }
        return TomorrowDraft(fixed: fixed, included: included, excluded: excluded, capacity: capacity)
    }
}

// MARK: - 分層介入與抑制（PRD 7.11 / AC-14）

public enum InterventionLevel: String, Sendable, Codable, CaseIterable {
    case daily, weekly, deadline
}

public enum InterventionOutcome: String, Sendable, Codable {
    case shown, handled, snoozed, dismissed
}

public struct InterventionRecord: Sendable, Equatable {
    public var key: String
    public var level: InterventionLevel
    public var outcome: InterventionOutcome
    public var at: Date
    public var severity: Int
    public var snoozeUntil: Date?
    public var planningDay: LocalDay?

    public init(key: String, level: InterventionLevel, outcome: InterventionOutcome, at: Date, severity: Int,
                snoozeUntil: Date? = nil, planningDay: LocalDay? = nil) {
        self.key = key
        self.level = level
        self.outcome = outcome
        self.at = at
        self.severity = severity
        self.snoozeUntil = snoozeUntil
        self.planningDay = planningDay
    }
}

public struct InterventionPolicy: Sendable, Equatable {
    public var dismissCooldownDays = 14
    public var weeklyWindowDays = 7
    public init() {}
}

public enum InterventionGate {
    /// 只有風險升級（severity 變高）才能打破冷卻
    public static func shouldShow(key: String, level: InterventionLevel, severity: Int, now: Date, today: LocalDay,
                                  history: [InterventionRecord], policy: InterventionPolicy = InterventionPolicy()) -> Bool {
        let mine = history.filter { $0.key == key }.sorted { $0.at < $1.at }
        guard let last = mine.last else { return true }
        let maxSeverity = mine.map(\.severity).max() ?? 0
        if severity > maxSeverity { return true }

        if let until = mine.compactMap(\.snoozeUntil).max(), until > now { return false }
        let cooldown = Double(policy.dismissCooldownDays) * 86_400
        if mine.contains(where: { $0.outcome == .dismissed && now.timeIntervalSince($0.at) < cooldown }) { return false }

        switch level {
        case .daily:
            return last.planningDay != today   // 同一問題同一規劃日只出現一次
        case .weekly:
            return now.timeIntervalSince(last.at) >= Double(policy.weeklyWindowDays) * 86_400
        case .deadline:
            // 同等級風險不重複；延後到期才再提示
            return last.outcome == .snoozed && (last.snoozeUntil ?? now) <= now
        }
    }
}

// MARK: - 焦點限制（PRD 7.1 / AC-02）

public enum FocusCheck: Sendable, Equatable {
    case allowed
    case allowedAboveRecommended(count: Int)
    case blocked
}

public enum FocusPolicy {
    public static let recommended = 3
    public static let hardLimit = 5

    public static func check(currentFocusCount: Int) -> FocusCheck {
        if currentFocusCount >= hardLimit { return .blocked }
        if currentFocusCount >= recommended { return .allowedAboveRecommended(count: currentFocusCount + 1) }
        return .allowed
    }

    /// 草稿可存；要能執行必須有啟用中的策略與一個未完成的下一步
    public static func isExecutable(hasActiveStrategy: Bool, openActionCount: Int) -> Bool {
        hasActiveStrategy && openActionCount > 0
    }
}

// MARK: - 首頁排序（PRD 7.1）

public struct GoalRankInput: Sendable, Equatable {
    public var id: UUID
    public var hasPlacementToday: Bool
    public var risk: DeadlineRisk
    public var userRank: Int
    public var lastActivity: Date?

    public init(id: UUID, hasPlacementToday: Bool, risk: DeadlineRisk, userRank: Int, lastActivity: Date?) {
        self.id = id
        self.hasPlacementToday = hasPlacementToday
        self.risk = risk
        self.userRank = userRank
        self.lastActivity = lastActivity
    }
}

public enum GoalOrdering {
    /// 今日關聯 → 期限風險 → 使用者排序 → 最近活動
    public static func sort(_ goals: [GoalRankInput]) -> [UUID] {
        goals.sorted { a, b in
            if a.hasPlacementToday != b.hasPlacementToday { return a.hasPlacementToday }
            if a.risk != b.risk { return a.risk > b.risk }
            if a.userRank != b.userRank { return a.userRank < b.userRank }
            return (a.lastActivity ?? .distantPast) > (b.lastActivity ?? .distantPast)
        }.map(\.id)
    }
}

// MARK: - 錯過不等於失敗（PRD 7.7 / AC-09）

public enum Disposition: String, CaseIterable, Sendable, Codable {
    case startNow, shrink, later, tomorrow, cancelToday, notNeeded

    public var label: String {
        switch self {
        case .startNow: "現在開始"
        case .shrink: "改成縮小版本"
        case .later: "移到稍後"
        case .tomorrow: "移到明日"
        case .cancelToday: "今天先不做"
        case .notNeeded: "標為不再需要"
        }
    }

    public var symbol: String {
        switch self {
        case .startNow: "play.circle"
        case .shrink: "arrow.down.right.and.arrow.up.left"
        case .later: "clock.arrow.circlepath"
        case .tomorrow: "sunrise"
        case .cancelToday: "xmark.circle"
        case .notNeeded: "checkmark.seal"
        }
    }

    /// 這些處置會被視為「延後」（落後訊號的來源之一，但單次不構成落後）
    public var countsAsDeferral: Bool { self == .later || self == .tomorrow }
}

public enum MissedDetector {
    public static func needsDisposition(day: LocalDay, startMinute: Int?, durationMinutes: Int?, isDone: Bool,
                                        isStarted: Bool, isDisposed: Bool, now: Date, calendar: Calendar) -> Bool {
        guard !isDone, !isStarted, !isDisposed else { return false }
        let today = LocalDay(now, calendar: calendar)
        if day < today { return true }
        guard day == today, let start = startMinute else { return false }
        return day.instant(minute: start, in: calendar) < now
    }
}

// MARK: - 雙重進度（PRD 決策 C / AC-04）

public struct OutcomeProgress: Sendable, Equatable {
    public enum Basis: Sendable, Equatable {
        case numeric(value: Double, target: Double, unit: String)
        case milestones(done: Int, total: Int)
        case evidenceOnly(count: Int)
    }
    public let basis: Basis

    public var fraction: Double? {
        switch basis {
        case .numeric(let v, let t, _): t > 0 ? min(1, v / t) : nil
        case .milestones(let d, let t): t > 0 ? Double(d) / Double(t) : nil
        case .evidenceOnly: nil
        }
    }

    public var text: String {
        switch basis {
        case .numeric(let v, let t, let u): "\(trim(v)) / \(trim(t)) \(u)"
        case .milestones(let d, let t): "里程碑 \(d) / \(t)"
        case .evidenceOnly(let c): c == 0 ? "還沒有成果紀錄" : "已記錄 \(c) 項成果"
        }
    }

    private func trim(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }

    public static func compute(target: Double?, unit: String, numericValues: [Double], milestonesDone: Int,
                               milestonesTotal: Int, evidenceCount: Int) -> OutcomeProgress {
        if let target, target > 0 {
            return OutcomeProgress(basis: .numeric(value: numericValues.reduce(0, +), target: target, unit: unit))
        }
        if milestonesTotal > 0 { return OutcomeProgress(basis: .milestones(done: milestonesDone, total: milestonesTotal)) }
        return OutcomeProgress(basis: .evidenceOnly(count: evidenceCount))
    }
}

public struct ActionTrend: Sendable, Equatable {
    public var done7: Int
    public var done30: Int
    public var minutes7: Int
    public var minutes30: Int
    public var planned7: Int

    public static func compute(completions: [(date: Date, minutes: Int?)], plannedLast7: Int, now: Date) -> ActionTrend {
        let d7 = now.addingTimeInterval(-7 * 86_400), d30 = now.addingTimeInterval(-30 * 86_400)
        let in7 = completions.filter { $0.date >= d7 && $0.date <= now }
        let in30 = completions.filter { $0.date >= d30 && $0.date <= now }
        return ActionTrend(done7: in7.count, done30: in30.count,
                           minutes7: in7.compactMap(\.minutes).reduce(0, +),
                           minutes30: in30.compactMap(\.minutes).reduce(0, +), planned7: plannedLast7)
    }
}
