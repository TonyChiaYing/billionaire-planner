import Foundation
import SwiftData
import PlannerCore

/// 單步復原（局部重排、過載處理）。只存在記憶體，App 重啟後不保留。
@MainActor
final class UndoCenter: ObservableObject {
    static let shared = UndoCenter()

    struct PlacementState {
        var dayKey: String
        var startMinute: Int?
        var durationMinutes: Int?
        var dispositionRaw: String?
        var dispositionAt: Date?
    }
    struct ActionState {
        var statusRaw: String
        var carryoverCount: Int
        var estimateMinutes: Int?
    }
    struct Entry {
        let label: String
        var placements: [UUID: PlacementState] = [:]
        var actions: [UUID: ActionState] = [:]
        var createdPlacementIDs: [UUID] = []
        var createdActionIDs: [UUID] = []
    }

    @Published private(set) var last: Entry?

    func record(_ entry: Entry) { last = entry }
    func clear() { last = nil }
}

extension Planner {
    // MARK: - 工作模板與當日覆寫（AC-05）

    var activeTemplate: WorkTemplate? {
        context.all(WorkTemplate.self).filter(\.isActive).sorted { $0.createdAt < $1.createdAt }.first
    }

    func templateItems(_ t: WorkTemplate) -> [WorkTemplateItem] {
        context.all(WorkTemplateItem.self).filter { $0.templateID == t.id }.sorted { $0.startMinute < $1.startMinute }
    }

    /// 打開某天時：若模板適用且當天尚未套用，就建立當日實例。修改實例不反寫模板。
    func ensureDayPrepared(_ day: LocalDay) {
        let r = review(for: day)
        guard r.templateAppliedAt == nil else { return }
        if let t = activeTemplate, t.weekdays.contains(day.weekday(in: calendar)) {
            applyTemplate(t, to: day)
        } else {
            r.templateAppliedAt = now   // 不適用模板的日子也只判斷一次
            save()
        }
    }

    func applyTemplate(_ t: WorkTemplate, to day: LocalDay) {
        let existing = Set(context.all(DayBlock.self).filter { $0.dayKey == day.description }.compactMap(\.sourceTemplateItemID))
        for item in templateItems(t) where !existing.contains(item.id) {
            let b = DayBlock(day: day, kind: item.kind, title: item.title, startMinute: item.startMinute,
                             durationMinutes: item.durationMinutes)
            b.sourceTemplateItemID = item.id
            context.insert(b)
        }
        review(for: day).templateAppliedAt = now
        save()
    }

    /// 只改今天
    func editDayBlock(_ b: DayBlock, title: String, kind: BlockKind, start: Int, duration: Int) {
        b.title = title.trimmed
        b.kind = kind
        b.startMinute = start
        b.durationMinutes = max(5, duration)
        b.isOverride = true
        save()
    }

    /// 使用者明確選擇「更新模板」才影響未來
    func pushBlockToTemplate(_ b: DayBlock) {
        guard let id = b.sourceTemplateItemID,
              let item = context.all(WorkTemplateItem.self).first(where: { $0.id == id }) else { return }
        item.title = b.title
        item.kindRaw = b.kindRaw
        item.startMinute = b.startMinute
        item.durationMinutes = b.durationMinutes
        save()
    }

    func addDayBlock(_ day: LocalDay, kind: BlockKind, title: String, start: Int, duration: Int) {
        let b = DayBlock(day: day, kind: kind, title: title.trimmed.isEmpty ? kind.label : title.trimmed,
                         startMinute: start, durationMinutes: max(5, duration))
        b.isOverride = true
        context.insert(b)
        save()
    }

    func removeDayBlock(_ b: DayBlock) {
        b.isRemoved = true
        save()
    }

    @discardableResult
    func createDefaultTemplate() -> WorkTemplate {
        let t = WorkTemplate(name: "平日")
        context.insert(t)
        let items: [(BlockKind, String, Int, Int)] = [
            (.commute, "通勤", 8 * 60 + 15, 45), (.work, "上午工作", 9 * 60, 180), (.meal, "午餐", 12 * 60, 60),
            (.work, "下午工作", 13 * 60, 300), (.commute, "通勤", 18 * 60, 45), (.rest, "晚間休息", 19 * 60, 30),
        ]
        for (i, it) in items.enumerated() {
            context.insert(WorkTemplateItem(templateID: t.id, kind: it.0, title: it.1, startMinute: it.2, durationMinutes: it.3, order: i))
        }
        save()
        return t
    }

    // MARK: - 安排行動

    @discardableResult
    func plan(_ action: ActionItem, on day: LocalDay, period: DayPeriod? = nil, startMinute: Int? = nil,
              duration: Int? = nil, commitment: Commitment = .accepted) -> PlanPlacement {
        let existing = placements(on: day)
        let p = PlanPlacement(actionID: action.id, day: day, order: (existing.map(\.order).max() ?? 0) + 1)
        p.createdAt = now
        p.timeZoneID = calendar.timeZone.identifier
        p.commitment = commitment
        if let startMinute {
            p.type = .timed
            p.startMinute = startMinute
            p.period = DayPeriod.of(minute: startMinute)
        } else if let period {
            p.type = .period
            p.period = period
        }
        p.durationMinutes = duration
        context.insert(p)
        if action.status != .done { action.status = .planned }
        save()
        return p
    }

    func complete(_ p: PlanPlacement, actualMinutes: Int? = nil) {
        p.isDone = true
        if let a = actionMap()[p.actionID] {
            a.status = .done
            a.completedAt = now
            if let m = actualMinutes { a.actualMinutes += m }
            if let g = goal(a.goalID) { g.lastActivityAt = now }
        }
        save()
    }

    func reopen(_ p: PlanPlacement) {
        p.isDone = false
        if let a = actionMap()[p.actionID] {
            a.status = .planned
            a.completedAt = nil
        }
        save()
    }

    func setLocked(_ p: PlanPlacement, _ locked: Bool) {
        p.commitment = locked ? .locked : .accepted
        save()
    }

    func start(_ p: PlanPlacement) {
        p.startedAt = now
        p.disposition = p.disposition == .shrink ? .shrink : nil
        if let a = actionMap()[p.actionID] { a.status = .inProgress }
        save()
    }

    /// 專注計時結束：記錄實際投入（使用者確認後才寫入）
    func logFocus(_ p: PlanPlacement, minutes: Int, markDone: Bool) {
        guard let a = actionMap()[p.actionID] else { return }
        a.actualMinutes += max(0, minutes)
        if markDone { complete(p) } else { save() }
    }

    // MARK: - 錯過＝需要處置（AC-09）

    func needsDisposition(_ p: PlanPlacement) -> Bool {
        MissedDetector.needsDisposition(day: p.day, startMinute: p.type == .timed ? p.startMinute : nil,
                                        durationMinutes: p.durationMinutes, isDone: p.isDone, isStarted: p.startedAt != nil,
                                        isDisposed: p.disposition != nil, now: now, calendar: calendar)
    }

    func dispose(_ p: PlanPlacement, _ d: Disposition) {
        guard let a = actionMap()[p.actionID] else { return }
        p.dispositionAt = now
        switch d {
        case .startNow:
            if p.type == .timed { p.startMinute = nextQuarter() }
            p.disposition = .startNow
            start(p)
        case .shrink:
            let base = plannedMinutes(p, action: a)
            let small = a.minimumMinutes ?? max(10, base / 2)
            p.durationMinutes = small
            p.disposition = .shrink
            a.estimateMinutes = small
            save()
        case .later:
            p.disposition = .later
            let np = plan(a, on: p.day, period: p.period, startMinute: p.type == .timed ? laterSlot(after: nextQuarter(), length: plannedMinutes(p, action: a), day: p.day) : nil,
                          duration: p.durationMinutes, commitment: .accepted)
            _ = np
            save()
        case .tomorrow:
            carry(p, to: p.day.adding(days: 1, calendar: calendar))
        case .cancelToday:
            p.disposition = .cancelToday
            a.status = a.goalID == nil ? .inbox : .ready
            save()
        case .notNeeded:
            p.disposition = .notNeeded
            a.status = .cancelled
            save()
        }
    }

    /// 延續到另一天：保留來源與延續次數，不羞辱
    @discardableResult
    func carry(_ p: PlanPlacement, to day: LocalDay) -> PlanPlacement? {
        guard let a = actionMap()[p.actionID] else { return nil }
        p.disposition = .tomorrow
        p.dispositionAt = now
        a.carryoverCount += 1
        let np = plan(a, on: day, period: p.period, startMinute: nil, duration: p.durationMinutes, commitment: .accepted)
        save()
        return np
    }

    func nextQuarter() -> Int {
        let m = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return min(24 * 60 - 15, ((m + 14) / 15) * 15)
    }

    func laterSlot(after start: Int, length: Int, day: LocalDay) -> Int {
        let occupied = timedSlots(on: day).map { ($0.start, $0.end) } + dayBlocks(on: day).map { ($0.startMinute, $0.endMinute) }
        var c = start
        var moved = true
        while moved {
            moved = false
            for (s, e) in occupied where s < c + length && e > c {
                c = e
                moved = true
            }
        }
        return min(c, 24 * 60 - 5)
    }

    // MARK: - 快速插入＋局部重排（AC-08）

    func timedSlots(on day: LocalDay) -> [PlannedSlot] {
        let actions = actionMap()
        return placements(on: day).filter { $0.type == .timed && $0.isActiveToday && $0.startMinute != nil }.map { p in
            let state: SlotState = p.isDone ? .done : (p.startedAt != nil ? .inProgress : (p.isLocked ? .locked : .planned))
            return PlannedSlot(id: p.id, title: actions[p.actionID]?.title ?? "", start: p.startMinute ?? 0,
                               duration: plannedMinutes(p, action: actions[p.actionID]), state: state)
        }
    }

    /// 固定工作區段視為不可移動（以 locked 呈現）
    func slotsIncludingBlocks(on day: LocalDay) -> [PlannedSlot] {
        timedSlots(on: day) + dayBlocks(on: day).map {
            PlannedSlot(id: $0.id, title: $0.title, start: $0.startMinute, duration: $0.durationMinutes, state: .locked)
        }
    }

    func replanPreview(insertStart: Int, duration: Int, on day: LocalDay) -> ReplanPreview {
        LocalReplanner.preview(slots: slotsIncludingBlocks(on: day), insertStart: insertStart, insertDuration: duration)
    }

    /// 一次確認：建立插入項＋套用重排；可單步復原
    @discardableResult
    func quickInsert(title: String, kind: ItemContext, urgency: Int, estimate: Int?, startMinute: Int?,
                     preview: ReplanPreview?, on day: LocalDay) -> ActionItem {
        var undo = UndoCenter.Entry(label: "插入「\(title.trimmed)」")
        let a = ActionItem(title: title.trimmed, kind: kind)
        a.createdAt = now
        a.estimateMinutes = estimate
        a.estimateSource = estimate == nil ? "" : "user"
        a.urgency = urgency
        context.insert(a)
        undo.createdActionIDs.append(a.id)

        // 插入項置頂（排序模式）或放在指定時間（時段模式）
        let p = PlanPlacement(actionID: a.id, day: day, order: (placements(on: day).map(\.order).min() ?? 1) - 1)
        p.createdAt = now
        p.timeZoneID = calendar.timeZone.identifier
        if let startMinute {
            p.type = .timed
            p.startMinute = startMinute
            p.period = DayPeriod.of(minute: startMinute)
            p.durationMinutes = estimate
        }
        context.insert(p)
        a.status = .planned
        undo.createdPlacementIDs.append(p.id)

        if let preview {
            let existing = placements(on: day)
            for change in preview.changes {
                guard let target = existing.first(where: { $0.id == change.slotID }), let opt = change.selectedOption else { continue }
                undo.placements[target.id] = snapshot(target)
                if let act = actionMap()[target.actionID] { undo.actions[act.id] = snapshot(act) }
                switch opt.choice {
                case .keep: break
                case .shorten, .postpone:
                    target.startMinute = opt.newStart
                    target.durationMinutes = opt.newDuration
                case .moveToTomorrow:
                    if let np = carry(target, to: day.adding(days: 1, calendar: calendar)) { undo.createdPlacementIDs.append(np.id) }
                }
            }
        }
        save()
        UndoCenter.shared.record(undo)
        return a
    }

    // MARK: - 過載方案（AC-06：預覽後由使用者選擇）

    func apply(_ proposal: OverloadProposal, on day: LocalDay) {
        var undo = UndoCenter.Entry(label: proposal.explanation)
        let byID = Dictionary(placements(on: day).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        switch proposal.kind {
        case .useBuffer:
            return
        case .shrink:
            for (id, minutes) in proposal.newMinutes {
                guard let p = byID[id] else { continue }
                undo.placements[id] = snapshot(p)
                p.durationMinutes = minutes
            }
        case .moveToTomorrow:
            for id in proposal.itemIDs {
                guard let p = byID[id] else { continue }
                undo.placements[id] = snapshot(p)
                if let a = actionMap()[p.actionID] { undo.actions[a.id] = snapshot(a) }
                if let np = carry(p, to: day.adding(days: 1, calendar: calendar)) { undo.createdPlacementIDs.append(np.id) }
            }
        case .cancelToday:
            for id in proposal.itemIDs {
                guard let p = byID[id] else { continue }
                undo.placements[id] = snapshot(p)
                if let a = actionMap()[p.actionID] { undo.actions[a.id] = snapshot(a) }
                dispose(p, .cancelToday)
            }
        }
        save()
        UndoCenter.shared.record(undo)
    }

    // MARK: - 單步復原

    func undoLast() {
        guard let entry = UndoCenter.shared.last else { return }
        let ps = context.all(PlanPlacement.self)
        for (id, s) in entry.placements {
            guard let p = ps.first(where: { $0.id == id }) else { continue }
            p.dayKey = s.dayKey
            p.startMinute = s.startMinute
            p.durationMinutes = s.durationMinutes
            p.dispositionRaw = s.dispositionRaw
            p.dispositionAt = s.dispositionAt
        }
        let acts = context.all(ActionItem.self)
        for (id, s) in entry.actions {
            guard let a = acts.first(where: { $0.id == id }) else { continue }
            a.statusRaw = s.statusRaw
            a.carryoverCount = s.carryoverCount
            a.estimateMinutes = s.estimateMinutes
        }
        // 剛建立的項目可安全移除（它們在這次操作前不存在）
        for p in ps where entry.createdPlacementIDs.contains(p.id) { context.delete(p) }
        for a in acts where entry.createdActionIDs.contains(a.id) { context.delete(a) }
        save()
        UndoCenter.shared.clear()
    }

    private func snapshot(_ p: PlanPlacement) -> UndoCenter.PlacementState {
        .init(dayKey: p.dayKey, startMinute: p.startMinute, durationMinutes: p.durationMinutes,
              dispositionRaw: p.dispositionRaw, dispositionAt: p.dispositionAt)
    }

    private func snapshot(_ a: ActionItem) -> UndoCenter.ActionState {
        .init(statusRaw: a.statusRaw, carryoverCount: a.carryoverCount, estimateMinutes: a.estimateMinutes)
    }

    // MARK: - 明日草案（PRD 7.3）

    func tomorrowDraft(from day: LocalDay) -> TomorrowDraft {
        let target = day.adding(days: 1, calendar: calendar)
        let actions = actionMap()
        let weekday = target.weekday(in: calendar)

        // 模板（尚未套用時用模板預覽；已套用則用當日實例）
        var fixed: [DraftCandidate] = []
        var rest: [DraftCandidate] = []
        let blocks = dayBlocks(on: target)
        if !blocks.isEmpty {
            for b in blocks {
                let c = DraftCandidate(id: b.id, title: b.title, minutes: b.durationMinutes,
                                       source: b.kind == .work ? .templateFixed : .restBoundary, context: b.kind == .work ? .work : .maintenance)
                if b.kind == .work { fixed.append(c) } else { rest.append(c) }
            }
        } else if let t = activeTemplate, t.weekdays.contains(weekday) {
            for item in templateItems(t) {
                let c = DraftCandidate(id: item.id, title: item.title, minutes: item.durationMinutes,
                                       source: item.kind == .work ? .templateFixed : .restBoundary, context: item.kind == .work ? .work : .maintenance)
                if item.kind == .work { fixed.append(c) } else { rest.append(c) }
            }
        }

        let committed = placements(on: target).filter { $0.isActiveToday && !$0.isDone }.map { p in
            DraftCandidate(id: p.id, title: actions[p.actionID]?.title ?? "", minutes: plannedMinutes(p, action: actions[p.actionID]),
                           source: .lockedCommitment, context: actions[p.actionID]?.kind ?? .personal)
        }
        let committedActionIDs = Set(placements(on: target).map(\.actionID))

        let carry = placements(on: day).filter { !$0.isDone && $0.disposition == nil && !committedActionIDs.contains($0.actionID) }
            .compactMap { p -> DraftCandidate? in
                guard let a = actions[p.actionID], a.status.isOpen else { return nil }
                return DraftCandidate(id: p.id, title: a.title, minutes: plannedMinutes(p, action: a), source: .carryover, context: a.kind)
            }

        var focus: [DraftCandidate] = []
        for (rank, g) in focusGoals.enumerated() where g.status == .active {
            guard let next = openActions(for: g.id).first(where: { !committedActionIDs.contains($0.id) && $0.status != .planned })
                    ?? openActions(for: g.id).first(where: { !committedActionIDs.contains($0.id) }) else { continue }
            let minutes = next.minimumMinutes ?? next.estimateMinutes
                ?? estimateSuggestion(title: next.title, goalID: g.id, kind: next.kind, userEstimate: nil)?.minutes
                ?? settings.defaultEstimateMinutes
            focus.append(DraftCandidate(id: next.id, title: next.title, minutes: minutes, source: .focusAction, context: .personal, rank: rank))
        }
        return TomorrowDrafter.build(availableMinutes: settings.availableMinutes, template: fixed, rest: rest,
                                     locked: committed, carryovers: carry, focusActions: focus, policy: settings.capacityPolicy)
    }

    /// 只接受勾選的項目；其餘不受影響（草案不自動成為承諾）
    func accept(_ entries: [DraftEntry], from day: LocalDay) {
        let target = day.adding(days: 1, calendar: calendar)
        let ps = context.all(PlanPlacement.self)
        let actions = actionMap()
        for e in entries {
            switch e.candidate.source {
            case .carryover:
                if let p = ps.first(where: { $0.id == e.candidate.id }) { carry(p, to: target) }
            case .focusAction:
                if let a = actions[e.candidate.id] { plan(a, on: target, duration: e.candidate.minutes) }
            default:
                break
            }
        }
        if let t = activeTemplate, t.weekdays.contains(target.weekday(in: calendar)) { ensureDayPrepared(target) }
        review(for: day).draftAcceptedAt = now
        save()
    }
}
