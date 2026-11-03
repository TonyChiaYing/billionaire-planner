import XCTest
@testable import PlannerCore

/// AC-15 的純規則部分（SwiftData 實際讀寫另由 App 測試覆蓋）
final class MigrationMapperTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return c
    }()
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func goal(_ title: String, top: Bool = false, done: Bool = false, offset: Double = 0) -> LegacyGoal {
        LegacyGoal(id: UUID(), title: title, isTopFive: top, isCompleted: done, createdAt: t0.addingTimeInterval(offset),
                   completedAt: done ? t0.addingTimeInterval(offset + 100) : nil)
    }

    func testEmptyStore() {
        let p = LegacyMigrationMapper.plan(LegacySnapshot(), alreadyImported: [], calendar: cal)
        XCTAssertTrue(p.goals.isEmpty && p.actions.isEmpty && p.placements.isEmpty)
        XCTAssertTrue(p.report.warnings.isEmpty)
    }

    func testOneOfEachPreservesIDsAndLinks() {
        let g = goal("讀完 12 本書", top: true)
        let dump = LegacyDumpItem(id: UUID(), title: "買書", tag: "#深度工作", goalTitle: " 讀完 12本書 ".replacingOccurrences(of: "12本", with: "12 本"), createdAt: t0)
        let block = LegacyTimeBlock(id: UUID(), taskTitle: "讀 30 頁", tag: "#深度工作", goalTitle: "讀完 12 本書",
                                    day: LocalDay(year: 2026, month: 10, day: 29).start(in: cal), startMinute: 0,
                                    durationMinutes: 15, isDone: true)
        let pr = LegacyPrinciple(id: UUID(), painPoint: "拖延", causeType: "人", rootCause: "太累", concretePrinciple: "先做 5 分鐘",
                                 tag: "#戰略規劃", createdAt: t0)
        let th = LegacyThinkSession(id: UUID(), topic: "AI", notes: "筆記", startedAt: t0, plannedEnd: t0, endedAt: nil)
        let p = LegacyMigrationMapper.plan(LegacySnapshot(goals: [g], dumpItems: [dump], timeBlocks: [block],
                                                          principles: [pr], thinkSessions: [th]), alreadyImported: [], calendar: cal)
        XCTAssertEqual(p.goals.first?.id, g.id)
        XCTAssertTrue(p.goals.first!.isFocus)
        XCTAssertEqual(p.actions.count, 2)
        XCTAssertTrue(p.actions.allSatisfy { $0.goalID == g.id })
        XCTAssertEqual(p.placements.first?.id, block.id)
        XCTAssertEqual(p.placements.first?.day, LocalDay(year: 2026, month: 10, day: 29))   // 午夜時間塊不跑到前一天
        XCTAssertEqual(p.placements.first?.actionID, LegacyMigrationMapper.derivedActionID(forBlock: block.id))
        XCTAssertEqual(p.principles, [pr])
        XCTAssertEqual(p.thinkSessions, [th])
        XCTAssertTrue(p.report.unlinked.isEmpty)
    }

    func testDuplicateAndMissingTitlesStayUnlinked() {
        let a = goal("健身"), b = goal("健身", offset: 10)
        let dumps = [LegacyDumpItem(id: UUID(), title: "跑步", tag: "", goalTitle: "健身", createdAt: t0),
                     LegacyDumpItem(id: UUID(), title: "記帳", tag: "", goalTitle: "理財", createdAt: t0)]
        let p = LegacyMigrationMapper.plan(LegacySnapshot(goals: [a, b], dumpItems: dumps), alreadyImported: [], calendar: cal)
        XCTAssertTrue(p.actions.allSatisfy { $0.goalID == nil })
        XCTAssertEqual(p.report.unlinked.count, 2)
        XCTAssertEqual(p.goals.count, 2)   // 重名目標都保留
    }

    func testMoreThanFiveTopFiveKeepsAllGoals() {
        let goals = (0..<7).map { goal("G\($0) 目標😀", top: true, offset: Double($0)) }
        let p = LegacyMigrationMapper.plan(LegacySnapshot(goals: goals), alreadyImported: [], calendar: cal)
        XCTAssertEqual(p.goals.count, 7)
        XCTAssertEqual(p.goals.filter(\.isFocus).map(\.id), Array(goals.prefix(5).map(\.id)))
        XCTAssertEqual(p.report.focusOverflowGoalIDs, goals.suffix(2).map(\.id))
        XCTAssertFalse(p.report.warnings.isEmpty)
    }

    func testCompletedGoalAndBlockKeepCompletion() {
        let g = goal("完成的", done: true)
        let p = LegacyMigrationMapper.plan(LegacySnapshot(goals: [g]), alreadyImported: [], calendar: cal)
        XCTAssertEqual(p.goals[0].lifecycle, .completed)
        XCTAssertEqual(p.goals[0].completedAt, g.completedAt)
        XCTAssertFalse(p.goals[0].isFocus)
    }

    /// 重跑：已匯入的來源 ID 不再產生
    func testIdempotentRetry() {
        let g = goal("A", top: true)
        let block = LegacyTimeBlock(id: UUID(), taskTitle: "x", tag: "", goalTitle: "A", day: t0, startMinute: 600,
                                    durationMinutes: 30, isDone: false)
        let snap = LegacySnapshot(goals: [g], timeBlocks: [block])
        let first = LegacyMigrationMapper.plan(snap, alreadyImported: [], calendar: cal)
        let imported = Set(first.goals.map(\.id) + first.placements.map(\.legacySourceID) + first.actions.map(\.legacySourceID))
        let second = LegacyMigrationMapper.plan(snap, alreadyImported: imported, calendar: cal)
        XCTAssertTrue(second.goals.isEmpty && second.actions.isEmpty && second.placements.isEmpty)
        XCTAssertEqual(second.report.goals.alreadyPresent, 1)
        XCTAssertEqual(second.report.timeBlocks.alreadyPresent, 1)
        // 中斷在一半（只匯入了目標）→ 重跑只補上其餘
        let partial = LegacyMigrationMapper.plan(snap, alreadyImported: [g.id], calendar: cal)
        XCTAssertTrue(partial.goals.isEmpty)
        XCTAssertEqual(partial.placements.count, 1)
        XCTAssertEqual(partial.actions.first?.goalID, g.id)
    }

    func testLargeStore() {
        let goals = (0..<1000).map { goal("目標\($0)", offset: Double($0)) }
        let blocks = (0..<5000).map { i in
            LegacyTimeBlock(id: UUID(), taskTitle: "t\(i)", tag: "", goalTitle: "目標\(i % 1000)", day: t0,
                            startMinute: (i % 72) * 15, durationMinutes: 15, isDone: i % 2 == 0)
        }
        let p = LegacyMigrationMapper.plan(LegacySnapshot(goals: goals, timeBlocks: blocks), alreadyImported: [], calendar: cal)
        XCTAssertEqual(p.placements.count, 5000)
        XCTAssertTrue(p.actions.allSatisfy { $0.goalID != nil })
    }
}
