import Foundation

// MARK: - 落後訊號（PRD 7.9 / AC-11）

public enum LagSignalKind: String, CaseIterable, Sendable, Codable {
    case noEvidenceInCommittedPeriods
    case repeatedDeferrals
    case milestoneForecastLate
    case chronicCapacityShortfall
    case userReportedBlocked
}

public struct LagSignal: Sendable, Equatable, Codable {
    public let kind: LagSignalKind
    public let evidence: String
}

/// 一個已承諾週期（通常為一週）的摘要
public struct CommittedPeriod: Sendable, Equatable {
    public var hadCommitment: Bool
    public var evidenceCount: Int
    public var isPlannedRest: Bool

    public init(hadCommitment: Bool, evidenceCount: Int, isPlannedRest: Bool = false) {
        self.hadCommitment = hadCommitment
        self.evidenceCount = evidenceCount
        self.isPlannedRest = isPlannedRest
    }
}

public enum GoalLifecycle: String, CaseIterable, Sendable, Codable {
    case draft, active, paused, completed, archived

    public var label: String {
        switch self {
        case .draft: "草稿"
        case .active: "進行中"
        case .paused: "暫停中"
        case .completed: "已完成"
        case .archived: "已封存"
        }
    }
}

public struct GoalLagInput: Sendable {
    public var lifecycle: GoalLifecycle
    public var createdAt: Date
    public var isWaitingOnExternal: Bool
    public var periods: [CommittedPeriod]           // 舊 → 新
    public var deferralDates: [Date]
    public var milestoneForecastSlipDays: Int?      // 預測超過期限的天數
    public var capacityShortfallDays: Int           // 近 14 天計畫需求 > 可承諾容量的天數
    public var blockedReportsInLastTwoReviews: Int
    public var userDeclaredNeedsRecovery: Bool

    public init(lifecycle: GoalLifecycle, createdAt: Date, isWaitingOnExternal: Bool = false,
                periods: [CommittedPeriod] = [], deferralDates: [Date] = [], milestoneForecastSlipDays: Int? = nil,
                capacityShortfallDays: Int = 0, blockedReportsInLastTwoReviews: Int = 0,
                userDeclaredNeedsRecovery: Bool = false) {
        self.lifecycle = lifecycle
        self.createdAt = createdAt
        self.isWaitingOnExternal = isWaitingOnExternal
        self.periods = periods
        self.deferralDates = deferralDates
        self.milestoneForecastSlipDays = milestoneForecastSlipDays
        self.capacityShortfallDays = capacityShortfallDays
        self.blockedReportsInLastTwoReviews = blockedReportsInLastTwoReviews
        self.userDeclaredNeedsRecovery = userDeclaredNeedsRecovery
    }
}

public struct LagPolicy: Sendable, Equatable {
    public var consecutiveEmptyPeriods = 2
    public var deferralThreshold = 3
    public var deferralWindowDays = 7
    public var forecastToleranceDays = 7
    public var shortfallDaysThreshold = 5
    public var minimumHistoryDays = 7
    public var requiredSignalKinds = 2
    public init() {}
}

public enum LagAssessment: Sendable, Equatable {
    case notApplicable(reason: String)
    case insufficientData
    case onTrack(signals: [LagSignal])
    case mayNeedRecovery(signals: [LagSignal])

    public var signals: [LagSignal] {
        switch self {
        case .onTrack(let s), .mayNeedRecovery(let s): s
        default: []
        }
    }
}

public enum LagDetector {
    public static func assess(_ input: GoalLagInput, now: Date, policy: LagPolicy = LagPolicy()) -> LagAssessment {
        switch input.lifecycle {
        case .paused: return .notApplicable(reason: "目標暫停中")
        case .draft: return .notApplicable(reason: "目標仍是草稿")
        case .completed, .archived: return .notApplicable(reason: "目標已結束")
        case .active: break
        }
        if input.isWaitingOnExternal { return .notApplicable(reason: "正在等待外部條件") }
        if input.userDeclaredNeedsRecovery {
            return .mayNeedRecovery(signals: [LagSignal(kind: .userReportedBlocked, evidence: "你主動表示這個目標需要調整")])
        }

        let ageDays = Int(now.timeIntervalSince(input.createdAt) / 86_400)
        let hasHistory = !input.periods.isEmpty || !input.deferralDates.isEmpty || input.milestoneForecastSlipDays != nil
            || input.capacityShortfallDays > 0 || input.blockedReportsInLastTwoReviews > 0
        if ageDays < policy.minimumHistoryDays && !hasHistory { return .insufficientData }

        var signals: [LagSignal] = []

        // 1. 連續已承諾週期沒有成果（休息週期不算、也不打斷）
        let counted = input.periods.filter { !$0.isPlannedRest }
        let tail = counted.suffix(policy.consecutiveEmptyPeriods)
        if tail.count == policy.consecutiveEmptyPeriods, tail.allSatisfy({ $0.hadCommitment && $0.evidenceCount == 0 }) {
            signals.append(LagSignal(kind: .noEvidenceInCommittedPeriods,
                                     evidence: "最近 \(policy.consecutiveEmptyPeriods) 個有安排的週期都還沒有成果紀錄"))
        }
        // 2. 7 天內延後 3 次以上
        let windowStart = now.addingTimeInterval(-Double(policy.deferralWindowDays) * 86_400)
        let deferrals = input.deferralDates.filter { $0 >= windowStart && $0 <= now }.count
        if deferrals >= policy.deferralThreshold {
            signals.append(LagSignal(kind: .repeatedDeferrals,
                                     evidence: "\(policy.deferralWindowDays) 天內相關行動延後了 \(deferrals) 次"))
        }
        // 3. 里程碑預測超過期限容忍
        if let slip = input.milestoneForecastSlipDays, slip > policy.forecastToleranceDays {
            signals.append(LagSignal(kind: .milestoneForecastLate, evidence: "依目前步調，預估會比期限晚約 \(slip) 天"))
        }
        // 4. 容量長期不足
        if input.capacityShortfallDays >= policy.shortfallDaysThreshold {
            signals.append(LagSignal(kind: .chronicCapacityShortfall,
                                     evidence: "近兩週有 \(input.capacityShortfallDays) 天的安排超過可承諾容量"))
        }
        // 5. 兩次回顧都表示受阻
        if input.blockedReportsInLastTwoReviews >= 2 {
            signals.append(LagSignal(kind: .userReportedBlocked, evidence: "最近兩次回顧都提到這個目標受阻"))
        }

        if Set(signals.map(\.kind)).count >= policy.requiredSignalKinds { return .mayNeedRecovery(signals: signals) }
        if !hasHistory { return .insufficientData }
        return .onTrack(signals: signals)
    }
}

// MARK: - 恢復方案（PRD 7.10）

public enum RecoveryOption: String, CaseIterable, Sendable, Codable {
    case shrinkNextStep, reduceFrequency, switchStrategy, moveMilestoneOrDeadline, pauseWithReviewDate, restartCycle

    public var title: String {
        switch self {
        case .shrinkNextStep: "把下一步縮小"
        case .reduceFrequency: "降低本週頻率或投入"
        case .switchStrategy: "換一個策略"
        case .moveMilestoneOrDeadline: "移動里程碑或調整期限"
        case .pauseWithReviewDate: "先暫停，設定回看日期"
        case .restartCycle: "開始新的恢復週期"
        }
    }

    public var explanation: String {
        switch self {
        case .shrinkNextStep: "改動最小：把下一步縮到 5–15 分鐘也能完成的版本。"
        case .reduceFrequency: "保留方向，只是這週少安排一些，讓節奏跟得上。"
        case .switchStrategy: "目前的方法可能不適合，換個做法；舊策略的紀錄會保留。"
        case .moveMilestoneOrDeadline: "調整時間線；原期限會留在期限歷史中。"
        case .pauseWithReviewDate: "有意識地暫停，到回看日再決定，不會被提醒打擾。"
        case .restartCycle: "從今天起算新週期；過去的成果全部保留並持續累積。"
        }
    }

    public var symbol: String {
        switch self {
        case .shrinkNextStep: "arrow.down.right.and.arrow.up.left"
        case .reduceFrequency: "tortoise"
        case .switchStrategy: "arrow.triangle.branch"
        case .moveMilestoneOrDeadline: "calendar.badge.clock"
        case .pauseWithReviewDate: "pause.circle"
        case .restartCycle: "arrow.clockwise.circle"
        }
    }
}

public enum RecoveryPlanner {
    /// 一律由最小改動排到最大
    public static func rankedOptions(hasAlternativeStrategy: Bool = true, hasDeadlineOrMilestone: Bool = true) -> [RecoveryOption] {
        RecoveryOption.allCases.filter { option in
            switch option {
            case .moveMilestoneOrDeadline: hasDeadlineOrMilestone
            default: true
            }
        }
    }
}

/// 恢復週期：同一個目標跨週期延續，不清空。
public struct GoalCycle: Sendable, Equatable {
    public var number: Int
    public var startedAt: Date
    public init(number: Int, startedAt: Date) {
        self.number = number
        self.startedAt = startedAt
    }

    public func restarted(at date: Date) -> GoalCycle { GoalCycle(number: number + 1, startedAt: date) }
}

public struct EvidencePoint: Sendable, Equatable {
    public var recordedAt: Date
    public var value: Double?
    public var cycle: Int
    public init(recordedAt: Date, value: Double?, cycle: Int) {
        self.recordedAt = recordedAt
        self.value = value
        self.cycle = cycle
    }
}

public struct CycleSplit: Sendable, Equatable {
    public var cumulativeCount: Int
    public var cumulativeValue: Double
    public var cycleCount: Int
    public var cycleValue: Double
}

public enum CycleViews {
    /// 「累積成果」與「本次恢復週期」兩套視圖（AC-12：累積不歸零）
    public static func split(_ points: [EvidencePoint], currentCycle: Int) -> CycleSplit {
        let inCycle = points.filter { $0.cycle == currentCycle }
        return CycleSplit(cumulativeCount: points.count, cumulativeValue: points.compactMap(\.value).reduce(0, +),
                          cycleCount: inCycle.count, cycleValue: inCycle.compactMap(\.value).reduce(0, +))
    }
}

// MARK: - 期限歷史（只增不改，AC-13）

public struct DeadlineRevisionValue: Sendable, Equatable {
    public var oldDeadline: Date?
    public var newDeadline: Date?
    public var changedAt: Date
    public var reason: String
    public init(oldDeadline: Date?, newDeadline: Date?, changedAt: Date, reason: String = "") {
        self.oldDeadline = oldDeadline
        self.newDeadline = newDeadline
        self.changedAt = changedAt
        self.reason = reason
    }
}

public enum DeadlineHistory {
    public static func appending(_ history: [DeadlineRevisionValue], newDeadline: Date?, at: Date,
                                 reason: String = "") -> [DeadlineRevisionValue] {
        let current = history.last?.newDeadline
        guard current != newDeadline else { return history }
        return history + [DeadlineRevisionValue(oldDeadline: current, newDeadline: newDeadline, changedAt: at, reason: reason)]
    }
}

public enum DeadlineRisk: Int, Sendable, Comparable, CaseIterable {
    case none = 0, low, medium, high

    public var label: String {
        switch self {
        case .none: "無期限"
        case .low: "期限穩定"
        case .medium: "期限需要留意"
        case .high: "期限很近，值得檢視"
        }
    }

    public static func < (a: DeadlineRisk, b: DeadlineRisk) -> Bool { a.rawValue < b.rawValue }

    /// progress: 0...1 的成果進度（未知為 nil）
    public static func assess(deadline: Date?, startedAt: Date, progress: Double?, now: Date) -> DeadlineRisk {
        guard let deadline else { return .none }
        let daysLeft = deadline.timeIntervalSince(now) / 86_400
        if daysLeft < 0 { return .high }
        let total = max(1, deadline.timeIntervalSince(startedAt))
        let expected = min(1, max(0, now.timeIntervalSince(startedAt) / total))
        guard let progress else { return daysLeft <= 7 ? .medium : .low }
        if daysLeft <= 7 && progress < 0.8 { return .high }
        if expected - progress > 0.25 { return .medium }
        return .low
    }
}
