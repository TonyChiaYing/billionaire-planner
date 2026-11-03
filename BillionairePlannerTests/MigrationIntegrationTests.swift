import XCTest
import SwiftData
import PlannerCore
@testable import BillionairePlanner

/// AC-15：用真正的 v1 SwiftData store 驗證遷移（備份、v1 不被改動、可重跑、中斷重試不重複）
@MainActor
final class MigrationIntegrationTests: XCTestCase {
    var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "bp-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    var v1URL: URL { dir.appending(path: "Planner.store") }
    var backups: URL { dir.appending(path: "Backups", directoryHint: .isDirectory) }

    /// 典型 v1 資料：重名目標、孤兒 goalTitle、超過 5 個 Top 5、完成的項目、Unicode、午夜時間塊、進行中的思考
    func writeTypicalV1() throws -> (goals: Int, dumps: Int, blocks: Int) {
        let c = try LegacyV1.container(at: v1URL, readOnly: false)
        let ctx = ModelContext(c)
        var goals: [RichGoal] = []
        for i in 0..<7 {
            let g = RichGoal(title: "目標 \(i) 🚀")
            g.isTopFive = true
            g.createdAt = Date(timeIntervalSince1970: 1_790_000_000 + Double(i))
            goals.append(g)
            ctx.insert(g)
        }
        let dupA = RichGoal(title: "健身"), dupB = RichGoal(title: "健身")
        let done = RichGoal(title: "完成的目標")
        done.isCompleted = true
        done.completedAt = Date(timeIntervalSince1970: 1_791_000_000)
        for g in [dupA, dupB, done] { ctx.insert(g) }

        ctx.insert(BrainDumpItem(title: "讀 30 頁", tag: "#深度工作", goalTitle: "目標 0 🚀"))
        ctx.insert(BrainDumpItem(title: "跑步", tag: "#深度工作", goalTitle: "健身"))           // 重名 → 不連結
        ctx.insert(BrainDumpItem(title: "記帳", tag: "#財務決策", goalTitle: "不存在的目標"))   // 孤兒 → 不連結
        let midnight = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_791_500_000))
        let b1 = TimeBlock(taskTitle: "深夜整理", tag: "#緩衝/雜務", goalTitle: nil, day: midnight, startMinute: 0, durationMinutes: 15)
        b1.isDone = true
        ctx.insert(b1)
        ctx.insert(TimeBlock(taskTitle: "寫企劃", tag: "#戰略規劃", goalTitle: "目標 1 🚀", day: midnight, startMinute: 600, durationMinutes: 45))
        ctx.insert(PrincipleLog(painPoint: "拖延", causeType: "人", rootCause: "太累", concretePrinciple: "先做 5 分鐘", tag: "#深度工作"))
        ctx.insert(ThinkSession(topic: "AI 與工作", hours: 1))
        try ctx.save()
        return (10, 3, 2)
    }

    func migrator(_ container: ModelContainer) -> V1Migrator {
        V1Migrator(v1Store: v1URL, backupRoot: backups, container: container)
    }

    func testNoLegacyStore() throws {
        let c = try PlannerContainer.inMemory()
        XCTAssertEqual(migrator(c).runIfNeeded(), .noLegacyStore)
    }

    func testEmptyV1Store() throws {
        let legacy = try LegacyV1.container(at: v1URL, readOnly: false)
        try ModelContext(legacy).save()
        let c = try PlannerContainer.inMemory()
        guard case .migrated(let r) = migrator(c).runIfNeeded() else { return XCTFail() }
        XCTAssertEqual(r.goals.source, 0)
        XCTAssertEqual(migrator(c).runIfNeeded(), .alreadyCompleted)
    }

    func testTypicalStoreMigratesWithReportAndBackup() throws {
        let expected = try writeTypicalV1()
        let c = try PlannerContainer.inMemory()
        guard case .migrated(let r) = migrator(c).runIfNeeded() else { return XCTFail("migration failed") }
        let ctx = ModelContext(c)

        XCTAssertEqual(ctx.all(Goal.self).count, expected.goals)
        XCTAssertEqual(ctx.all(Goal.self).filter(\.isFocus).count, 5)            // 超過 5 個只取前 5
        XCTAssertEqual(r.focusOverflowGoalIDs.count, 2)
        XCTAssertEqual(ctx.all(ActionItem.self).count, expected.dumps + expected.blocks)
        XCTAssertEqual(ctx.all(PlanPlacement.self).count, expected.blocks)
        XCTAssertEqual(ctx.all(Principle.self).count, 1)
        XCTAssertEqual(ctx.all(ThinkingSession.self).count, 1)
        XCTAssertEqual(r.unlinked.count, 2)
        XCTAssertEqual(ctx.all(Goal.self).first { $0.title == "完成的目標" }?.status, .completed)

        // 午夜時間塊仍在原本那一天、完成狀態保留
        let midnight = ctx.all(PlanPlacement.self).first { $0.startMinute == 0 }
        XCTAssertEqual(midnight?.dayKey, LocalDay(Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_791_500_000)),
                                                  calendar: .current).description)
        XCTAssertEqual(midnight?.isDone, true)

        // 備份存在；v1 原檔仍可被 v1 schema 讀取且內容不變
        let backupDirs = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        XCTAssertEqual(backupDirs.count, 1)
        let v1 = ModelContext(try LegacyV1.container(at: v1URL, readOnly: true))
        XCTAssertEqual(v1.all(RichGoal.self).count, expected.goals)

        XCTAssertEqual(migrator(c).runIfNeeded(), .alreadyCompleted)
    }

    func testInterruptedMigrationRetriesWithoutDuplicates() throws {
        let expected = try writeTypicalV1()
        let c = try PlannerContainer.inMemory()
        var m = migrator(c)
        m.interruptAfterGoals = true
        guard case .failed = m.runIfNeeded() else { return XCTFail() }
        XCTAssertEqual(ModelContext(c).all(Goal.self).count, expected.goals)    // 只寫了一半

        guard case .migrated(let r) = migrator(c).runIfNeeded() else { return XCTFail() }
        let ctx = ModelContext(c)
        XCTAssertEqual(ctx.all(Goal.self).count, expected.goals)                // 沒有重複
        XCTAssertEqual(ctx.all(ActionItem.self).count, expected.dumps + expected.blocks)
        XCTAssertEqual(r.goals.alreadyPresent, expected.goals)
        XCTAssertEqual(Set(ctx.all(Goal.self).map(\.id)).count, expected.goals)
    }

    func testReopenAfterMigration() throws {
        _ = try writeTypicalV1()
        let url = dir.appending(path: "PlannerV2.store")
        do {
            let c = try PlannerContainer.make(url: url)
            guard case .migrated = migrator(c).runIfNeeded() else { return XCTFail() }
        }
        let reopened = try PlannerContainer.make(url: url)
        XCTAssertEqual(ModelContext(reopened).all(Goal.self).count, 10)
        XCTAssertEqual(migrator(reopened).runIfNeeded(), .alreadyCompleted)
    }
}
