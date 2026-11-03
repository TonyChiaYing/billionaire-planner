import Foundation

// MARK: - 快速插入＋局部重排（PRD 7.6 / AC-08）

public enum SlotState: String, Sendable, Codable {
    case planned, inProgress, done, locked

    var isMovable: Bool { self == .planned }
}

public struct PlannedSlot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var start: Int        // 當日分鐘
    public var duration: Int
    public var state: SlotState

    public init(id: UUID = UUID(), title: String, start: Int, duration: Int, state: SlotState = .planned) {
        self.id = id
        self.title = title
        self.start = start
        self.duration = max(1, duration)
        self.state = state
    }

    public var end: Int { start + duration }
    func overlaps(_ s: Int, _ e: Int) -> Bool { start < e && end > s }
}

public enum ReplanChoice: String, Sendable, CaseIterable, Codable {
    case keep, shorten, postpone, moveToTomorrow

    public var label: String {
        switch self {
        case .keep: "保留（與插入重疊）"
        case .shorten: "縮短"
        case .postpone: "延後"
        case .moveToTomorrow: "移至明日"
        }
    }
}

public struct ReplanOption: Sendable, Equatable {
    public let choice: ReplanChoice
    public let newStart: Int?
    public let newDuration: Int?

    public var summary: String {
        switch choice {
        case .keep: "維持原時間"
        case .moveToTomorrow: "移到明天"
        case .shorten, .postpone:
            "\(formatMinute(newStart ?? 0))–\(formatMinute((newStart ?? 0) + (newDuration ?? 0)))"
        }
    }
}

public struct ReplanChange: Sendable, Equatable, Identifiable {
    public var id: UUID { slotID }
    public let slotID: UUID
    public let title: String
    public let originalStart: Int
    public let originalDuration: Int
    public let options: [ReplanOption]
    public var selected: ReplanChoice

    public var selectedOption: ReplanOption? { options.first { $0.choice == selected } }
}

public struct ReplanPreview: Sendable, Equatable {
    public let insertStart: Int
    public let insertDuration: Int
    public var changes: [ReplanChange]
    /// 與插入重疊但不能動的項目（已完成、進行中、鎖定）
    public let immovableConflicts: [UUID]

    public var hasConflicts: Bool { !changes.isEmpty || !immovableConflicts.isEmpty }
}

public enum LocalReplanner {
    /// 只處理和插入時段重疊、且可移動的項目；其他一律不動。
    public static func preview(slots: [PlannedSlot], insertStart: Int, insertDuration: Int,
                               dayEnd: Int = 24 * 60, minimumMinutes: Int = 10) -> ReplanPreview {
        let ws = insertStart, we = insertStart + max(1, insertDuration)
        let overlapping = slots.filter { $0.overlaps(ws, we) }.sorted { $0.start < $1.start }
        let affected = overlapping.filter { $0.state.isMovable }
        let immovable = overlapping.filter { !$0.state.isMovable }.map(\.id)

        // 佔用：所有不受影響或不可移動的項目＋插入時段；之後的延後提案逐一加入
        var occupied: [(Int, Int)] = slots.filter { s in !affected.contains { $0.id == s.id } }.map { ($0.start, $0.end) }
        occupied.append((ws, we))

        var changes: [ReplanChange] = []
        for slot in affected {
            var options: [ReplanOption] = []
            // 延後：插入結束之後第一個放得下的空檔
            if let gap = firstGap(after: we, length: slot.duration, occupied: occupied, dayEnd: dayEnd) {
                options.append(ReplanOption(choice: .postpone, newStart: gap, newDuration: slot.duration))
            }
            // 縮短：保留不與插入重疊的較長一段
            let before = max(0, ws - slot.start)
            let after = max(0, slot.end - we)
            if max(before, after) >= minimumMinutes {
                options.append(before >= after
                    ? ReplanOption(choice: .shorten, newStart: slot.start, newDuration: before)
                    : ReplanOption(choice: .shorten, newStart: we, newDuration: after))
            }
            options.append(ReplanOption(choice: .moveToTomorrow, newStart: nil, newDuration: nil))
            options.append(ReplanOption(choice: .keep, newStart: slot.start, newDuration: slot.duration))

            let preferred = options.first { $0.choice == .postpone }
                ?? options.first { $0.choice == .shorten }
                ?? options.first { $0.choice == .moveToTomorrow }!
            if let s = preferred.newStart, let d = preferred.newDuration { occupied.append((s, s + d)) }
            changes.append(ReplanChange(slotID: slot.id, title: slot.title, originalStart: slot.start,
                                        originalDuration: slot.duration, options: options, selected: preferred.choice))
        }
        return ReplanPreview(insertStart: ws, insertDuration: we - ws, changes: changes, immovableConflicts: immovable)
    }

    /// 純函式：回傳套用後的時段；移至明日的項目以 `movedToTomorrow` 回報，不刪除。
    public static func apply(_ preview: ReplanPreview, to slots: [PlannedSlot]) -> (slots: [PlannedSlot], movedToTomorrow: [UUID]) {
        var moved: [UUID] = []
        var result: [PlannedSlot] = []
        for slot in slots {
            guard let change = preview.changes.first(where: { $0.slotID == slot.id }),
                  let option = change.selectedOption else {
                result.append(slot)
                continue
            }
            switch option.choice {
            case .keep:
                result.append(slot)
            case .moveToTomorrow:
                moved.append(slot.id)
            case .shorten, .postpone:
                var s = slot
                s.start = option.newStart ?? slot.start
                s.duration = option.newDuration ?? slot.duration
                result.append(s)
            }
        }
        return (result, moved)
    }

    static func firstGap(after start: Int, length: Int, occupied: [(Int, Int)], dayEnd: Int) -> Int? {
        var candidate = start
        let sorted = occupied.sorted { $0.0 < $1.0 }
        var changed = true
        while changed {
            changed = false
            for (s, e) in sorted where s < candidate + length && e > candidate {
                candidate = e
                changed = true
            }
        }
        return candidate + length <= dayEnd ? candidate : nil
    }
}
