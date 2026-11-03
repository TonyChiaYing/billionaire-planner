import Foundation

/// 可承諾容量 = 可用時間 − 固定工作 − 休息／生活邊界 − 緩衝（PRD 7.4）
public enum LoadState: String, CaseIterable, Sendable {
    case comfortable, feasible, tight, overloaded

    public var label: String {
        switch self {
        case .comfortable: "寬鬆"
        case .feasible: "可行"
        case .tight: "偏滿"
        case .overloaded: "過載"
        }
    }

    /// 不只靠顏色：每個狀態都有圖示與文字
    public var symbol: String {
        switch self {
        case .comfortable: "leaf"
        case .feasible: "checkmark.circle"
        case .tight: "exclamationmark.circle"
        case .overloaded: "exclamationmark.triangle"
        }
    }

    var rank: Int { LoadState.allCases.firstIndex(of: self) ?? 0 }
}

/// 門檻集中於此，皆為推導基準值（非使用者原話），可調整。
public struct CapacityPolicy: Sendable, Equatable {
    public var bufferRatio: Double = 0.20
    public var minimumBufferMinutes: Int = 15
    public var comfortableMax: Double = 0.70
    public var feasibleMax: Double = 0.85
    public var restFloorMinutes: Int = 30
    public var restFloorAppliesFromMinutes: Int = 240
    public var maxContextSwitches: Int = 6
    public var maxHighEnergyItems: Int = 3
    public var transitionMinutesPerSwitch: Int = 0

    public init(bufferRatio: Double = 0.20, restFloorMinutes: Int = 30) {
        self.bufferRatio = min(max(bufferRatio, 0), 0.9)
        self.restFloorMinutes = max(0, restFloorMinutes)
    }
}

public enum ItemContext: String, Codable, Sendable, CaseIterable {
    case personal, work, maintenance
}

public struct CapacityItem: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var minutes: Int
    public var context: ItemContext
    public var isHighEnergy: Bool
    public var isLocked: Bool

    public init(id: UUID = UUID(), title: String = "", minutes: Int, context: ItemContext = .personal,
                isHighEnergy: Bool = false, isLocked: Bool = false) {
        self.id = id
        self.title = title
        self.minutes = max(0, minutes)
        self.context = context
        self.isHighEnergy = isHighEnergy
        self.isLocked = isLocked
    }
}

public struct CapacityInput: Sendable, Equatable {
    public var availableMinutes: Int
    public var fixedWorkMinutes: Int
    public var restMinutes: Int
    public var items: [CapacityItem]

    public init(availableMinutes: Int, fixedWorkMinutes: Int, restMinutes: Int, items: [CapacityItem]) {
        self.availableMinutes = availableMinutes
        self.fixedWorkMinutes = fixedWorkMinutes
        self.restMinutes = restMinutes
        self.items = items
    }
}

public enum CapacityReason: Equatable, Sendable {
    case loadRatio(percent: Int)
    case overBy(minutes: Int)
    case noAvailability
    case missingProtectedRest(have: Int, floor: Int)
    case tooManySwitches(count: Int)
    case clusteredHighEnergy(count: Int)

    public var text: String {
        switch self {
        case .loadRatio(let p): "已安排可承諾容量的 \(p)%"
        case .overBy(let m): "比可承諾容量多 \(formatDuration(m))"
        case .noAvailability: "今天沒有可支配的時間"
        case .missingProtectedRest(let have, let floor): "受保護的休息只有 \(have) 分（建議至少 \(floor) 分）"
        case .tooManySwitches(let c): "工作與個人事項切換 \(c) 次，切換成本偏高"
        case .clusteredHighEnergy(let c): "高耗能事項有 \(c) 項，可能撐不住"
        }
    }
}

public struct CapacityAssessment: Sendable, Equatable {
    public var availableMinutes: Int
    public var fixedWorkMinutes: Int
    public var restMinutes: Int
    public var discretionaryMinutes: Int
    public var bufferMinutes: Int
    public var committableMinutes: Int
    public var loadMinutes: Int
    public var loadRatio: Double
    public var state: LoadState
    public var reasons: [CapacityReason]

    public var overloadMinutes: Int { max(0, loadMinutes - committableMinutes) }
    public var remainingMinutes: Int { max(0, committableMinutes - loadMinutes) }
}

public enum CapacityCalculator {
    public static func assess(_ input: CapacityInput, policy: CapacityPolicy = CapacityPolicy()) -> CapacityAssessment {
        let available = max(0, input.availableMinutes)
        let fixed = max(0, input.fixedWorkMinutes)
        let rest = max(0, input.restMinutes)
        let discretionary = max(0, available - fixed - rest)
        let buffer = discretionary == 0 ? 0
            : min(discretionary, max(policy.minimumBufferMinutes, Int((Double(discretionary) * policy.bufferRatio).rounded())))
        let committable = discretionary - buffer
        let switches = contextSwitches(input.items)
        let load = input.items.reduce(0) { $0 + $1.minutes } + switches * policy.transitionMinutesPerSwitch

        let ratio: Double = committable > 0 ? Double(load) / Double(committable) : (load > 0 ? .infinity : 0)
        var reasons: [CapacityReason] = []
        var state: LoadState

        if committable <= 0 {
            reasons.append(.noAvailability)
            state = load > 0 ? .overloaded : .comfortable
        } else if ratio <= policy.comfortableMax {
            state = .comfortable
        } else if ratio <= policy.feasibleMax {
            state = .feasible
        } else if ratio <= 1.0 {
            state = .tight
        } else {
            state = .overloaded
        }
        if committable > 0, load > 0 { reasons.append(.loadRatio(percent: Int((ratio * 100).rounded()))) }
        if load > committable, committable > 0 { reasons.append(.overBy(minutes: load - committable)) }

        // 總分鐘未超載，也可能因結構因素「偏滿」
        var structural: [CapacityReason] = []
        if available >= policy.restFloorAppliesFromMinutes, rest < policy.restFloorMinutes {
            structural.append(.missingProtectedRest(have: rest, floor: policy.restFloorMinutes))
        }
        if switches > policy.maxContextSwitches { structural.append(.tooManySwitches(count: switches)) }
        let high = input.items.filter(\.isHighEnergy).count
        if high > policy.maxHighEnergyItems { structural.append(.clusteredHighEnergy(count: high)) }
        if !structural.isEmpty, state.rank < LoadState.tight.rank, load > 0 { state = .tight }
        reasons += structural

        return CapacityAssessment(availableMinutes: available, fixedWorkMinutes: fixed, restMinutes: rest,
                                  discretionaryMinutes: discretionary, bufferMinutes: buffer,
                                  committableMinutes: max(0, committable), loadMinutes: load,
                                  loadRatio: ratio, state: state, reasons: reasons)
    }

    static func contextSwitches(_ items: [CapacityItem]) -> Int {
        zip(items, items.dropFirst()).filter { $0.context != $1.context }.count
    }
}

// MARK: - 過載提案（只產生建議，不改動計畫）

public struct OverloadProposal: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case useBuffer, shrink, moveToTomorrow, cancelToday
    }
    public var id: String { kind.rawValue }
    public let kind: Kind
    public let itemIDs: [UUID]
    public let newMinutes: [UUID: Int]
    public let freedMinutes: Int
    public let explanation: String
}

public enum OverloadAdvisor {
    /// 依「最小改動」排序：先暫用緩衝，再縮小，再移到明日，最後才是取消今日。鎖定項永遠不動。
    public static func proposals(for input: CapacityInput, assessment: CapacityAssessment) -> [OverloadProposal] {
        let over = assessment.overloadMinutes
        guard over > 0 else { return [] }
        var result: [OverloadProposal] = []
        let movable = input.items.filter { !$0.isLocked && $0.minutes > 0 }

        if over <= assessment.bufferMinutes {
            result.append(OverloadProposal(kind: .useBuffer, itemIDs: [], newMinutes: [:], freedMinutes: over,
                                           explanation: "暫時動用 \(formatDuration(over)) 緩衝，今天就沒有應變空間。"))
        }

        // 縮小：由大到小砍半（最少留 10 分），直到補足
        var freed = 0
        var shrunk: [UUID: Int] = [:]
        for item in movable.sorted(by: { $0.minutes > $1.minutes }) where freed < over {
            let target = max(10, item.minutes / 2)
            guard target < item.minutes else { continue }
            shrunk[item.id] = target
            freed += item.minutes - target
        }
        if !shrunk.isEmpty {
            result.append(OverloadProposal(kind: .shrink, itemIDs: Array(shrunk.keys).sorted { $0.uuidString < $1.uuidString },
                                           newMinutes: shrunk, freedMinutes: freed,
                                           explanation: "把 \(shrunk.count) 項改成縮小版本，可騰出 \(formatDuration(freed))。"))
        }

        // 移到明日／取消今日：從清單後段（較低優先）開始
        var picked: [UUID] = []
        var moved = 0
        for item in movable.reversed() where moved < over {
            picked.append(item.id)
            moved += item.minutes
        }
        if !picked.isEmpty {
            result.append(OverloadProposal(kind: .moveToTomorrow, itemIDs: picked, newMinutes: [:], freedMinutes: moved,
                                           explanation: "把 \(picked.count) 項移到明天，保留今天的休息與緩衝。"))
            result.append(OverloadProposal(kind: .cancelToday, itemIDs: picked, newMinutes: [:], freedMinutes: moved,
                                           explanation: "今天先不做這 \(picked.count) 項（不會刪除，仍可再安排）。"))
        }
        return result
    }
}
