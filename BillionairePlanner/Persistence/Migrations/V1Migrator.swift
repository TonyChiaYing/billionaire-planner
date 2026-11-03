import Foundation
import SwiftData
import PlannerCore

/// v1 → v2 遷移（PRD 10 / AC-15）
/// 1. 先把 v1 整組 store 檔備份到 Backups/（不自動刪除）
/// 2. 只開「備份副本」讀取，v1 原檔完全不動 → 失敗或想退回 v1 都安全
/// 3. 以 legacy UUID 判斷已匯入項目 → 可重跑、不重複
/// 4. 一次儲存；之後用全新 context 重新讀取驗證筆數，才標記完成
@MainActor
struct V1Migrator {
    enum Outcome: Equatable {
        case noLegacyStore
        case alreadyCompleted
        case migrated(MigrationReport)
        case failed(String)
    }

    let v1Store: URL
    let backupRoot: URL
    let container: ModelContainer
    var calendar: Calendar = .current
    var now: () -> Date = { Date() }
    /// 測試用：在寫入一半時模擬中斷
    var interruptAfterGoals = false

    func runIfNeeded() -> Outcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: v1Store.path) else { return .noLegacyStore }
        let context = ModelContext(container)
        let runs = context.all(MigrationRun.self)
        if runs.contains(where: { $0.completedAt != nil }) { return .alreadyCompleted }

        // 1. 備份
        let stamp = ISO8601DateFormatter().string(from: now()).replacingOccurrences(of: ":", with: "-")
        let backupDir = backupRoot.appending(path: "v1-\(stamp)-\(UUID().uuidString.prefix(6))", directoryHint: .isDirectory)
        let backupStore = backupDir.appending(path: v1Store.lastPathComponent)
        do {
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
            for (src, dst) in zip(StoreLocation.family(of: v1Store), StoreLocation.family(of: backupStore))
            where fm.fileExists(atPath: src.path) {
                try fm.copyItem(at: src, to: dst)
            }
        } catch {
            return .failed("無法建立 v1 資料備份：\(error.localizedDescription)")
        }

        let run = MigrationRun(backupPath: backupDir.path)
        context.insert(run)
        try? context.save()

        // 2. 讀取備份副本
        let snapshot: LegacySnapshot
        do {
            snapshot = try readSnapshot(at: backupStore)
        } catch {
            run.errorMessage = "讀取 v1 資料失敗：\(error.localizedDescription)"
            try? context.save()
            return .failed(run.errorMessage)
        }

        // 3. 映射＋寫入
        let imported = alreadyImportedIDs(context)
        let plan = LegacyMigrationMapper.plan(snapshot, alreadyImported: imported, calendar: calendar)
        do {
            try apply(plan, into: context)
        } catch {
            context.rollback()
            run.errorMessage = "寫入 v2 失敗：\(error.localizedDescription)"
            try? context.save()
            return .failed(run.errorMessage)
        }
        if interruptAfterGoals { return .failed("模擬中斷") }

        // 4. 重新開啟驗證
        let verify = ModelContext(container)
        let ids = alreadyImportedIDs(verify)
        let expected = snapshot.goals.map(\.id) + snapshot.dumpItems.map(\.id) + snapshot.timeBlocks.map(\.id)
            + snapshot.principles.map(\.id) + snapshot.thinkSessions.map(\.id)
        let missing = expected.filter { !ids.contains($0) }
        guard missing.isEmpty else {
            run.errorMessage = "驗證失敗：有 \(missing.count) 筆沒有寫入"
            try? context.save()
            return .failed(run.errorMessage)
        }

        var report = plan.report
        if report.goals.imported + report.dumpItems.imported + report.timeBlocks.imported == 0, imported.isEmpty {
            report.warnings.append("v1 資料庫是空的。")
        }
        run.reportJSON = (try? String(data: JSONEncoder().encode(report), encoding: .utf8)) ?? ""
        run.completedAt = now()
        try? context.save()
        return .migrated(report)
    }

    func readSnapshot(at url: URL) throws -> LegacySnapshot {
        let legacy = try LegacyV1.container(at: url, readOnly: true)
        let c = ModelContext(legacy)
        return LegacySnapshot(
            goals: c.all(RichGoal.self).map {
                LegacyGoal(id: $0.id, title: $0.title, isTopFive: $0.isTopFive, isCompleted: $0.isCompleted,
                           createdAt: $0.createdAt, completedAt: $0.completedAt)
            },
            dumpItems: c.all(BrainDumpItem.self).map {
                LegacyDumpItem(id: $0.id, title: $0.title, tag: $0.tag, goalTitle: $0.goalTitle, createdAt: $0.createdAt)
            },
            timeBlocks: c.all(TimeBlock.self).map {
                LegacyTimeBlock(id: $0.id, taskTitle: $0.taskTitle, tag: $0.tag, goalTitle: $0.goalTitle, day: $0.day,
                                startMinute: $0.startMinute, durationMinutes: $0.durationMinutes, isDone: $0.isDone)
            },
            principles: c.all(PrincipleLog.self).map {
                LegacyPrinciple(id: $0.id, painPoint: $0.painPoint, causeType: $0.causeType, rootCause: $0.rootCause,
                                concretePrinciple: $0.concretePrinciple, tag: $0.tag, createdAt: $0.createdAt)
            },
            thinkSessions: c.all(ThinkSession.self).map {
                LegacyThinkSession(id: $0.id, topic: $0.topic, notes: $0.notes, startedAt: $0.startedAt,
                                   plannedEnd: $0.plannedEnd, endedAt: $0.endedAt)
            })
    }

    /// 已匯入的 legacy 來源 ID（目標沿用 v1 UUID；其餘存在 legacySourceID）
    func alreadyImportedIDs(_ c: ModelContext) -> Set<UUID> {
        var ids = Set(c.all(Goal.self).filter(\.migratedFromV1).map(\.id))
        ids.formUnion(c.all(ActionItem.self).compactMap(\.legacySourceID))
        ids.formUnion(c.all(PlanPlacement.self).compactMap(\.legacySourceID))
        ids.formUnion(c.all(Principle.self).compactMap(\.legacySourceID))
        ids.formUnion(c.all(ThinkingSession.self).compactMap(\.legacySourceID))
        return ids
    }

    func apply(_ plan: MigrationPlan, into c: ModelContext) throws {
        for g in plan.goals {
            let goal = Goal(title: g.title, horizon: .medium, outcomeDescription: "")
            goal.id = g.id
            goal.status = g.lifecycle
            goal.isFocus = g.isFocus
            goal.focusRank = g.focusRank
            goal.createdAt = g.createdAt
            goal.cycleStartedAt = g.createdAt
            goal.activatedAt = g.lifecycle == .active ? g.createdAt : nil
            goal.completedAt = g.completedAt
            goal.migratedFromV1 = true
            c.insert(goal)
        }
        if interruptAfterGoals {
            try c.save()
            return
        }
        let placedMinutes = Dictionary(plan.placements.map { ($0.actionID, $0.durationMinutes) }, uniquingKeysWith: { a, _ in a })
        for a in plan.actions {
            let action = ActionItem(title: a.title, kind: .personal, goalID: a.goalID)
            action.id = a.id
            action.legacySourceID = a.legacySourceID
            action.legacyTag = a.legacyTag
            action.createdAt = a.createdAt
            action.status = a.isDone ? .done : (placedMinutes[a.id] != nil ? .planned : .inbox)
            action.completedAt = a.completedAt
            // 已完成的 v1 時間塊時長作為估時歷史
            if a.isDone, let m = placedMinutes[a.id] { action.actualMinutes = m }
            if a.legacyTag.contains("緩衝") || a.legacyTag.contains("雜務") { action.kind = .maintenance }
            c.insert(action)
        }
        for p in plan.placements {
            let placement = PlanPlacement(actionID: p.actionID, day: p.day, order: p.startMinute)
            placement.id = p.id
            placement.legacySourceID = p.legacySourceID
            placement.type = .timed
            placement.startMinute = p.startMinute
            placement.durationMinutes = p.durationMinutes
            placement.isDone = p.isDone
            placement.timeZoneID = calendar.timeZone.identifier
            c.insert(placement)
        }
        for p in plan.principles {
            let principle = Principle(text: p.concretePrinciple, painPoint: p.painPoint, causeType: p.causeType, rootCause: p.rootCause)
            principle.contextTag = p.tag
            principle.createdAt = p.createdAt
            principle.legacySourceID = p.id
            c.insert(principle)
        }
        for t in plan.thinkSessions {
            let s = ThinkingSession(topic: t.topic, hours: 0)
            s.notes = t.notes
            s.startedAt = t.startedAt
            s.plannedEnd = t.plannedEnd
            s.endedAt = t.endedAt
            s.legacySourceID = t.id
            c.insert(s)
        }
        try c.save()
    }
}
