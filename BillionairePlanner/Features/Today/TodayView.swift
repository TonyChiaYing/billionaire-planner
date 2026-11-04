import SwiftUI
import SwiftData
import PlannerCore

/// 首頁依序回答：最重要的下一步？裝得下嗎？有什麼要處置？最近推進了什麼？（PRD 5.2）
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dataVersion) private var dataVersion
    @AppStorage(SettingKey.fineTimeMode) private var fineTimeMode = false
    @ObservedObject private var undo = UndoCenter.shared

    @State private var showInsert = false
    @State private var showAdd = false
    @State private var showSkeleton = false
    @State private var focusTarget: PlanPlacement?
    @State private var editTarget: PlanPlacement?
    @State private var proposalToConfirm: OverloadProposal?
    @State private var recoveryTarget: RecoveryEpisode?
    @State private var showWeekly = false
    @State private var nextStepGoal: Goal?
    @State private var evaluated = false

    var body: some View {
        let _ = dataVersion
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            content(planner: Planner(context, now: tl.date))
        }
        .navigationTitle("今天")
    }

    @ViewBuilder
    private func content(planner: Planner) -> some View {
        let day = planner.today
        let all = planner.placements(on: day)
        let actions = planner.actionMap()
        let active = all.filter(\.isActiveToday)
        let pending = planner.overduePlacements() + active.filter { planner.needsDisposition($0) }
        let next = active.first { !$0.isDone && !pending.contains($0) && ($0.startedAt != nil || $0.isLocked) }
            ?? active.first { !$0.isDone && !pending.contains($0) }
        let cap = planner.capacity(for: day)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(day: day, planner: planner)
                    nextActionCard(next, actions: actions, planner: planner)
                    capacityCard(cap, planner: planner, day: day)
                    if let entry = undo.last {
                        undoBanner(entry.label, planner: planner)
                    }
                    if !pending.isEmpty { dispositionCard(pending, actions: actions, planner: planner) }
                    planCard(active.filter { !pending.contains($0) }, actions: actions, planner: planner, day: day)
                    interventionCards(planner: planner)
                    recentOutcomes(planner: planner)
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("今天")
            .toolbar {
                ToolbarItemGroup {
                    Button { showInsert = true } label: { Label("快速插入", systemImage: "bolt.badge.clock") }
                        .accessibilityIdentifier("today.insert")
                        .keyboardShortcut("i", modifiers: [.command])
                        .help("快速插入臨時工作")
                    Button { showAdd = true } label: { Label("加入今天", systemImage: "plus") }
                        .accessibilityIdentifier("today.add")
                        .keyboardShortcut("n", modifiers: [.command])
                    Button { showSkeleton = true } label: { Label("今日骨架", systemImage: "rectangle.split.3x1") }
                        .accessibilityIdentifier("today.skeleton")
                    SettingsToolbarButton()
                }
            }
            .sheet(isPresented: $showInsert) { QuickInsertSheet(day: day) }
            .sheet(isPresented: $showAdd) { AddToTodaySheet(day: day) }
            .sheet(isPresented: $showSkeleton) { DaySkeletonSheet(day: day) }
            .sheet(item: $focusTarget) { FocusTimerSheet(placement: $0) }
            .sheet(item: $editTarget) { PlacementEditSheet(placement: $0) }
            .sheet(item: $recoveryTarget) { RecoverySheet(episode: $0) }
            .sheet(item: $nextStepGoal) { GoalEditSheets(goal: $0, kind: .action) }
            .sheet(isPresented: $showWeekly) { WeeklyReviewSheet() }
            .confirmationDialog("確認調整", isPresented: Binding(get: { proposalToConfirm != nil }, set: { if !$0 { proposalToConfirm = nil } }),
                                presenting: proposalToConfirm) { p in
                Button("套用（可復原）") { planner.apply(p, on: day) }
                Button("取消", role: .cancel) {}
            } message: { p in
                Text(p.explanation)
            }
            .task {
                guard !evaluated else { return }
                evaluated = true
                planner.ensureDayPrepared(day)
                planner.evaluateRecoveryPrompts()
            }
        }
    }

    private func header(day: LocalDay, planner: Planner) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.start(in: planner.calendar).formatted(.dateTime.month().day().weekday(.wide)))
                .font(.title2.bold())
            if let r = planner.existingReview(for: day), r.isRestDay {
                Text("今天是休息日，安排可以很少。").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 1. 下一步

    @ViewBuilder
    private func nextActionCard(_ p: PlanPlacement?, actions: [UUID: ActionItem], planner: Planner) -> some View {
        Card(title: "最重要的下一步", symbol: "arrow.right.circle") {
            if let p, let a = actions[p.actionID] {
                VStack(alignment: .leading, spacing: 8) {
                    Text(a.title).font(.title3.bold())
                    HStack(spacing: 8) {
                        StatusBadge(text: a.kind.label, symbol: a.kind.symbol, color: a.kind.color)
                        if let g = planner.goal(a.goalID) {
                            Text(g.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text(timeText(p, planner: planner, action: a)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if !a.minimumVersion.isEmpty {
                        Text("縮小版本：\(a.minimumVersion)").font(.caption).foregroundStyle(.secondary)
                    }
                    if planner.isFocusing(p) {
                        Label("專注中 · 已 \(planner.focusElapsedMinutes(p)) 分", systemImage: "timer")
                            .font(.callout).foregroundStyle(Color.assetGreen)
                            .accessibilityIdentifier("today.focusing")
                    }
                    HStack {
                        Button { focusTarget = p } label: { Label(p.startedAt == nil ? "開始專注" : "回到計時", systemImage: "timer") }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(.black)
                            .accessibilityIdentifier("today.focus")
                        Button { planner.complete(p) } label: { Label("完成", systemImage: "checkmark") }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("today.complete")
                    }
                }
            } else if planner.placements(on: planner.today).contains(where: \.isDone) {
                // V202-DAILY-02：做完了不是「還沒有安排」
                Label("今天安排的都完成了。", systemImage: "checkmark.circle")
                    .foregroundStyle(Color.assetGreen)
                    .accessibilityIdentifier("today.allDone")
                ForEach(planner.goalsNeedingNextStep(after: planner.today)) { g in
                    HStack {
                        Text("「\(g.title)」還沒有下一步").font(.callout)
                        Spacer()
                        Button("寫下一步") { nextStepGoal = g }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("today.writeNextStep")
                    }
                }
            } else {
                EmptyHint(text: "今天還沒有安排。按「＋」從焦點目標挑一個小的下一步。", symbol: "plus.circle")
            }
        }
    }

    // MARK: 2. 容量

    private func capacityCard(_ c: CapacityAssessment, planner: Planner, day: LocalDay) -> some View {
        Card(title: "今天裝得下嗎", symbol: "gauge.with.dots.needle.33percent") {
            HStack(spacing: 8) {
                StatusBadge(text: "容量：\(c.state.label)", symbol: c.state.symbol, color: c.state.color)
                    .accessibilityIdentifier("capacity.load")
                if c.missingRest {
                    StatusBadge(text: "需要補休息", symbol: "cup.and.saucer", color: .attention)
                        .accessibilityIdentifier("capacity.rest")
                } else if c.needsAdjustment {
                    StatusBadge(text: "計畫需調整", symbol: "slider.horizontal.3", color: .attention)
                        .accessibilityIdentifier("capacity.structure")
                }
                Spacer()
                Text("已安排 \(formatDuration(c.loadMinutes)) ／ 可承諾 \(formatDuration(c.committableMinutes))")
                    .font(.callout.monospacedDigit())
            }
            ProgressView(value: min(1, c.committableMinutes > 0 ? Double(c.loadMinutes) / Double(c.committableMinutes) : 0))
                .tint(c.state.color)
                .accessibilityLabel("負荷 \(c.state.label)")
            Text("固定工作 \(formatDuration(c.fixedWorkMinutes)) · 休息／生活 \(formatDuration(c.restMinutes)) · 緩衝 \(formatDuration(c.bufferMinutes))")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(c.reasons.enumerated()), id: \.offset) { _, r in
                Text("· \(r.text)").font(.caption).foregroundStyle(.secondary)
            }
            if c.needsAdjustment {
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.missingRest ? "不是事情太多，而是還沒保護休息時間。" : "時間夠，但安排方式可能讓你很累。")
                        .font(.callout.bold())
                    ForEach(Array(c.structuralRisks.enumerated()), id: \.offset) { _, r in
                        Text("· \(r.text)").font(.caption).foregroundStyle(.secondary)
                    }
                    if c.missingRest {
                        Button { showSkeleton = true } label: { Label("加入休息", systemImage: "plus") }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("capacity.addRest")
                    }
                }
                .padding(10)
                .background(Color.attention.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            if c.state == .overloaded {
                let proposals = OverloadAdvisor.proposals(for: planner.capacityInput(for: day), assessment: c)
                Text("可以這樣調整（不會自動套用）：").font(.caption.bold())
                ForEach(proposals) { p in
                    Button { proposalToConfirm = p } label: {
                        Label(p.explanation, systemImage: proposalSymbol(p.kind)).font(.callout).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func proposalSymbol(_ k: OverloadProposal.Kind) -> String {
        switch k {
        case .useBuffer: "shield.lefthalf.filled"
        case .shrink: "arrow.down.right.and.arrow.up.left"
        case .moveToTomorrow: "sunrise"
        case .cancelToday: "xmark.circle"
        }
    }

    private func undoBanner(_ label: String, planner: Planner) -> some View {
        HStack {
            Label("已調整：\(label)", systemImage: "arrow.uturn.backward.circle").font(.callout).lineLimit(2)
            Spacer()
            Button("復原") { planner.undoLast() }.buttonStyle(.bordered)
            Button { UndoCenter.shared.clear() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).accessibilityLabel("關閉")
        }
        .padding(10)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: 需要處置（錯過≠失敗）

    private func dispositionCard(_ items: [PlanPlacement], actions: [UUID: ActionItem], planner: Planner) -> some View {
        Card(title: "需要處置（\(items.count)）", symbol: "clock.badge.questionmark") {
            Text("時間過了沒關係，選一個新的去向就好。").font(.caption).foregroundStyle(.secondary)
            ForEach(items) { p in
                HStack {
                    VStack(alignment: .leading) {
                        Text(actions[p.actionID]?.title ?? "").bold()
                        Text([dayAgo(p.day, planner: planner), planner.goal(actions[p.actionID]?.goalID)?.title,
                              timeText(p, planner: planner, action: actions[p.actionID])]
                            .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(Disposition.allCases, id: \.self) { d in
                            Button { planner.dispose(p, d) } label: { Label(d.label, systemImage: d.symbol) }
                        }
                    } label: {
                        Label("處置", systemImage: "ellipsis.circle")
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    .accessibilityLabel("處置 \(actions[p.actionID]?.title ?? "")")
                }
            }
        }
    }

    // MARK: 今日安排（工作／個人／休息分組）

    private func planCard(_ items: [PlanPlacement], actions: [UUID: ActionItem], planner: Planner, day: LocalDay) -> some View {
        let personal = items.filter { actions[$0.actionID]?.kind != .work }
        let work = items.filter { actions[$0.actionID]?.kind == .work }
        let blocks = planner.dayBlocks(on: day)
        return Card(title: "今日安排", symbol: "list.bullet") {
            if items.isEmpty && blocks.isEmpty {
                EmptyHint(text: "還沒有安排；「今日骨架」可以套用工作模板。")
            }
            if !personal.isEmpty {
                groupHeader("個人與生活", symbol: "target")
                ForEach(personal) { row($0, action: actions[$0.actionID], planner: planner) }
            }
            if !work.isEmpty {
                groupHeader("工作", symbol: "briefcase")
                ForEach(work) { row($0, action: actions[$0.actionID], planner: planner) }
            }
            if !blocks.isEmpty {
                groupHeader("固定區段與休息", symbol: "cup.and.saucer")
                ForEach(blocks) { b in
                    HStack {
                        Image(systemName: b.kind.symbol).foregroundStyle(b.kind.isProtected ? Color.assetGreen : .cyan).frame(width: 22)
                        Text(b.title)
                        Spacer()
                        Text("\(formatMinute(b.startMinute))–\(formatMinute(b.endMinute))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func groupHeader(_ t: String, symbol: String) -> some View {
        Label(t, systemImage: symbol).font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 4)
    }

    private func row(_ p: PlanPlacement, action a: ActionItem?, planner: Planner) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Button {
                p.isDone ? planner.reopen(p) : planner.complete(p)
            } label: {
                Image(systemName: p.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(p.isDone ? Color.assetGreen : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(p.isDone ? "標為未完成" : "標為完成")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if p.isLocked { Image(systemName: "lock.fill").font(.caption2).accessibilityLabel("已鎖定") }
                    Text(a?.title ?? "").strikethrough(p.isDone)
                }
                HStack(spacing: 6) {
                    Text(timeText(p, planner: planner, action: a)).font(.caption.monospacedDigit())
                    if let g = planner.goal(a?.goalID) { Text("· \(g.title)").font(.caption).lineLimit(1) }
                    if (a?.carryoverCount ?? 0) > 0 { Text("· 延續 \(a?.carryoverCount ?? 0) 次").font(.caption) }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button { focusTarget = p } label: { Label("開始專注", systemImage: "timer") }
                Button { editTarget = p } label: { Label("調整時間／時長", systemImage: "slider.horizontal.3") }
                Button { planner.setLocked(p, !p.isLocked) } label: {
                    Label(p.isLocked ? "取消鎖定" : "鎖定（重排時不動）", systemImage: p.isLocked ? "lock.open" : "lock")
                }
                Divider()
                ForEach(Disposition.allCases.filter { $0 != .startNow }, id: \.self) { d in
                    Button { planner.dispose(p, d) } label: { Label(d.label, systemImage: d.symbol) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .accessibilityLabel("更多動作")
        }
        .padding(.vertical, 2)
    }

    /// 之前幾天的安排標出是哪天的（今天的不標）
    private func dayAgo(_ day: LocalDay, planner: Planner) -> String? {
        guard day < planner.today else { return nil }
        let n = (1...14).first { day.adding(days: $0, calendar: planner.calendar) >= planner.today } ?? 14
        return n == 1 ? "昨天" : "\(n) 天前"
    }

    private func timeText(_ p: PlanPlacement, planner: Planner, action: ActionItem?) -> String {
        let minutes = planner.plannedMinutes(p, action: action)
        let est = p.durationMinutes == nil && action?.estimateMinutes == nil ? "（未估時，以 \(minutes) 分計）" : formatDuration(minutes)
        if p.type == .timed, let s = p.startMinute { return "\(formatMinute(s)) · \(est)" }
        if let period = p.period { return "\(period.label) · \(est)" }
        return est
    }

    // MARK: 分層介入（數量受限，不壓過行動）

    @ViewBuilder
    private func interventionCards(planner: Planner) -> some View {
        let episodes = planner.goals.compactMap { planner.openEpisode(for: $0) }.prefix(1)
        let deadlines = planner.deadlinePromptGoals().prefix(1)
        let weekly = planner.weeklyPromptDue()
        if !episodes.isEmpty || !deadlines.isEmpty || weekly {
            Card(title: "值得看一下", symbol: "lightbulb") {
                ForEach(Array(episodes)) { e in
                    let g = planner.goal(e.goalID)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("「\(g?.title ?? "")」可能需要更小的路徑").bold()
                        ForEach(e.signals, id: \.evidence) { s in Text("· \(s.evidence)").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Button("看看恢復方案") { recoveryTarget = e }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                            Button("過幾天再說") { planner.snooze(e, days: 3) }.buttonStyle(.bordered)
                            Button("關閉") { planner.dismiss(e) }.buttonStyle(.borderless)
                        }
                    }
                }
                ForEach(Array(deadlines)) { prompt in
                    let g = prompt.goal
                    let risk = prompt.risk
                    VStack(alignment: .leading, spacing: 6) {
                        Text("「\(g.title)」\(risk.label)").bold()
                        if let d = g.deadline { Text("期限 \(d.shortDay)").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            NavigationLink("檢視目標") { GoalDetailView(goal: g) }.buttonStyle(.bordered)
                            Button("稍後提醒") {
                                planner.logIntervention(key: "deadline:\(g.id.uuidString)", level: .deadline, outcome: .snoozed,
                                                        severity: risk.rawValue, snoozeUntil: planner.now.addingTimeInterval(3 * 86_400))
                            }.buttonStyle(.bordered)
                            Button("知道了") {
                                planner.logIntervention(key: "deadline:\(g.id.uuidString)", level: .deadline, outcome: .handled, severity: risk.rawValue)
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                if weekly {
                    HStack {
                        Text("這週的回顧還沒做（約 5 分鐘）")
                        Spacer()
                        Button("開始") { showWeekly = true }.buttonStyle(.bordered)
                        Button("這週略過") {
                            planner.logIntervention(key: "weekly", level: .weekly, outcome: .snoozed, severity: 1,
                                                    snoozeUntil: planner.now.addingTimeInterval(7 * 86_400))
                        }.buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    // MARK: 最近推進

    @ViewBuilder
    private func recentOutcomes(planner: Planner) -> some View {
        let recent = planner.context.all(OutcomeEvidence.self).filter { !$0.isReversed }.sorted { $0.recordedAt > $1.recordedAt }.prefix(3)
        Card(title: "最近確實推進的", symbol: "chart.line.uptrend.xyaxis") {
            if recent.isEmpty {
                EmptyHint(text: "完成行動後，在晚間日結記下一項成果。")
            }
            ForEach(Array(recent)) { e in
                HStack {
                    Text(planner.goal(e.goalID)?.title ?? "").font(.caption).foregroundStyle(.secondary)
                    Text(e.note.isEmpty ? (e.value.map { "\($0.formatted()) \(e.unit)" } ?? e.kind.label) : e.note)
                    Spacer()
                    Text(e.recordedAt.shortDay).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
