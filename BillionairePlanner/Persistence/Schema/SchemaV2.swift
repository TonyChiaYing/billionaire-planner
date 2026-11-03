import Foundation
import SwiftData
import PlannerCore

// v2 資料模型（PRD 6）。關聯一律用穩定 UUID，不用標題；不使用 cascade delete，歷史以封存保留。
// 列舉存成 rawValue 字串，未來加值不需破壞性遷移。

enum GoalHorizon: String, CaseIterable, Identifiable, Codable {
    case short, medium, long
    var id: String { rawValue }
    var label: String {
        switch self {
        case .short: "短期（數週）"
        case .medium: "中期（數月）"
        case .long: "長期（一年以上）"
        }
    }
    var shortLabel: String {
        switch self {
        case .short: "短期"
        case .medium: "中期"
        case .long: "長期"
        }
    }
}

enum StrategyStatus: String, CaseIterable, Codable {
    case proposed, active, paused, retired, succeeded
    var label: String {
        switch self {
        case .proposed: "構想中"
        case .active: "使用中"
        case .paused: "暫停"
        case .retired: "已替換"
        case .succeeded: "已奏效"
        }
    }
}

enum ActionStatus: String, CaseIterable, Codable {
    case inbox, ready, planned, inProgress, done, cancelled, waiting
    var isOpen: Bool { [.inbox, .ready, .planned, .inProgress, .waiting].contains(self) }
    var label: String {
        switch self {
        case .inbox: "未安排"
        case .ready: "可執行"
        case .planned: "已安排"
        case .inProgress: "進行中"
        case .done: "完成"
        case .cancelled: "不再需要"
        case .waiting: "等待中"
        }
    }
}

enum PlacementType: String, Codable { case ordered, period, timed }

enum DayPeriod: String, CaseIterable, Identifiable, Codable {
    case morning, afternoon, evening
    var id: String { rawValue }
    var label: String {
        switch self {
        case .morning: "上午"
        case .afternoon: "下午"
        case .evening: "晚上"
        }
    }
    static func of(minute: Int) -> DayPeriod { minute < 12 * 60 ? .morning : (minute < 18 * 60 ? .afternoon : .evening) }
}

enum Commitment: String, Codable { case draft, accepted, locked }

enum BlockKind: String, CaseIterable, Identifiable, Codable {
    case work, rest, meal, commute, sleep
    var id: String { rawValue }
    var label: String {
        switch self {
        case .work: "固定工作"
        case .rest: "休息"
        case .meal: "用餐"
        case .commute: "通勤"
        case .sleep: "睡眠邊界"
        }
    }
    var symbol: String {
        switch self {
        case .work: "briefcase"
        case .rest: "cup.and.saucer"
        case .meal: "fork.knife"
        case .commute: "tram"
        case .sleep: "moon.zzz"
        }
    }
    var isProtected: Bool { self != .work }
}

enum EvidenceKind: String, CaseIterable, Identifiable, Codable {
    case numeric, checkpoint, note
    var id: String { rawValue }
    var label: String {
        switch self {
        case .numeric: "數值"
        case .checkpoint: "檢查點"
        case .note: "文字紀錄"
        }
    }
}

enum RecoveryStatus: String, Codable { case open, resolved, snoozed, dismissed }

// MARK: - 目標主幹

@Model
final class Goal {
    var id: UUID = UUID()
    var title: String = ""
    var outcomeDescription: String = ""
    var horizonRaw: String = GoalHorizon.medium.rawValue
    var statusRaw: String = GoalLifecycle.draft.rawValue
    var isFocus: Bool = false
    var focusRank: Int = 99
    var createdAt: Date = Date()
    var activatedAt: Date? = nil
    var completedAt: Date? = nil
    var archivedAt: Date? = nil
    var deadline: Date? = nil              // 由 DeadlineRevision 投影的快取
    var outcomeTarget: Double? = nil
    var outcomeUnit: String = ""
    var cycleNumber: Int = 1
    var cycleStartedAt: Date = Date()
    var pausedUntil: Date? = nil
    var isWaiting: Bool = false
    var lastActivityAt: Date? = nil
    var migratedFromV1: Bool = false

    init(title: String, horizon: GoalHorizon, outcomeDescription: String) {
        self.title = title
        self.horizonRaw = horizon.rawValue
        self.outcomeDescription = outcomeDescription
    }

    var horizon: GoalHorizon {
        get { GoalHorizon(rawValue: horizonRaw) ?? .medium }
        set { horizonRaw = newValue.rawValue }
    }
    var status: GoalLifecycle {
        get { GoalLifecycle(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }
    var isOpen: Bool { status == .draft || status == .active || status == .paused }
}

@Model
final class Milestone {
    var id: UUID = UUID()
    var goalID: UUID = UUID()
    var title: String = ""
    var definitionOfDone: String = ""
    var targetDate: Date? = nil
    var order: Int = 0
    var completedAt: Date? = nil
    var createdAt: Date = Date()
    var isArchived: Bool = false

    init(goalID: UUID, title: String, targetDate: Date?, order: Int) {
        self.goalID = goalID
        self.title = title
        self.targetDate = targetDate
        self.order = order
    }
}

@Model
final class Strategy {
    var id: UUID = UUID()
    var goalID: UUID = UUID()
    var title: String = ""
    var hypothesis: String = ""
    var statusRaw: String = StrategyStatus.active.rawValue
    var startedAt: Date = Date()
    var endedAt: Date? = nil
    var decisionReason: String = ""

    init(goalID: UUID, title: String, hypothesis: String = "") {
        self.goalID = goalID
        self.title = title
        self.hypothesis = hypothesis
    }

    var status: StrategyStatus {
        get { StrategyStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class ActionItem {
    var id: UUID = UUID()
    var goalID: UUID? = nil
    var strategyID: UUID? = nil
    var milestoneID: UUID? = nil
    var kindRaw: String = ItemContext.personal.rawValue
    var title: String = ""
    var notes: String = ""
    var statusRaw: String = ActionStatus.inbox.rawValue
    var estimateMinutes: Int? = nil
    var estimateSource: String = ""          // user / suggestion
    var minimumVersion: String = ""          // 縮小版本的描述
    var minimumMinutes: Int? = nil
    var actualMinutes: Int = 0
    var isHighEnergy: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date? = nil
    var sourceActionID: UUID? = nil          // 跨日延續來源
    var carryoverCount: Int = 0
    var legacySourceID: UUID? = nil          // v1 來源（冪等）
    var legacyTag: String = ""
    var urgency: Int = 0                     // 0 一般 1 急 2 很急

    init(title: String, kind: ItemContext, goalID: UUID? = nil, strategyID: UUID? = nil) {
        self.title = title
        self.kindRaw = kind.rawValue
        self.goalID = goalID
        self.strategyID = strategyID
    }

    var kind: ItemContext {
        get { ItemContext(rawValue: kindRaw) ?? .personal }
        set { kindRaw = newValue.rawValue }
    }
    var status: ActionStatus {
        get { ActionStatus(rawValue: statusRaw) ?? .inbox }
        set { statusRaw = newValue.rawValue }
    }
}

/// 行動在某一天的安排；移動不複製 Action 身分
@Model
final class PlanPlacement {
    var id: UUID = UUID()
    var actionID: UUID = UUID()
    var dayKey: String = ""                  // LocalDay "yyyy-MM-dd"
    var timeZoneID: String = TimeZone.current.identifier
    var typeRaw: String = PlacementType.ordered.rawValue
    var order: Int = 0
    var periodRaw: String? = nil
    var startMinute: Int? = nil
    var durationMinutes: Int? = nil
    var commitmentRaw: String = Commitment.accepted.rawValue
    var isDone: Bool = false
    var startedAt: Date? = nil
    var dispositionRaw: String? = nil
    var dispositionAt: Date? = nil
    var createdAt: Date = Date()
    var legacySourceID: UUID? = nil

    init(actionID: UUID, day: LocalDay, order: Int) {
        self.actionID = actionID
        self.dayKey = day.description
        self.order = order
    }

    var day: LocalDay { LocalDay(dayKey) ?? LocalDay.today() }
    var type: PlacementType {
        get { PlacementType(rawValue: typeRaw) ?? .ordered }
        set { typeRaw = newValue.rawValue }
    }
    var period: DayPeriod? {
        get { periodRaw.flatMap(DayPeriod.init(rawValue:)) }
        set { periodRaw = newValue?.rawValue }
    }
    var commitment: Commitment {
        get { Commitment(rawValue: commitmentRaw) ?? .accepted }
        set { commitmentRaw = newValue.rawValue }
    }
    var disposition: Disposition? {
        get { dispositionRaw.flatMap(Disposition.init(rawValue:)) }
        set { dispositionRaw = newValue?.rawValue }
    }
    var isLocked: Bool { commitment == .locked }
    /// 仍佔用今日容量（未處置、未完成）
    var isActiveToday: Bool { disposition == nil || disposition == .startNow || disposition == .shrink }
}

// MARK: - 工作模板與日骨架

@Model
final class WorkTemplate {
    var id: UUID = UUID()
    var name: String = "平日"
    var weekdaysRaw: String = "2,3,4,5,6"    // Calendar.weekday：1=日 … 7=六
    var isActive: Bool = true
    var createdAt: Date = Date()

    init(name: String) { self.name = name }

    var weekdays: Set<Int> {
        get { Set(weekdaysRaw.split(separator: ",").compactMap { Int($0) }) }
        set { weekdaysRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }
}

@Model
final class WorkTemplateItem {
    var id: UUID = UUID()
    var templateID: UUID = UUID()
    var kindRaw: String = BlockKind.work.rawValue
    var title: String = ""
    var startMinute: Int = 540
    var durationMinutes: Int = 60
    var order: Int = 0

    init(templateID: UUID, kind: BlockKind, title: String, startMinute: Int, durationMinutes: Int, order: Int) {
        self.templateID = templateID
        self.kindRaw = kind.rawValue
        self.title = title
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.order = order
    }

    var kind: BlockKind { BlockKind(rawValue: kindRaw) ?? .work }
}

/// 某一天的固定區段實例（工作、休息、用餐…）；修改它不會反寫模板
@Model
final class DayBlock {
    var id: UUID = UUID()
    var dayKey: String = ""
    var kindRaw: String = BlockKind.work.rawValue
    var title: String = ""
    var startMinute: Int = 540
    var durationMinutes: Int = 60
    var sourceTemplateItemID: UUID? = nil
    var isOverride: Bool = false
    var isRemoved: Bool = false              // 當日移除（保留紀錄）

    init(day: LocalDay, kind: BlockKind, title: String, startMinute: Int, durationMinutes: Int) {
        self.dayKey = day.description
        self.kindRaw = kind.rawValue
        self.title = title
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
    }

    var kind: BlockKind {
        get { BlockKind(rawValue: kindRaw) ?? .work }
        set { kindRaw = newValue.rawValue }
    }
    var endMinute: Int { startMinute + durationMinutes }
}

// MARK: - 成果、回顧、恢復

@Model
final class OutcomeEvidence {
    var id: UUID = UUID()
    var goalID: UUID = UUID()
    var milestoneID: UUID? = nil
    var strategyID: UUID? = nil
    var actionID: UUID? = nil
    var kindRaw: String = EvidenceKind.note.rawValue
    var value: Double? = nil
    var unit: String = ""
    var note: String = ""
    var recordedAt: Date = Date()
    var cycleNumber: Int = 1
    var isReversed: Bool = false             // 只透過稽核紀錄反轉，不刪除

    init(goalID: UUID, kind: EvidenceKind, value: Double?, note: String, cycleNumber: Int) {
        self.goalID = goalID
        self.kindRaw = kind.rawValue
        self.value = value
        self.note = note
        self.cycleNumber = cycleNumber
    }

    var kind: EvidenceKind { EvidenceKind(rawValue: kindRaw) ?? .note }
}

@Model
final class DailyReview {
    var id: UUID = UUID()
    var dayKey: String = ""
    var templateAppliedAt: Date? = nil
    var workClosedAt: Date? = nil
    var squeezedNote: String = ""
    var eveningClosedAt: Date? = nil
    var energy: Int? = nil                   // 1–5
    var blockers: String = ""
    var blockedGoalIDsRaw: String = ""
    var isRestDay: Bool = false
    var note: String = ""
    var draftGeneratedAt: Date? = nil
    var draftAcceptedAt: Date? = nil

    init(day: LocalDay) { self.dayKey = day.description }

    var blockedGoalIDs: [UUID] {
        get { blockedGoalIDsRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
        set { blockedGoalIDsRaw = newValue.map(\.uuidString).joined(separator: ",") }
    }
}

@Model
final class WeeklyReview {
    var id: UUID = UUID()
    var weekStartKey: String = ""
    var completedAt: Date? = nil
    var nextWeekCapacityNote: String = ""
    var note: String = ""
    var snoozedUntil: Date? = nil

    init(weekStart: LocalDay) { self.weekStartKey = weekStart.description }
}

@Model
final class StrategyDecision {
    var id: UUID = UUID()
    var goalID: UUID = UUID()
    var strategyID: UUID = UUID()
    var decision: String = "continue"        // continue / tweak / replace / pause
    var reason: String = ""
    var decidedAt: Date = Date()
    var weeklyReviewID: UUID? = nil

    init(goalID: UUID, strategyID: UUID, decision: String, reason: String) {
        self.goalID = goalID
        self.strategyID = strategyID
        self.decision = decision
        self.reason = reason
    }
}

@Model
final class RecoveryEpisode {
    var id: UUID = UUID()
    var goalID: UUID = UUID()
    var cycleNumber: Int = 1
    var signalsJSON: String = "[]"
    var statusRaw: String = RecoveryStatus.open.rawValue
    var openedAt: Date = Date()
    var closedAt: Date? = nil
    var chosenOptionRaw: String? = nil
    var reason: String = ""
    var snoozeUntil: Date? = nil
    var snapshotDeadline: Date? = nil
    var snapshotStrategyID: UUID? = nil

    init(goalID: UUID, cycleNumber: Int, signals: [LagSignal]) {
        self.goalID = goalID
        self.cycleNumber = cycleNumber
        self.signalsJSON = (try? String(data: JSONEncoder().encode(signals), encoding: .utf8)) ?? "[]"
    }

    var signals: [LagSignal] {
        (try? JSONDecoder().decode([LagSignal].self, from: Data(signalsJSON.utf8))) ?? []
    }
    var status: RecoveryStatus {
        get { RecoveryStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }
    var chosenOption: RecoveryOption? { chosenOptionRaw.flatMap(RecoveryOption.init(rawValue:)) }
}

/// 只增不改
@Model
final class DeadlineRevision {
    var id: UUID = UUID()
    var goalID: UUID = UUID()
    var oldDeadline: Date? = nil
    var newDeadline: Date? = nil
    var changedAt: Date = Date()
    var reason: String = ""
    var recoveryEpisodeID: UUID? = nil

    init(goalID: UUID, oldDeadline: Date?, newDeadline: Date?, reason: String, recoveryEpisodeID: UUID?) {
        self.goalID = goalID
        self.oldDeadline = oldDeadline
        self.newDeadline = newDeadline
        self.reason = reason
        self.recoveryEpisodeID = recoveryEpisodeID
    }
}

@Model
final class Principle {
    var id: UUID = UUID()
    var painPoint: String = ""
    var causeType: String = "系統流程"
    var rootCause: String = ""
    var text: String = ""
    var contextTag: String = ""
    var goalID: UUID? = nil
    var strategyID: UUID? = nil
    var createdAt: Date = Date()
    var legacySourceID: UUID? = nil

    init(text: String, painPoint: String = "", causeType: String = "系統流程", rootCause: String = "") {
        self.text = text
        self.painPoint = painPoint
        self.causeType = causeType
        self.rootCause = rootCause
    }
}

@Model
final class ThinkingSession {
    var id: UUID = UUID()
    var topic: String = ""
    var notes: String = ""
    var startedAt: Date = Date()
    var plannedEnd: Date = Date()
    var endedAt: Date? = nil
    var goalID: UUID? = nil
    var strategyID: UUID? = nil
    var legacySourceID: UUID? = nil

    init(topic: String, hours: Int) {
        self.topic = topic
        self.startedAt = .now
        self.plannedEnd = .now.addingTimeInterval(TimeInterval(hours * 3600))
    }
}

/// 介入紀錄（抑制與冷卻用）
@Model
final class InterventionEvent {
    var id: UUID = UUID()
    var key: String = ""
    var levelRaw: String = InterventionLevel.daily.rawValue
    var outcomeRaw: String = InterventionOutcome.shown.rawValue
    var at: Date = Date()
    var severity: Int = 1
    var snoozeUntil: Date? = nil
    var dayKey: String = ""

    init(key: String, level: InterventionLevel, outcome: InterventionOutcome, severity: Int, day: LocalDay) {
        self.key = key
        self.levelRaw = level.rawValue
        self.outcomeRaw = outcome.rawValue
        self.severity = severity
        self.dayKey = day.description
    }

    var record: InterventionRecord {
        InterventionRecord(key: key, level: InterventionLevel(rawValue: levelRaw) ?? .daily,
                           outcome: InterventionOutcome(rawValue: outcomeRaw) ?? .shown, at: at,
                           severity: severity, snoozeUntil: snoozeUntil, planningDay: LocalDay(dayKey))
    }
}

/// v1 遷移執行紀錄
@Model
final class MigrationRun {
    var id: UUID = UUID()
    var sourceVersion: String = "1.0.0"
    var startedAt: Date = Date()
    var completedAt: Date? = nil
    var backupPath: String = ""
    var reportJSON: String = ""
    var errorMessage: String = ""

    init(backupPath: String) { self.backupPath = backupPath }

    var report: MigrationReport? {
        try? JSONDecoder().decode(MigrationReport.self, from: Data(reportJSON.utf8))
    }
}

// MARK: - Versioned schema（之後的 v2.x 從這裡加 stage）

enum PlannerSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Goal.self, Milestone.self, Strategy.self, ActionItem.self, PlanPlacement.self, WorkTemplate.self,
         WorkTemplateItem.self, DayBlock.self, OutcomeEvidence.self, DailyReview.self, WeeklyReview.self,
         StrategyDecision.self, RecoveryEpisode.self, DeadlineRevision.self, Principle.self, ThinkingSession.self,
         InterventionEvent.self, MigrationRun.self]
    }
}

enum PlannerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PlannerSchemaV2.self] }
    static var stages: [MigrationStage] { [] }
}
