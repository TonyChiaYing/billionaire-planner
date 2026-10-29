import Foundation
import SwiftData
import SwiftUI

// MARK: - 任務脈絡標籤（時間塊與原則共用）

enum ContextTag: String, CaseIterable, Identifiable {
    case strategy = "#戰略規劃"
    case finance = "#財務決策"
    case deep = "#深度工作"
    case buffer = "#緩衝/雜務"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .strategy: .assetGreen
        case .finance: .yellow
        case .deep: .cyan
        case .buffer: .guardGray
        }
    }

    static func color(_ raw: String) -> Color { ContextTag(rawValue: raw)?.color ?? .guardGray }
}

func hhmm(_ minuteOfDay: Int) -> String {
    String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
}

// MARK: - 巴菲特 5/25

@Model
final class RichGoal {
    var id: UUID = UUID()
    var title: String = ""
    var isTopFive: Bool = false
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date? = nil

    init(title: String) { self.title = title }

    /// 佔用 Top 5 名額中（完成後釋出名額）
    var isActive: Bool { isTopFive && !isCompleted }
}

// MARK: - 馬斯克時間塊

@Model
final class BrainDumpItem {
    var id: UUID = UUID()
    var title: String = ""
    var tag: String = ContextTag.deep.rawValue
    var goalTitle: String? = nil
    var createdAt: Date = Date()

    init(title: String, tag: String, goalTitle: String?) {
        self.title = title
        self.tag = tag
        self.goalTitle = goalTitle
    }
}

@Model
final class TimeBlock {
    var id: UUID = UUID()
    var taskTitle: String = ""
    var tag: String = ContextTag.deep.rawValue
    var goalTitle: String? = nil
    var day: Date = Date()          // 當天 00:00
    var startMinute: Int = 540      // 自 00:00 起算的分鐘數
    var durationMinutes: Int = 15
    var isDone: Bool = false

    init(taskTitle: String, tag: String, goalTitle: String?, day: Date, startMinute: Int, durationMinutes: Int) {
        self.taskTitle = taskTitle
        self.tag = tag
        self.goalTitle = goalTitle
        self.day = day
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
    }

    var endMinute: Int { startMinute + durationMinutes }
    var startDate: Date { Calendar.current.date(byAdding: .minute, value: startMinute, to: day) ?? day }
}

// MARK: - 達利奧原則

@Model
final class PrincipleLog {
    var id: UUID = UUID()
    var painPoint: String = ""
    var causeType: String = "系統流程"   // 人 / 系統流程
    var rootCause: String = ""
    var concretePrinciple: String = ""
    var tag: String = ContextTag.strategy.rawValue
    var createdAt: Date = Date()

    init(painPoint: String, causeType: String, rootCause: String, concretePrinciple: String, tag: String) {
        self.painPoint = painPoint
        self.causeType = causeType
        self.rootCause = rootCause
        self.concretePrinciple = concretePrinciple
        self.tag = tag
    }
}

// MARK: - 蓋茲思考週

@Model
final class ThinkSession {
    var id: UUID = UUID()
    var topic: String = ""
    var notes: String = ""
    var startedAt: Date = Date()
    var plannedEnd: Date = Date()
    var endedAt: Date? = nil

    init(topic: String, hours: Int) {
        self.topic = topic
        self.startedAt = .now
        self.plannedEnd = .now.addingTimeInterval(TimeInterval(hours * 3600))
    }
}
