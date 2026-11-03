import Foundation
import SwiftData

// v1.0.0 已出貨的 schema，原封不動保留，只用來「讀取備份副本」做遷移。
// ⚠️ 不可修改欄位，否則無法開啟 v1 store。

@Model
final class RichGoal {
    var id: UUID = UUID()
    var title: String = ""
    var isTopFive: Bool = false
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date? = nil

    init(title: String) { self.title = title }
}

@Model
final class BrainDumpItem {
    var id: UUID = UUID()
    var title: String = ""
    var tag: String = "#深度工作"
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
    var tag: String = "#深度工作"
    var goalTitle: String? = nil
    var day: Date = Date()
    var startMinute: Int = 540
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
}

@Model
final class PrincipleLog {
    var id: UUID = UUID()
    var painPoint: String = ""
    var causeType: String = "系統流程"
    var rootCause: String = ""
    var concretePrinciple: String = ""
    var tag: String = "#戰略規劃"
    var createdAt: Date = Date()

    init(painPoint: String, causeType: String, rootCause: String, concretePrinciple: String, tag: String) {
        self.painPoint = painPoint
        self.causeType = causeType
        self.rootCause = rootCause
        self.concretePrinciple = concretePrinciple
        self.tag = tag
    }
}

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

enum LegacyV1 {
    static var models: [any PersistentModel.Type] {
        [RichGoal.self, BrainDumpItem.self, TimeBlock.self, PrincipleLog.self, ThinkSession.self]
    }

    static func container(at url: URL, readOnly: Bool) throws -> ModelContainer {
        let schema = Schema(models)
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, allowsSave: !readOnly))
    }
}
