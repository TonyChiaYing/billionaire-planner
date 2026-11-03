import SwiftUI
import SwiftData
import PlannerCore

struct GoalDetailView: View {
    let goal: Goal
    @Environment(\.modelContext) private var context
    @Environment(\.dataVersion) private var dataVersion

    @State private var cycleOnly = false
    @State private var sheet: GoalSheet?
    @State private var focusAlert: FocusRequestResult?
    @State private var showReplace = false
    @State private var recovery: RecoveryEpisode?

    enum GoalSheet: String, Identifiable {
        case edit, action, strategy, switchStrategy, milestone, evidence, deadline, pause, restart
        var id: String { rawValue }
    }

    var body: some View {
        let _ = dataVersion
        let planner = Planner(context)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(planner)
                if let e = planner.openEpisode(for: goal) { recoveryCard(e, planner: planner) }
                progressCard(planner)
                nextActionsCard(planner)
                strategyCard(planner)
                milestonesCard(planner)
                evidenceCard(planner)
                deadlineCard(planner)
                lifecycleCard(planner)
            }
            .padding()
        }
        .background(Color.black)
        .navigationTitle(goal.title)
        .toolbar {
            ToolbarItem {
                Button { sheet = .edit } label: { Label("編輯", systemImage: "pencil") }
            }
        }
        .sheet(item: $sheet) { s in GoalEditSheets(goal: goal, kind: s) }
        .sheet(item: $recovery) { RecoverySheet(episode: $0) }
        .sheet(isPresented: $showReplace) { FocusReplaceSheet(newGoal: goal) }
        .alert(focusAlertTitle, isPresented: Binding(get: { focusAlert != nil }, set: { if !$0 { focusAlert = nil } })) {
            if focusAlert == .blocked {
                Button("選一個替換") { showReplace = true }
                Button("先不要", role: .cancel) {}
            } else if focusAlert == .needsStrategyAndAction {
                Button("補上策略") { sheet = .strategy }
                Button("新增下一步") { sheet = .action }
                Button("稍後", role: .cancel) {}
            } else {
                Button("好", role: .cancel) {}
            }
        } message: {
            Text(focusAlertMessage)
        }
    }

    private var focusAlertTitle: String {
        switch focusAlert {
        case .blocked: "已經有 5 個焦點"
        case .needsStrategyAndAction: "還差一步"
        case .focusedAboveRecommended: "已加入焦點"
        default: ""
        }
    }

    private var focusAlertMessage: String {
        switch focusAlert {
        case .blocked: "可以選一個現有焦點改為一般目標（不會刪除或改動它），或先不加入。"
        case .needsStrategyAndAction: "加入焦點前，需要一個目前策略和一個可以執行的下一步。"
        case .focusedAboveRecommended(let n): "目前有 \(n) 個焦點，超過建議的 3 個；每個目標每天能分到的容量會變少。"
        default: ""
        }
    }

    // MARK: Header

    private func header(_ planner: Planner) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusBadge(text: goal.status.label, symbol: "circle.fill", color: goal.status == .active ? .assetGreen : .guardGray)
                Text(goal.horizon.label).font(.caption).foregroundStyle(.secondary)
                if goal.cycleNumber > 1 { Text("第 \(goal.cycleNumber) 個週期").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if goal.isOpen {
                    Button {
                        if goal.isFocus { planner.unfocus(goal) } else { focusAlert = planner.requestFocus(goal) }
                        if focusAlert == .focused { focusAlert = nil }
                    } label: {
                        Label(goal.isFocus ? "焦點中" : "加入焦點", systemImage: goal.isFocus ? "scope" : "plus.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text(goal.outcomeDescription.isEmpty ? "尚未寫下「完成時會看到什麼」" : goal.outcomeDescription)
                .foregroundStyle(goal.outcomeDescription.isEmpty ? Color.secondary : Color.primary)
            if goal.migratedFromV1 && goal.outcomeDescription.isEmpty {
                Text("這是從 v1 匯入的目標，可以按「編輯」補上成果描述。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func recoveryCard(_ e: RecoveryEpisode, planner: Planner) -> some View {
        Card(title: "這個目標可能需要更小的路徑", symbol: "lightbulb") {
            ForEach(e.signals, id: \.evidence) { s in Text("· \(s.evidence)").font(.callout) }
            HStack {
                Button("看看恢復方案") { recovery = e }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                Button("過幾天再說") { planner.snooze(e, days: 3) }.buttonStyle(.bordered)
                Button("關閉") { planner.dismiss(e) }.buttonStyle(.borderless)
            }
        }
    }

    // MARK: 雙重進度（AC-04）

    private func progressCard(_ planner: Planner) -> some View {
        let outcome = planner.outcomeProgress(goal, cycleOnly: cycleOnly)
        let trend = planner.actionTrend(goal)
        return Card(title: "進度（兩種不同指標）", symbol: "chart.bar.xaxis") {
            if goal.cycleNumber > 1 {
                Picker("範圍", selection: $cycleOnly) {
                    Text("累積成果").tag(false)
                    Text("本次恢復週期").tag(true)
                }
                .pickerStyle(.segmented)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("成果", systemImage: "flag.checkered").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(outcome.text).font(.title3.bold())
                    if let f = outcome.fraction {
                        ProgressView(value: f).tint(.assetGreen).accessibilityLabel("成果進度 \(Int(f * 100))%")
                    }
                    Text("真正達成了什麼").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label("行動證據", systemImage: "figure.walk").font(.caption.bold()).foregroundStyle(.secondary)
                    Text("近 7 天完成 \(trend.done7) 項").font(.callout)
                    Text("近 30 天完成 \(trend.done30) 項 · 投入 \(formatDuration(trend.minutes30))").font(.caption)
                    Text("近 7 天安排 \(trend.planned7) 次").font(.caption).foregroundStyle(.secondary)
                    Text("做了多少，不等於達成多少").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 下一步

    private func nextActionsCard(_ planner: Planner) -> some View {
        let open = planner.openActions(for: goal.id)
        let today = planner.today
        let placed = Set(planner.placements(on: today).filter(\.isActiveToday).map(\.actionID))
        return Card(title: "下一步", symbol: "arrow.right.circle") {
            if open.isEmpty { EmptyHint(text: "加一個 5–90 分鐘能完成的下一步。") }
            ForEach(open) { a in
                HStack {
                    VStack(alignment: .leading) {
                        Text(a.title)
                        HStack(spacing: 6) {
                            if let m = a.estimateMinutes { Text("約 \(formatDuration(m))") }
                            if !a.minimumVersion.isEmpty { Text("縮小版：\(a.minimumVersion)") }
                            if a.carryoverCount > 0 { Text("延續 \(a.carryoverCount) 次") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if placed.contains(a.id) {
                        Text("今天已安排").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("加入今天") { planner.plan(a, on: today) }.buttonStyle(.bordered)
                    }
                }
            }
            Button { sheet = .action } label: { Label("新增下一步", systemImage: "plus") }
        }
    }

    // MARK: 動態策略（AC-03）

    private func strategyCard(_ planner: Planner) -> some View {
        let all = planner.strategies(for: goal.id)
        let active = all.last { $0.status == .active }
        let history = all.filter { $0.id != active?.id }.reversed()
        return Card(title: "策略", symbol: "arrow.triangle.branch") {
            if let active {
                Text(active.title).font(.headline)
                if !active.hypothesis.isEmpty { Text(active.hypothesis).font(.caption).foregroundStyle(.secondary) }
                Text("從 \(active.startedAt.shortDay) 開始").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("換一個策略") { sheet = .switchStrategy }.buttonStyle(.bordered)
                    Button("暫停這個策略") { planner.setStrategy(active, status: .paused, reason: "") }.buttonStyle(.borderless)
                }
            } else {
                EmptyHint(text: "還沒有使用中的策略。")
                Button { sheet = .strategy } label: { Label("新增策略", systemImage: "plus") }
            }
            if !history.isEmpty {
                DisclosureGroup("策略歷史（\(history.count)）") {
                    ForEach(Array(history)) { s in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(s.title)
                                Text("\(s.status.label) · \(s.startedAt.shortDay)\(s.endedAt.map { "–\($0.shortDay)" } ?? "")\(s.decisionReason.isEmpty ? "" : " · \(s.decisionReason)")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if s.status == .paused || s.status == .proposed {
                                Button("改用") { planner.activate(s, in: goal) }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 里程碑

    private func milestonesCard(_ planner: Planner) -> some View {
        let ms = planner.milestones(for: goal.id)
        return Card(title: "里程碑", symbol: "flag") {
            if ms.isEmpty { EmptyHint(text: "可驗證的中間成果，例如「讀完第 3 本」。") }
            ForEach(ms) { m in
                Button { planner.setMilestone(m, done: m.completedAt == nil) } label: {
                    HStack {
                        Image(systemName: m.completedAt == nil ? "circle" : "checkmark.circle.fill")
                            .foregroundStyle(m.completedAt == nil ? Color.secondary : Color.assetGreen)
                        Text(m.title)
                        Spacer()
                        if let d = m.targetDate { Text(d.shortDay).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(m.title)，\(m.completedAt == nil ? "未完成" : "已完成")")
            }
            Button { sheet = .milestone } label: { Label("新增里程碑", systemImage: "plus") }
        }
    }

    // MARK: 成果紀錄

    private func evidenceCard(_ planner: Planner) -> some View {
        let ev = planner.evidence(for: goal.id)
        return Card(title: "成果紀錄", symbol: "checkmark.seal") {
            if ev.isEmpty { EmptyHint(text: "記下真正的成果（數值、檢查點或一句話）。") }
            ForEach(ev.prefix(10)) { e in
                HStack {
                    Text(e.value.map { "\($0.formatted()) \(e.unit)" } ?? e.kind.label).bold()
                    Text(e.note).lineLimit(2)
                    Spacer()
                    Text(e.recordedAt.shortDay).font(.caption).foregroundStyle(.secondary)
                }
                .contextMenu { Button("標為記錯（保留紀錄）") { planner.reverse(e) } }
            }
            Button { sheet = .evidence } label: { Label("記錄成果", systemImage: "plus") }
        }
    }

    // MARK: 期限（AC-13）

    private func deadlineCard(_ planner: Planner) -> some View {
        let history = planner.deadlineHistory(for: goal.id)
        let risk = planner.deadlineRisk(goal)
        return Card(title: "期限", symbol: "calendar") {
            HStack {
                Text(goal.deadline.map { $0.formatted(date: .long, time: .omitted) } ?? "沒有固定期限")
                Spacer()
                if risk != .none { Text(risk.label).font(.caption).foregroundStyle(.secondary) }
            }
            Button("調整期限") { sheet = .deadline }.buttonStyle(.bordered)
            if !history.isEmpty {
                DisclosureGroup("期限歷史（\(history.count)）") {
                    ForEach(history) { r in
                        VStack(alignment: .leading) {
                            Text("\(r.oldDeadline?.shortDay ?? "無") → \(r.newDeadline?.shortDay ?? "無")")
                            Text("\(r.changedAt.formatted(date: .abbreviated, time: .shortened))\(r.reason.isEmpty ? "" : " · \(r.reason)")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: 生命週期

    private func lifecycleCard(_ planner: Planner) -> some View {
        Card(title: "調整這個目標", symbol: "slider.horizontal.3") {
            HStack {
                switch goal.status {
                case .paused:
                    Button("恢復") { planner.resume(goal) }.buttonStyle(.bordered)
                case .completed, .archived:
                    Button("重新開啟") { planner.reopen(goal) }.buttonStyle(.bordered)
                default:
                    Button("有意識地暫停") { sheet = .pause }.buttonStyle(.bordered)
                    Button("標為完成") { planner.complete(goal) }.buttonStyle(.bordered)
                }
                Button("開始新週期") { sheet = .restart }.buttonStyle(.bordered)
                if goal.status != .archived { Button("封存") { planner.archive(goal) }.buttonStyle(.borderless) }
            }
            Text("任何調整都會保留過去的成果與歷史。").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 焦點已滿：選一個替換（AC-02）

struct FocusReplaceSheet: View {
    let newGoal: Goal
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let planner = Planner(context)
        NavigationStack {
            List {
                Section {
                    ForEach(planner.focusGoals) { g in
                        Button { planner.replaceFocus(g, with: newGoal); dismiss() } label: {
                            HStack {
                                Text(g.title)
                                Spacer()
                                Text("改為一般目標").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: { Text("被替換的目標不會被刪除或修改，只是暫時不佔焦點位置。") }
            }
            .navigationTitle("用「\(newGoal.title)」替換")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .frame(minWidth: 400, minHeight: 360)
    }
}
