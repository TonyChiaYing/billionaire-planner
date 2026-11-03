import Foundation

// v1 → v2 映射規則（PRD 10 / migration-and-release.md）。純函式：輸入 v1 快照，輸出要建立的 v2 紀錄與報告。
// 冪等：以 legacy 來源 UUID 判斷是否已匯入；同一份 v1 資料跑幾次結果都一樣。

public struct LegacyGoal: Sendable, Equatable {
    public var id: UUID, title: String, isTopFive: Bool, isCompleted: Bool, createdAt: Date, completedAt: Date?
    public init(id: UUID, title: String, isTopFive: Bool, isCompleted: Bool, createdAt: Date, completedAt: Date?) {
        self.id = id; self.title = title; self.isTopFive = isTopFive; self.isCompleted = isCompleted
        self.createdAt = createdAt; self.completedAt = completedAt
    }
}

public struct LegacyDumpItem: Sendable, Equatable {
    public var id: UUID, title: String, tag: String, goalTitle: String?, createdAt: Date
    public init(id: UUID, title: String, tag: String, goalTitle: String?, createdAt: Date) {
        self.id = id; self.title = title; self.tag = tag; self.goalTitle = goalTitle; self.createdAt = createdAt
    }
}

public struct LegacyTimeBlock: Sendable, Equatable {
    public var id: UUID, taskTitle: String, tag: String, goalTitle: String?, day: Date
    public var startMinute: Int, durationMinutes: Int, isDone: Bool
    public init(id: UUID, taskTitle: String, tag: String, goalTitle: String?, day: Date, startMinute: Int,
                durationMinutes: Int, isDone: Bool) {
        self.id = id; self.taskTitle = taskTitle; self.tag = tag; self.goalTitle = goalTitle; self.day = day
        self.startMinute = startMinute; self.durationMinutes = durationMinutes; self.isDone = isDone
    }
}

public struct LegacyPrinciple: Sendable, Equatable {
    public var id: UUID, painPoint: String, causeType: String, rootCause: String, concretePrinciple: String
    public var tag: String, createdAt: Date
    public init(id: UUID, painPoint: String, causeType: String, rootCause: String, concretePrinciple: String,
                tag: String, createdAt: Date) {
        self.id = id; self.painPoint = painPoint; self.causeType = causeType; self.rootCause = rootCause
        self.concretePrinciple = concretePrinciple; self.tag = tag; self.createdAt = createdAt
    }
}

public struct LegacyThinkSession: Sendable, Equatable {
    public var id: UUID, topic: String, notes: String, startedAt: Date, plannedEnd: Date, endedAt: Date?
    public init(id: UUID, topic: String, notes: String, startedAt: Date, plannedEnd: Date, endedAt: Date?) {
        self.id = id; self.topic = topic; self.notes = notes; self.startedAt = startedAt
        self.plannedEnd = plannedEnd; self.endedAt = endedAt
    }
}

public struct LegacySnapshot: Sendable, Equatable {
    public var goals: [LegacyGoal] = []
    public var dumpItems: [LegacyDumpItem] = []
    public var timeBlocks: [LegacyTimeBlock] = []
    public var principles: [LegacyPrinciple] = []
    public var thinkSessions: [LegacyThinkSession] = []
    public init(goals: [LegacyGoal] = [], dumpItems: [LegacyDumpItem] = [], timeBlocks: [LegacyTimeBlock] = [],
                principles: [LegacyPrinciple] = [], thinkSessions: [LegacyThinkSession] = []) {
        self.goals = goals; self.dumpItems = dumpItems; self.timeBlocks = timeBlocks
        self.principles = principles; self.thinkSessions = thinkSessions
    }
}

// MARK: 輸出

public struct MigratedGoal: Sendable, Equatable {
    public var id: UUID, title: String, lifecycle: GoalLifecycle, isFocus: Bool, focusRank: Int
    public var createdAt: Date, completedAt: Date?
}

public struct MigratedAction: Sendable, Equatable {
    public var id: UUID, legacySourceID: UUID, title: String, legacyTag: String, goalID: UUID?
    public var createdAt: Date, isDone: Bool, completedAt: Date?
}

public struct MigratedPlacement: Sendable, Equatable {
    public var id: UUID, actionID: UUID, legacySourceID: UUID, day: LocalDay, startMinute: Int
    public var durationMinutes: Int, isDone: Bool
}

public struct UnlinkedReference: Sendable, Equatable, Codable {
    public var sourceID: UUID
    public var itemTitle: String
    public var goalTitle: String
    public var reason: String     // 找不到目標 / 有多個同名目標
}

public struct EntityCount: Sendable, Equatable, Codable {
    public var source = 0
    public var imported = 0
    public var alreadyPresent = 0
}

public struct MigrationReport: Sendable, Equatable, Codable {
    public var goals = EntityCount()
    public var dumpItems = EntityCount()
    public var timeBlocks = EntityCount()
    public var principles = EntityCount()
    public var thinkSessions = EntityCount()
    public var unlinked: [UnlinkedReference] = []
    public var focusOverflowGoalIDs: [UUID] = []
    public var warnings: [String] = []

    public var summaryLines: [String] {
        [("目標", goals), ("腦傾倒項", dumpItems), ("時間塊", timeBlocks), ("原則", principles), ("思考紀錄", thinkSessions)]
            .map { "\($0.0)：v1 共 \($0.1.source) 筆，本次匯入 \($0.1.imported) 筆，先前已匯入 \($0.1.alreadyPresent) 筆" }
    }
}

public struct MigrationPlan: Sendable, Equatable {
    public var goals: [MigratedGoal] = []
    public var actions: [MigratedAction] = []
    public var placements: [MigratedPlacement] = []
    public var principles: [LegacyPrinciple] = []
    public var thinkSessions: [LegacyThinkSession] = []
    public var report = MigrationReport()
}

public enum LegacyMigrationMapper {
    public static func normalize(_ title: String) -> String {
        title.precomposedStringWithCompatibilityMapping
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// TimeBlock 的 Action 用可重現的衍生 UUID，重跑不會產生不同 ID
    public static func derivedActionID(forBlock id: UUID) -> UUID {
        var b = id.uuid
        b.0 ^= 0xA5
        b.15 ^= 0x5A
        return UUID(uuid: b)
    }

    public static func plan(_ s: LegacySnapshot, alreadyImported: Set<UUID>, calendar: Calendar) -> MigrationPlan {
        var plan = MigrationPlan()
        var report = MigrationReport()

        // 目標：保留 UUID；Top 5 意圖最多 5 個成為焦點（依建立時間、ID 決定順序）
        let activeTop = s.goals.filter { $0.isTopFive && !$0.isCompleted }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        let focusIDs = Array(activeTop.prefix(FocusPolicy.hardLimit).map(\.id))
        report.focusOverflowGoalIDs = activeTop.dropFirst(FocusPolicy.hardLimit).map(\.id)
        if !report.focusOverflowGoalIDs.isEmpty {
            report.warnings.append("v1 有 \(activeTop.count) 個 Top 5 目標，前 5 個設為焦點，其餘保留為一般目標，請檢查。")
        }
        report.goals.source = s.goals.count
        for g in s.goals {
            if alreadyImported.contains(g.id) { report.goals.alreadyPresent += 1; continue }
            let rank = focusIDs.firstIndex(of: g.id)
            plan.goals.append(MigratedGoal(id: g.id, title: g.title,
                                           lifecycle: g.isCompleted ? .completed : .active,
                                           isFocus: rank != nil, focusRank: rank ?? 99,
                                           createdAt: g.createdAt, completedAt: g.isCompleted ? (g.completedAt ?? g.createdAt) : nil))
            report.goals.imported += 1
        }

        // 標題解析：只接受「正好一個」同名目標
        var byTitle: [String: [UUID]] = [:]
        for g in s.goals { byTitle[normalize(g.title), default: []].append(g.id) }
        func resolve(_ goalTitle: String?, sourceID: UUID, itemTitle: String) -> UUID? {
            guard let raw = goalTitle, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let matches = byTitle[normalize(raw)] ?? []
            if matches.count == 1 { return matches[0] }
            report.unlinked.append(UnlinkedReference(sourceID: sourceID, itemTitle: itemTitle, goalTitle: raw,
                                                     reason: matches.isEmpty ? "找不到這個目標" : "有 \(matches.count) 個同名目標"))
            return nil
        }

        report.dumpItems.source = s.dumpItems.count
        for d in s.dumpItems {
            if alreadyImported.contains(d.id) { report.dumpItems.alreadyPresent += 1; continue }
            plan.actions.append(MigratedAction(id: d.id, legacySourceID: d.id, title: d.title, legacyTag: d.tag,
                                               goalID: resolve(d.goalTitle, sourceID: d.id, itemTitle: d.title),
                                               createdAt: d.createdAt, isDone: false, completedAt: nil))
            report.dumpItems.imported += 1
        }

        // 每個時間塊各自一個 Action（不跨日期以標題合併）＋一個 PlanPlacement
        report.timeBlocks.source = s.timeBlocks.count
        for b in s.timeBlocks {
            if alreadyImported.contains(b.id) { report.timeBlocks.alreadyPresent += 1; continue }
            let day = LocalDay(b.day, calendar: calendar)
            let actionID = derivedActionID(forBlock: b.id)
            let doneAt = b.isDone ? day.instant(minute: b.startMinute + b.durationMinutes, in: calendar) : nil
            plan.actions.append(MigratedAction(id: actionID, legacySourceID: actionID, title: b.taskTitle, legacyTag: b.tag,
                                               goalID: resolve(b.goalTitle, sourceID: b.id, itemTitle: b.taskTitle),
                                               createdAt: day.start(in: calendar), isDone: b.isDone, completedAt: doneAt))
            plan.placements.append(MigratedPlacement(id: b.id, actionID: actionID, legacySourceID: b.id, day: day,
                                                     startMinute: b.startMinute, durationMinutes: max(1, b.durationMinutes),
                                                     isDone: b.isDone))
            report.timeBlocks.imported += 1
        }

        report.principles.source = s.principles.count
        for p in s.principles {
            if alreadyImported.contains(p.id) { report.principles.alreadyPresent += 1; continue }
            plan.principles.append(p)
            report.principles.imported += 1
        }
        report.thinkSessions.source = s.thinkSessions.count
        for t in s.thinkSessions {
            if alreadyImported.contains(t.id) { report.thinkSessions.alreadyPresent += 1; continue }
            plan.thinkSessions.append(t)
            report.thinkSessions.imported += 1
        }
        if !report.unlinked.isEmpty {
            report.warnings.append("有 \(report.unlinked.count) 個項目的目標名稱無法唯一對應，已保留為未連結，可在「目標」中手動連結。")
        }
        plan.report = report
        return plan
    }
}
