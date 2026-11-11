import SwiftUI
import SwiftData
import PlannerCore

/// 焦點少數、其餘保留不爭奪注意力（PRD 決策 B 聚焦少數目標）
struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dataVersion) private var dataVersion
    @State private var showWizard = false
    @State private var showClosed = false

    var body: some View {
        let _ = dataVersion
        let planner = Planner(context)
        let goals = planner.goals
        let focus = planner.focusGoals
        let drafts = goals.filter { $0.status == .draft && !$0.isFocus }
        let others = goals.filter { $0.status == .active && !$0.isFocus }
        let paused = goals.filter { $0.status == .paused && !$0.isFocus }
        let closed = goals.filter { $0.status == .completed || $0.status == .archived }
        let unlinked = planner.unlinkedMigrationActions()

        NavigationStack {
            List {
                Section {
                    if focus.isEmpty {
                        EmptyHint(text: "還沒有焦點目標。建議最多 3 個，上限 5 個。", symbol: "scope")
                    }
                    ForEach(focus) { g in
                        NavigationLink { GoalDetailView(goal: g) } label: { GoalRow(goal: g, planner: planner) }
                            .contextMenu {
                                Button("往上") { planner.moveFocus(g, by: -1) }
                                Button("往下") { planner.moveFocus(g, by: 1) }
                                Button("取消焦點") { planner.unfocus(g) }
                            }
                            .accessibilityAction(named: "往上") { planner.moveFocus(g, by: -1) }
                            .accessibilityAction(named: "往下") { planner.moveFocus(g, by: 1) }
                    }
                } header: {
                    Text("焦點目標 \(focus.count)/\(FocusPolicy.hardLimit)")
                        .accessibilityIdentifier("goals.focusHeader")
                } footer: {
                    if focus.count > FocusPolicy.recommended {
                        Text("超過 3 個焦點時，每個目標每天能分到的時間會變少。")
                    }
                }

                if !drafts.isEmpty {
                    Section {
                        ForEach(drafts) { g in NavigationLink { GoalDetailView(goal: g) } label: { GoalRow(goal: g, planner: planner) } }
                    } header: { Text("草稿") } footer: { Text("補上策略與一個下一步，就能加入焦點並出現在今天。") }
                }
                if !others.isEmpty {
                    Section("其他進行中") {
                        ForEach(others) { g in NavigationLink { GoalDetailView(goal: g) } label: { GoalRow(goal: g, planner: planner) } }
                    }
                }
                if !paused.isEmpty {
                    Section("暫停中") {
                        ForEach(paused) { g in NavigationLink { GoalDetailView(goal: g) } label: { GoalRow(goal: g, planner: planner) } }
                    }
                }
                if !unlinked.isEmpty {
                    Section {
                        ForEach(unlinked) { a in UnlinkedRow(action: a, planner: planner) }
                    } header: { Text("v1 遷移：待連結的事項") } footer: { Text("這些事項在 v1 用目標名稱連結，但名稱找不到或有重複，請手動選擇。") }
                }
                if !closed.isEmpty {
                    Section {
                        DisclosureGroup("已完成與封存（\(closed.count)）", isExpanded: $showClosed) {
                            ForEach(closed) { g in NavigationLink { GoalDetailView(goal: g) } label: { GoalRow(goal: g, planner: planner) } }
                        }
                    }
                }
            }
            .darkCanvas()
            .navigationTitle("目標")
            .toolbar {
                ToolbarItemGroup {
                    Button { showWizard = true } label: { Label("新目標", systemImage: "plus") }
                        .accessibilityIdentifier("goals.new")
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                    SettingsToolbarButton()
                }
            }
            .sheet(isPresented: $showWizard) { GoalWizard() }
        }
    }
}

struct GoalRow: View {
    let goal: Goal
    let planner: Planner

    var body: some View {
        let progress = planner.outcomeProgress(goal)
        let ready = planner.isExecutable(goal)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if goal.isFocus { Image(systemName: "scope").foregroundStyle(Color.assetGreen).accessibilityLabel("焦點") }
                Text(goal.title).bold()
                Spacer()
                Text(goal.horizon.shortLabel).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(progress.text).font(.caption)
                if let d = goal.deadline { Text("期限 \(d.shortDay)").font(.caption) }
                if goal.isOpen && !ready, let missing = planner.missingSetup(goal).label {
                    StatusBadge(text: missing, symbol: "square.dashed", color: .attention)
                        .accessibilityIdentifier("goal.missing")
                }
                if goal.status == .paused, let u = goal.pausedUntil { Text("回看 \(u.shortDay)").font(.caption) }
            }
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct UnlinkedRow: View {
    let action: ActionItem
    let planner: Planner

    var body: some View {
        HStack {
            Text(action.title)
            Spacer()
            Menu("連結到…") {
                ForEach(planner.goals.filter(\.isOpen)) { g in Button(g.title) { planner.link(action, to: g) } }
                Divider()
                Button("保持不連結") { planner.markReviewed(action) }
            }
            .fixedSize()
        }
    }
}

extension Planner {
    /// 遷移報告中無法唯一對應、尚未處理的事項
    func unlinkedMigrationActions() -> [ActionItem] {
        let run = context.all(MigrationRun.self).first { $0.completedAt != nil }
        guard let report = run?.report, !report.unlinked.isEmpty else { return [] }
        let sources = Set(report.unlinked.map(\.sourceID))
        let derived = Set(report.unlinked.map { LegacyMigrationMapper.derivedActionID(forBlock: $0.sourceID) })
        return context.all(ActionItem.self).filter { a in
            a.goalID == nil && a.notes != "已檢視" && (a.legacySourceID.map { sources.contains($0) || derived.contains($0) } ?? false)
        }
    }

    func markReviewed(_ a: ActionItem) {
        a.notes = "已檢視"
        save()
    }
}

// MARK: - 漸進式建立（三步，每步都可存草稿）

struct GoalWizard: View {
    /// V204-TUTORIAL：從教學打開時預先填好範例；使用者仍要自己按下一步才會存
    var example = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var step = 1
    @State private var goal: Goal?

    @State private var title = ""
    @State private var horizon: GoalHorizon = .medium
    @State private var outcome = ""
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
    @State private var milestone = ""
    @State private var strategy = ""
    @State private var nextAction = ""
    @State private var estimate = 25
    @State private var finishResult: SetupFinishResult?

    var body: some View {
        let planner = Planner(context)
        NavigationStack {
            Form {
                switch step {
                case 1:
                    Section {
                        TextField("目標名稱", text: $title).accessibilityIdentifier("wizard.title")
                        Picker("時間尺度", selection: $horizon) { ForEach(GoalHorizon.allCases) { Text($0.label).tag($0) } }
                        TextField("完成時，你會看到什麼？", text: $outcome, axis: .vertical).accessibilityIdentifier("wizard.outcome")
                    } header: { Text("第 1 步（必要）") } footer: { Text("先寫下來就好，之後都能再補。") }
                case 2:
                    Section {
                        Toggle("設定期限", isOn: $hasDeadline)
                        if hasDeadline { DatePicker("期限", selection: $deadline, displayedComponents: .date) }
                        TextField("第一個里程碑（選填）", text: $milestone)
                    } header: { Text("第 2 步（建議，可略過）") }
                case 3:
                    Section {
                        TextField("目前打算怎麼做？（策略）", text: $strategy, axis: .vertical).accessibilityIdentifier("wizard.strategy")
                        TextField("一個 5–90 分鐘能完成的下一步", text: $nextAction).accessibilityIdentifier("wizard.action")
                        Stepper("約 \(formatDuration(estimate))", value: $estimate, in: 5...90, step: 5)
                    } header: { Text("第 3 步（開始安排前）") } footer: { Text("填好策略和下一步後，下一個畫面會問你要不要加入焦點、安排到今天。") }
                default:
                    finishSection(planner)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(step <= 3 ? "新目標 · \(step)/3" : "接下來要怎麼做？")
            .onAppear {
                guard example, title.isEmpty else { return }
                title = Tutorial.exampleGoal
                outcome = Tutorial.exampleOutcome
                strategy = Tutorial.exampleStrategy
                nextAction = Tutorial.exampleAction
                estimate = 25
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step <= 3 { Button(goal == nil ? "取消" : "存成草稿") { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if step <= 3 {
                        Button("下一步") { advance(planner) }
                            .disabled(step == 1 && (title.trimmed.isEmpty || outcome.trimmed.isEmpty))
                            .accessibilityIdentifier("wizard.next")
                    } else {
                        Button("完成") { dismiss() }.accessibilityIdentifier("wizard.done")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    if step == 2 { Button("略過") { step = 3 }.accessibilityIdentifier("wizard.skip") }
                }
            }
        }
        .plannerZoom(minWidth: 460, minHeight: 460)
    }

    /// 第 4 步：一次明確確認（UAT-01）。「稍後」不產生任何副作用。
    @ViewBuilder
    private func finishSection(_ planner: Planner) -> some View {
        if let goal {
            let ready = planner.isExecutable(goal)
            let next = planner.openActions(for: goal.id).first
            Section {
                Text("「\(goal.title)」已建立。").font(.headline)
                if !ready {
                    Text("還缺策略或下一步，目前存成草稿；之後在目標頁補上就能安排。").foregroundStyle(.secondary)
                } else if let next {
                    Text("下一步：\(next.title)（約 \(formatDuration(next.estimateMinutes ?? 30))）")
                    let cap = planner.setupCapacity(for: goal)
                    let preview = cap.assessment
                    Label("\(cap.isEstimate ? "安排前預估" : "今天實際")：容量\(preview.state.label)（已安排 \(formatDuration(preview.loadMinutes))／可承諾 \(formatDuration(preview.committableMinutes))）",
                          systemImage: preview.state.symbol)
                        .font(.callout)
                        .foregroundStyle(preview.state.color)
                        .accessibilityIdentifier("wizard.capacity")
                }
            }
            if let r = finishResult {
                Section { resultText(r, planner: planner) }
            } else if ready {
                let focusCount = planner.focusGoals.count
                Section {
                    Button { finishResult = planner.finishSetup(goal, choice: .focusAndToday) } label: {
                        Label("加入焦點並安排今天", systemImage: "sun.max")
                    }
                    .buttonStyle(.borderedProminent).foregroundStyle(.black)
                    .accessibilityIdentifier("wizard.focusAndToday")
                    Button { finishResult = planner.finishSetup(goal, choice: .focusOnly) } label: {
                        Label("只加入焦點", systemImage: "scope")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("wizard.focusOnly")
                    Button { dismiss() } label: { Label("稍後再決定", systemImage: "clock") }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("wizard.later")
                } footer: {
                    Text(focusCount >= FocusPolicy.hardLimit ? "目前已有 \(focusCount) 個焦點（上限 5）。"
                         : "目前有 \(focusCount) 個焦點，建議最多 3 個。")
                }
            }
        }
    }

    @ViewBuilder
    private func resultText(_ r: SetupFinishResult, planner: Planner) -> some View {
        switch r.focus {
        case .some(.blocked):
            Text("焦點已經有 5 個，沒有加入。可以只先排進今天，或到目標頁替換一個焦點。")
            Button("只安排今天（不加入焦點）") { finishResult = planner.finishSetup(goal!, choice: .todayOnly) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("wizard.todayOnly")
        case .some(.needsStrategyAndAction):
            Text("還缺策略或下一步，先存成草稿。")
        default:
            let parts = [r.focus == nil ? nil : "已加入焦點", r.plannedToday ? "已排進今天" : nil].compactMap { $0 }
            Label(parts.isEmpty ? "完成" : parts.joined(separator: "，") + "。", systemImage: "checkmark.circle")
                .foregroundStyle(Color.assetGreen)
            if case .some(.focusedAboveRecommended(let n)) = r.focus {
                Text("目前有 \(n) 個焦點，超過建議的 3 個；每個目標每天分到的時間會變少。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func advance(_ planner: Planner) {
        switch step {
        case 1:
            goal = planner.createGoal(title: title, horizon: horizon, outcome: outcome)
            step = 2
        case 2:
            if let goal {
                if hasDeadline { planner.changeDeadline(goal, to: deadline, reason: "建立目標時設定") }
                if !milestone.trimmed.isEmpty { planner.addMilestone(goal, title: milestone, targetDate: nil) }
            }
            step = 3
        default:
            if let goal {
                if !strategy.trimmed.isEmpty { planner.addStrategy(goal, title: strategy) }
                if !nextAction.trimmed.isEmpty {
                    planner.addAction(title: nextAction, kind: .personal, goal: goal, estimate: estimate)
                }
            }
            step = 4
        }
    }
}
