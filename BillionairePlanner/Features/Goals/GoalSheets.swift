import SwiftUI
import SwiftData
import PlannerCore

/// 目標頁的各種小表單（都只做使用者明確確認的修改）
struct GoalEditSheets: View {
    let goal: Goal
    let kind: GoalDetailView.GoalSheet
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text1 = ""
    @State private var text2 = ""
    @State private var horizon: GoalHorizon = .medium
    @State private var minutes: Int? = nil
    @State private var date = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var hasDate = false
    @State private var number: Double = 1
    @State private var evidenceKind: EvidenceKind = .note
    @State private var target: Double? = nil
    @State private var unit = ""

    var body: some View {
        let planner = Planner(context)
        NavigationStack {
            Form { form(planner) }
                .formStyle(.grouped)
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("儲存") { save(planner); dismiss() }.disabled(!canSave)
                    }
                }
                .onAppear { load(planner) }
        }
        .frame(minWidth: 420, minHeight: 380)
    }

    private var title: String {
        switch kind {
        case .edit: "編輯目標"
        case .action: "新增下一步"
        case .strategy: "新增策略"
        case .switchStrategy: "換一個策略"
        case .milestone: "新增里程碑"
        case .evidence: "記錄成果"
        case .deadline: "調整期限"
        case .pause: "暫停目標"
        case .restart: "開始新週期"
        }
    }

    private var canSave: Bool {
        switch kind {
        case .edit: !text1.trimmed.isEmpty
        case .action, .strategy, .switchStrategy, .milestone: !text1.trimmed.isEmpty
        case .evidence: evidenceKind == .numeric || !text1.trimmed.isEmpty
        default: true
        }
    }

    @ViewBuilder
    private func form(_ planner: Planner) -> some View {
        switch kind {
        case .edit:
            TextField("目標名稱", text: $text1)
            Picker("時間尺度", selection: $horizon) { ForEach(GoalHorizon.allCases) { Text($0.label).tag($0) } }
            TextField("完成時會看到什麼？", text: $text2, axis: .vertical)
            Section("可量化的成果（選填）") {
                Toggle("設定數值目標", isOn: Binding(get: { target != nil }, set: { target = $0 ? (target ?? 10) : nil }))
                if let t = target {
                    TextField("目標值", value: Binding(get: { t }, set: { target = $0 }), format: .number)
                    TextField("單位（例：本、公里、萬元）", text: $unit)
                }
            }
        case .action:
            TextField("下一步（5–90 分鐘能完成）", text: $text1)
            OptionalMinutesField(title: "預估時間", minutes: $minutes, range: 5...180)
            if minutes == nil, let s = planner.estimateSuggestion(title: text1, goalID: goal.id, kind: .personal, userEstimate: nil) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("建議 \(s.minutes) 分").bold()
                        Text(s.basis).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("採用") { minutes = s.minutes }
                }
            }
            TextField("縮小版本（真的很忙時怎麼做？選填）", text: $text2)
        case .strategy:
            TextField("策略：打算怎麼做", text: $text1, axis: .vertical)
            TextField("假設：為什麼覺得有效（選填）", text: $text2, axis: .vertical)
        case .switchStrategy:
            TextField("新策略", text: $text1, axis: .vertical)
            TextField("換掉的原因（選填）", text: $text2, axis: .vertical)
            Text("舊策略的行動與成果都會保留，目標的累積進度不會歸零。").font(.caption).foregroundStyle(.secondary)
        case .milestone:
            TextField("里程碑", text: $text1)
            Toggle("目標日期", isOn: $hasDate)
            if hasDate { DatePicker("日期", selection: $date, displayedComponents: .date) }
        case .evidence:
            Picker("種類", selection: $evidenceKind) { ForEach(EvidenceKind.allCases) { Text($0.label).tag($0) } }
                .pickerStyle(.segmented)
            if evidenceKind == .numeric {
                TextField("數值", value: $number, format: .number)
                if !goal.outcomeUnit.isEmpty { Text("單位：\(goal.outcomeUnit)").font(.caption) }
            }
            TextField(evidenceKind == .checkpoint ? "達成了哪個檢查點？" : "發生了什麼成果？", text: $text1, axis: .vertical)
        case .deadline:
            Toggle("有期限", isOn: $hasDate)
            if hasDate { DatePicker("新期限", selection: $date, displayedComponents: .date) }
            TextField("原因（選填）", text: $text1)
            Text("原本的期限與這次調整都會留在期限歷史中。").font(.caption).foregroundStyle(.secondary)
        case .pause:
            Toggle("設定回看日期", isOn: $hasDate)
            if hasDate { DatePicker("回看日", selection: $date, displayedComponents: .date) }
            TextField("原因（選填）", text: $text1)
            Text("暫停期間不會因為沒進度而提醒你。").font(.caption).foregroundStyle(.secondary)
        case .restart:
            TextField("想重新開始的原因（選填）", text: $text1, axis: .vertical)
            Text("會從今天起算新週期。過去的成果、里程碑、策略和回顧全部保留，累積成果不歸零。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func load(_ planner: Planner) {
        switch kind {
        case .edit:
            text1 = goal.title
            text2 = goal.outcomeDescription
            horizon = goal.horizon
            target = goal.outcomeTarget
            unit = goal.outcomeUnit
        case .deadline:
            hasDate = goal.deadline != nil
            if let d = goal.deadline { date = d }
        default: break
        }
    }

    private func save(_ planner: Planner) {
        switch kind {
        case .edit:
            goal.title = text1.trimmed
            goal.outcomeDescription = text2.trimmed
            goal.horizon = horizon
            goal.outcomeTarget = target
            goal.outcomeUnit = unit.trimmed
            planner.save()
        case .action:
            let a = planner.addAction(title: text1, kind: .personal, goal: goal, estimate: minutes)
            if !text2.trimmed.isEmpty {
                a.minimumVersion = text2.trimmed
                planner.save()
            }
        case .strategy:
            planner.addStrategy(goal, title: text1, hypothesis: text2)
        case .switchStrategy:
            planner.switchStrategy(goal, toTitle: text1, reason: text2)
        case .milestone:
            planner.addMilestone(goal, title: text1, targetDate: hasDate ? date : nil)
        case .evidence:
            planner.recordEvidence(goal, kind: evidenceKind, value: evidenceKind == .numeric ? number : nil, note: text1)
        case .deadline:
            planner.changeDeadline(goal, to: hasDate ? date : nil, reason: text1)
        case .pause:
            planner.pause(goal, until: hasDate ? date : nil, reason: text1)
        case .restart:
            planner.restartCycle(goal, reason: text1)
        }
    }
}

// MARK: - 恢復方案（最小改動優先，PRD 7.10）

struct RecoverySheet: View {
    let episode: RecoveryEpisode
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var option: RecoveryOption?
    @State private var reason = ""
    @State private var actionID: UUID?
    @State private var minutes = 15
    @State private var small = ""
    @State private var newStrategy = ""
    @State private var date = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var hasDate = true

    var body: some View {
        let planner = Planner(context)
        let goal = planner.goal(episode.goalID)
        let options = RecoveryPlanner.rankedOptions(hasDeadlineOrMilestone: true)
        NavigationStack {
            Form {
                Section("為什麼出現這個建議") {
                    ForEach(episode.signals, id: \.evidence) { Text($0.evidence) }
                    if episode.signals.isEmpty { Text("你主動要求調整。") }
                }
                Section {
                    ForEach(options, id: \.self) { o in
                        Button { option = o } label: {
                            HStack(alignment: .top) {
                                Image(systemName: o.symbol).frame(width: 24)
                                VStack(alignment: .leading) {
                                    Text(o.title).bold()
                                    Text(o.explanation).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if option == o { Image(systemName: "checkmark").foregroundStyle(Color.assetGreen) }
                            }
                        }
                        .buttonStyle(.borderless)
                        .accessibilityAddTraits(option == o ? .isSelected : [])
                    }
                } header: { Text("從改動最小的開始") }

                if let option, let goal {
                    Section("細節") { detail(option, goal: goal, planner: planner) }
                    Section {
                        TextField("原因（選填）", text: $reason)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(goal.map { "「\($0.title)」的恢復方案" } ?? "恢復方案")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("先不改") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("確認") {
                        if let option, let goal { apply(option, goal: goal, planner: planner) }
                        dismiss()
                    }
                    .disabled(option == nil)
                }
            }
            .onAppear {
                if let g = goal { actionID = planner.openActions(for: g.id).first?.id }
            }
        }
        .frame(minWidth: 480, minHeight: 560)
    }

    @ViewBuilder
    private func detail(_ o: RecoveryOption, goal: Goal, planner: Planner) -> some View {
        switch o {
        case .shrinkNextStep:
            Picker("哪一個下一步", selection: $actionID) {
                ForEach(planner.openActions(for: goal.id)) { Text($0.title).tag(UUID?.some($0.id)) }
            }
            Stepper("縮成約 \(minutes) 分", value: $minutes, in: 5...60, step: 5)
            TextField("縮小版本長什麼樣子？", text: $small)
        case .reduceFrequency:
            TextField("這週打算安排幾次、每次多久？", text: $reason, axis: .vertical)
        case .switchStrategy:
            TextField("新策略", text: $newStrategy, axis: .vertical)
        case .moveMilestoneOrDeadline:
            Toggle("有期限", isOn: $hasDate)
            if hasDate { DatePicker("新期限", selection: $date, displayedComponents: .date) }
            Text("原期限 \(goal.deadline?.shortDay ?? "無") 會保留在歷史中。").font(.caption).foregroundStyle(.secondary)
        case .pauseWithReviewDate:
            DatePicker("回看日", selection: $date, displayedComponents: .date)
        case .restartCycle:
            Text("從今天起算新週期，累積成果保留。").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func apply(_ o: RecoveryOption, goal: Goal, planner: Planner) {
        switch o {
        case .shrinkNextStep:
            if let a = planner.openActions(for: goal.id).first(where: { $0.id == actionID }) {
                planner.shrink(a, toMinutes: minutes, description: small)
            }
            planner.resolve(episode, with: o, reason: reason)
        case .reduceFrequency:
            planner.resolve(episode, with: o, reason: reason)
        case .switchStrategy:
            if !newStrategy.trimmed.isEmpty { planner.switchStrategy(goal, toTitle: newStrategy, reason: reason) }
            planner.resolve(episode, with: o, reason: reason)
        case .moveMilestoneOrDeadline:
            planner.changeDeadline(goal, to: hasDate ? date : nil, reason: reason, recoveryEpisodeID: episode.id)
            planner.resolve(episode, with: o, reason: reason)
        case .pauseWithReviewDate:
            planner.pause(goal, until: date, reason: reason)
            planner.resolve(episode, with: o, reason: reason)
        case .restartCycle:
            planner.restartCycle(goal, reason: reason, episode: episode)
        }
    }
}

// MARK: - 遷移報告

struct MigrationReportView: View {
    let report: MigrationReport
    var isFirstRun = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if isFirstRun {
                Section {
                    Text("v1 的資料已經搬到 v2。原本的 v1 資料沒有被修改，另外也做了備份。")
                }
            }
            Section("匯入結果") {
                ForEach(report.summaryLines, id: \.self) { Text($0).font(.callout) }
            }
            if !report.warnings.isEmpty {
                Section("需要留意") { ForEach(report.warnings, id: \.self) { Text($0) } }
            }
            if !report.unlinked.isEmpty {
                Section {
                    ForEach(report.unlinked, id: \.sourceID) { u in
                        VStack(alignment: .leading) {
                            Text(u.itemTitle)
                            Text("原本連結「\(u.goalTitle)」：\(u.reason)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("待連結") } footer: { Text("可以在「目標」頁最下方逐一連結。") }
            }
            Section("備份位置") {
                Text(StoreLocation.backups.path).font(.caption).textSelection(.enabled)
            }
        }
        .navigationTitle("v1 遷移報告")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("知道了") { dismiss() } } }
        .frame(minWidth: 460, minHeight: 420)
    }
}
