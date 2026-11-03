import XCTest
@testable import PlannerCore

final class CapacityPolicyTests: XCTestCase {
    func testFixedRestAndBufferExcludedBeforeFlexible() {
        // 10h 可用、6h 工作、1h 休息 → 可支配 180，緩衝 20% = 36，可承諾 144
        let a = CapacityCalculator.assess(CapacityInput(availableMinutes: 600, fixedWorkMinutes: 360, restMinutes: 60, items: []))
        XCTAssertEqual(a.discretionaryMinutes, 180)
        XCTAssertEqual(a.bufferMinutes, 36)
        XCTAssertEqual(a.committableMinutes, 144)
        XCTAssertEqual(a.state, .comfortable)
    }

    func testBoundaryBandsAreDeterministic() {
        func state(_ load: Int) -> LoadState {
            // 可支配 125 → 緩衝 25 → 可承諾 100
            CapacityCalculator.assess(CapacityInput(availableMinutes: 155, fixedWorkMinutes: 0, restMinutes: 30,
                                                    items: [CapacityItem(minutes: load)])).state
        }
        XCTAssertEqual(state(70), .comfortable)
        XCTAssertEqual(state(71), .feasible)
        XCTAssertEqual(state(85), .feasible)
        XCTAssertEqual(state(86), .tight)
        XCTAssertEqual(state(100), .tight)
        XCTAssertEqual(state(101), .overloaded)
    }

    /// UAT-05：低負荷但沒休息 → 容量仍是「寬鬆」，缺休息另列為結構風險
    func testMissingRestIsSeparateFromLoadState() {
        let a = CapacityCalculator.assess(CapacityInput(availableMinutes: 900, fixedWorkMinutes: 0, restMinutes: 0,
                                                        items: [CapacityItem(minutes: 25)]))
        XCTAssertEqual(a.state, .comfortable)
        XCTAssertTrue(a.missingRest)
        XCTAssertTrue(a.needsAdjustment)
        XCTAssertTrue(a.structuralRisks.contains(.missingProtectedRest(have: 0, floor: 30)))
        XCTAssertFalse(a.reasons.contains(.missingProtectedRest(have: 0, floor: 30)))
    }

    func testExcessiveSwitchesAreStructuralRisk() {
        let items = (0..<8).map { CapacityItem(minutes: 5, context: $0 % 2 == 0 ? .work : .personal) }
        let a = CapacityCalculator.assess(CapacityInput(availableMinutes: 600, fixedWorkMinutes: 0, restMinutes: 60, items: items))
        XCTAssertEqual(a.state, .comfortable)
        XCTAssertTrue(a.structuralRisks.contains(.tooManySwitches(count: 7)))
    }

    func testEmptyDayHasNoStructuralNag() {
        let a = CapacityCalculator.assess(CapacityInput(availableMinutes: 900, fixedWorkMinutes: 0, restMinutes: 0, items: []))
        XCTAssertFalse(a.needsAdjustment)
    }

    func testZeroAvailabilityIsSafe() {
        let empty = CapacityCalculator.assess(CapacityInput(availableMinutes: 0, fixedWorkMinutes: 0, restMinutes: 0, items: []))
        XCTAssertEqual(empty.state, .comfortable)
        let neg = CapacityCalculator.assess(CapacityInput(availableMinutes: -30, fixedWorkMinutes: 100, restMinutes: 0,
                                                          items: [CapacityItem(minutes: 10)]))
        XCTAssertEqual(neg.state, .overloaded)
        XCTAssertEqual(neg.committableMinutes, 0)
    }

    /// AC-06：只剩 90 分卻有 150 分行動 → 過載，至少兩個非破壞性方案，計畫不被改動
    func testAC06OverloadProposalsNeverMutate() {
        // 可支配 113 → 緩衝 23 → 可承諾 90
        let items = [CapacityItem(title: "A", minutes: 60), CapacityItem(title: "B", minutes: 50), CapacityItem(title: "C", minutes: 40)]
        let input = CapacityInput(availableMinutes: 713, fixedWorkMinutes: 540, restMinutes: 60, items: items)
        let a = CapacityCalculator.assess(input)
        XCTAssertEqual(a.committableMinutes, 90)
        XCTAssertEqual(a.state, .overloaded)
        let before = input
        let proposals = OverloadAdvisor.proposals(for: input, assessment: a)
        XCTAssertGreaterThanOrEqual(proposals.filter { $0.kind != .cancelToday }.count, 2)
        XCTAssertEqual(input, before)
        XCTAssertTrue(proposals.allSatisfy { $0.freedMinutes > 0 })
    }

    func testLockedItemsNeverProposedForChange() {
        let locked = CapacityItem(title: "鎖定", minutes: 120, isLocked: true)
        let input = CapacityInput(availableMinutes: 200, fixedWorkMinutes: 0, restMinutes: 30, items: [locked, CapacityItem(minutes: 60)])
        let p = OverloadAdvisor.proposals(for: input, assessment: CapacityCalculator.assess(input))
        XCTAssertFalse(p.contains { $0.itemIDs.contains(locked.id) || $0.newMinutes[locked.id] != nil })
    }
}

final class TomorrowDraftTests: XCTestCase {
    func testLockedAndTemplatePrecedeFlexibleAndNeverOverfill() {
        let locked = DraftCandidate(title: "已承諾", minutes: 30, source: .lockedCommitment)
        let carry = DraftCandidate(title: "延續", minutes: 40, source: .carryover, context: .work)
        let f1 = DraftCandidate(title: "焦點1", minutes: 30, source: .focusAction, rank: 0)
        let f2 = DraftCandidate(title: "焦點2", minutes: 60, source: .focusAction, rank: 1)
        let draft = TomorrowDrafter.build(availableMinutes: 713,
                                          template: [DraftCandidate(title: "上班", minutes: 540, source: .templateFixed, context: .work)],
                                          rest: [DraftCandidate(title: "午餐", minutes: 60, source: .restBoundary)],
                                          locked: [locked], carryovers: [carry], focusActions: [f2, f1])
        XCTAssertEqual(draft.included.map(\.candidate.title), ["已承諾", "延續"])
        XCTAssertEqual(draft.excluded.map(\.candidate.title), ["焦點1", "焦點2"])   // 依焦點排序判斷
        XCTAssertTrue(draft.excluded.allSatisfy { $0.reason.contains("容量不足") })
        XCTAssertTrue(draft.fixed.contains { $0.candidate.source == .buffer })
        XCTAssertTrue(draft.fixed.contains { $0.candidate.source == .restBoundary })
        XCTAssertLessThanOrEqual(draft.included.reduce(0) { $0 + $1.candidate.minutes }, draft.capacity.committableMinutes)
    }
}
