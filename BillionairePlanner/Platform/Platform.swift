import Foundation
import SwiftData
import UserNotifications
import PlannerCore

// MARK: - 設定（集中鍵值；View 用 @AppStorage 讀同一組鍵）

enum SettingKey {
    static let dayStart = "dayStartMinute"
    static let dayEnd = "dayEndMinute"
    static let bufferPercent = "bufferPercent"
    static let restFloor = "restFloorMinutes"
    static let notifications = "notificationsEnabled"
    static let notificationDetails = "notificationShowsDetails"
    static let estimateSuggestions = "estimateSuggestionsEnabled"
    static let recoveryPrompts = "recoveryPromptsEnabled"
    static let weeklyPrompts = "weeklyPromptsEnabled"
    static let deadlinePrompts = "deadlinePromptsEnabled"
    static let fineTimeMode = "fineTimeMode"
    static let breakAfter = "focusBreakAfterMinutes"
    static let defaultEstimate = "defaultEstimateMinutes"
}

struct PlannerSettings {
    var dayStartMinute = 7 * 60
    var dayEndMinute = 22 * 60
    var bufferPercent = 20
    var restFloorMinutes = 30
    var notificationsEnabled = true
    var notificationShowsDetails = false
    var estimateSuggestions = true
    var recoveryPrompts = true
    var weeklyPrompts = true
    var deadlinePrompts = true
    var breakAfterMinutes = 50
    var defaultEstimateMinutes = 30

    static func load(_ d: UserDefaults = .standard) -> PlannerSettings {
        var s = PlannerSettings()
        func int(_ k: String, _ v: inout Int) { if d.object(forKey: k) != nil { v = d.integer(forKey: k) } }
        func bool(_ k: String, _ v: inout Bool) { if d.object(forKey: k) != nil { v = d.bool(forKey: k) } }
        int(SettingKey.dayStart, &s.dayStartMinute)
        int(SettingKey.dayEnd, &s.dayEndMinute)
        int(SettingKey.bufferPercent, &s.bufferPercent)
        int(SettingKey.restFloor, &s.restFloorMinutes)
        int(SettingKey.breakAfter, &s.breakAfterMinutes)
        int(SettingKey.defaultEstimate, &s.defaultEstimateMinutes)
        bool(SettingKey.notifications, &s.notificationsEnabled)
        bool(SettingKey.notificationDetails, &s.notificationShowsDetails)
        bool(SettingKey.estimateSuggestions, &s.estimateSuggestions)
        bool(SettingKey.recoveryPrompts, &s.recoveryPrompts)
        bool(SettingKey.weeklyPrompts, &s.weeklyPrompts)
        bool(SettingKey.deadlinePrompts, &s.deadlinePrompts)
        return s
    }

    var availableMinutes: Int { max(0, dayEndMinute - dayStartMinute) }
    var capacityPolicy: CapacityPolicy {
        CapacityPolicy(bufferRatio: Double(bufferPercent) / 100, restFloorMinutes: restFloorMinutes)
    }
}

enum AppInfo {
    static let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    /// 專案採四段版號（例：2.0.0.0），存在 CFBundleVersion
    static var display: String { build.split(separator: ".").count == 4 ? "v\(build)" : "v\(shortVersion) (\(build))" }
}

// MARK: - 通知（預設不顯示目標或工作內容）

@MainActor
enum Notifier {
    static func sync(_ context: ModelContext, now: Date = Date(), calendar: Calendar = .current) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let settings = PlannerSettings.load()
        guard settings.notificationsEnabled else { return }
        // 思考模式暫停非必要提醒；結束後只重排未來的，不補發過期的
        guard !context.all(ThinkingSession.self).contains(where: { $0.endedAt == nil }) else { return }

        let today = LocalDay(now, calendar: calendar)
        let days = [today, today.adding(days: 1, calendar: calendar)].map(\.description)
        let actions = Dictionary(context.all(ActionItem.self).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let requests: [UNNotificationRequest] = context.all(PlanPlacement.self)
            .filter { days.contains($0.dayKey) && $0.type == .timed && !$0.isDone && $0.isActiveToday && $0.startMinute != nil }
            .compactMap { p -> (Date, PlanPlacement)? in
                let at = p.day.instant(minute: p.startMinute ?? 0, in: calendar)
                return at > now ? (at, p) : nil
            }
            .sorted { $0.0 < $1.0 }
            .prefix(60)
            .map { at, p in
                let content = UNMutableNotificationContent()
                if settings.notificationShowsDetails, let a = actions[p.actionID] {
                    content.title = a.title
                    content.body = "預計 \(p.durationMinutes ?? a.estimateMinutes ?? 30) 分鐘"
                } else {
                    content.title = "億萬計畫"
                    content.body = "有一個安排即將開始"
                }
                content.sound = .default
                let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: at)
                return UNNotificationRequest(identifier: p.id.uuidString, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            }
        guard !requests.isEmpty else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            requests.forEach { center.add($0) }
        }
    }
}

// MARK: - 匯出（JSON，完全在本機）

@MainActor
enum DataExporter {
    static func json(_ c: ModelContext) -> Data {
        let iso = ISO8601DateFormatter()
        func d(_ date: Date?) -> Any { date.map { iso.string(from: $0) } ?? NSNull() }
        func u(_ id: UUID?) -> Any { id?.uuidString ?? NSNull() }
        func o<T>(_ v: T?) -> Any { v.map { $0 as Any } ?? NSNull() }
        var root: [String: Any] = ["app": "BillionairePlanner", "version": AppInfo.display, "exportedAt": iso.string(from: Date())]
        root["goals"] = c.all(Goal.self).map {
            ["id": $0.id.uuidString, "title": $0.title, "outcome": $0.outcomeDescription, "horizon": $0.horizonRaw,
             "status": $0.statusRaw, "isFocus": $0.isFocus, "focusRank": $0.focusRank, "deadline": d($0.deadline),
             "createdAt": d($0.createdAt), "completedAt": d($0.completedAt), "cycle": $0.cycleNumber,
             "outcomeTarget": o($0.outcomeTarget), "outcomeUnit": $0.outcomeUnit] as [String: Any]
        }
        root["milestones"] = c.all(Milestone.self).map {
            ["id": $0.id.uuidString, "goalID": $0.goalID.uuidString, "title": $0.title, "targetDate": d($0.targetDate),
             "completedAt": d($0.completedAt)] as [String: Any]
        }
        root["strategies"] = c.all(Strategy.self).map {
            ["id": $0.id.uuidString, "goalID": $0.goalID.uuidString, "title": $0.title, "status": $0.statusRaw,
             "startedAt": d($0.startedAt), "endedAt": d($0.endedAt), "reason": $0.decisionReason] as [String: Any]
        }
        root["actions"] = c.all(ActionItem.self).map {
            ["id": $0.id.uuidString, "goalID": u($0.goalID), "strategyID": u($0.strategyID), "kind": $0.kindRaw,
             "title": $0.title, "status": $0.statusRaw, "estimate": o($0.estimateMinutes),
             "actualMinutes": $0.actualMinutes, "createdAt": d($0.createdAt), "completedAt": d($0.completedAt),
             "carryoverCount": $0.carryoverCount] as [String: Any]
        }
        root["placements"] = c.all(PlanPlacement.self).map {
            ["id": $0.id.uuidString, "actionID": $0.actionID.uuidString, "day": $0.dayKey, "type": $0.typeRaw,
             "start": o($0.startMinute), "duration": o($0.durationMinutes), "done": $0.isDone,
             "disposition": o($0.dispositionRaw)] as [String: Any]
        }
        root["evidence"] = c.all(OutcomeEvidence.self).map {
            ["id": $0.id.uuidString, "goalID": $0.goalID.uuidString, "kind": $0.kindRaw, "value": o($0.value),
             "note": $0.note, "recordedAt": d($0.recordedAt), "cycle": $0.cycleNumber] as [String: Any]
        }
        root["deadlineRevisions"] = c.all(DeadlineRevision.self).map {
            ["goalID": $0.goalID.uuidString, "old": d($0.oldDeadline), "new": d($0.newDeadline),
             "changedAt": d($0.changedAt), "reason": $0.reason] as [String: Any]
        }
        root["recoveryEpisodes"] = c.all(RecoveryEpisode.self).map {
            ["goalID": $0.goalID.uuidString, "cycle": $0.cycleNumber, "status": $0.statusRaw, "signals": $0.signalsJSON,
             "chosen": o($0.chosenOptionRaw), "openedAt": d($0.openedAt), "closedAt": d($0.closedAt)] as [String: Any]
        }
        root["dailyReviews"] = c.all(DailyReview.self).map {
            ["day": $0.dayKey, "workClosedAt": d($0.workClosedAt), "eveningClosedAt": d($0.eveningClosedAt),
             "energy": o($0.energy), "blockers": $0.blockers, "isRestDay": $0.isRestDay, "note": $0.note] as [String: Any]
        }
        root["principles"] = c.all(Principle.self).map {
            ["text": $0.text, "painPoint": $0.painPoint, "causeType": $0.causeType, "rootCause": $0.rootCause,
             "tag": $0.contextTag, "goalID": u($0.goalID), "createdAt": d($0.createdAt)] as [String: Any]
        }
        root["thinkingSessions"] = c.all(ThinkingSession.self).map {
            ["topic": $0.topic, "notes": $0.notes, "startedAt": d($0.startedAt), "endedAt": d($0.endedAt),
             "goalID": u($0.goalID)] as [String: Any]
        }
        return (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}
