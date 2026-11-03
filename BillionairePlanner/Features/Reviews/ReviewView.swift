import SwiftUI
import SwiftData
import PlannerCore

struct ReviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dataVersion) private var dataVersion
    @State private var sheet: ReviewSheet?
    @State private var report: ReportBox?

    enum ReviewSheet: String, Identifiable {
        case workClose, evening, draft, weekly, principle
        var id: String { rawValue }
    }

    var body: some View {
        let _ = dataVersion
        let planner = Planner(context)
        let day = planner.today
        let r = planner.existingReview(for: day)
        let migration = planner.context.all(MigrationRun.self).first { $0.completedAt != nil }?.report

        NavigationStack {
            List {
                Section {
                    stepRow("下班整理", detail: "工作收尾，約 1–2 分鐘", done: r?.workClosedAt, symbol: "briefcase") { sheet = .workClose }
                    stepRow("晚間日結", detail: "確認今天、記下成果，約 2–4 分鐘", done: r?.eveningClosedAt, symbol: "moon.stars") { sheet = .evening }
                    stepRow("明日草案", detail: r?.draftAcceptedAt == nil ? "根據今天的紀錄產生，可逐項接受" : "已接受部分草案",
                            done: r?.draftAcceptedAt, symbol: "sunrise") { sheet = .draft }
                } header: { Text("今天") } footer: { Text("沒有進度或休息日也可以完成日結，不會中斷任何紀錄。") }

                Section("每週") {
                    let w = planner.context.all(WeeklyReview.self).first { $0.weekStartKey == planner.weekStart.description }
                    stepRow("每週回顧", detail: "成果與行動趨勢、策略決定、下週容量", done: w?.completedAt, symbol: "calendar") { sheet = .weekly }
                }

                Section {
                    let principles = planner.context.all(Principle.self).sorted { $0.createdAt > $1.createdAt }
                    if principles.isEmpty { EmptyHint(text: "從回顧中提煉的做事原則會累積在這裡。") }
                    ForEach(principles.prefix(20)) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.text).bold()
                            if !p.painPoint.isEmpty { Text("起因：\(p.painPoint)").font(.caption).foregroundStyle(.secondary) }
                            HStack(spacing: 6) {
                                if !p.rootCause.isEmpty { Text("[\(p.causeType)] \(p.rootCause)") }
                                if let g = planner.goal(p.goalID) { Text("· \(g.title)") }
                                if !p.contextTag.isEmpty { Text("· \(p.contextTag)") }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button { sheet = .principle } label: { Label("寫下一條原則", systemImage: "plus") }
                } header: { Text("原則（痛苦＋反思＝進步）") }

                Section("最近的成果") {
                    let ev = planner.context.all(OutcomeEvidence.self).filter { !$0.isReversed }.sorted { $0.recordedAt > $1.recordedAt }
                    if ev.isEmpty { EmptyHint(text: "還沒有成果紀錄。") }
                    ForEach(ev.prefix(15)) { e in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(e.note.isEmpty ? e.kind.label : e.note)
                                Text(planner.goal(e.goalID)?.title ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let v = e.value { Text("\(v.formatted()) \(e.unit)").font(.callout.monospacedDigit()) }
                            Text(e.recordedAt.shortDay).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if let migration {
                    Section {
                        Button { report = ReportBox(report: migration) } label: { Label("v1 遷移報告", systemImage: "doc.text") }
                    }
                }
            }
            .darkCanvas()
            .navigationTitle("回顧")
            .toolbar { ToolbarItem { SettingsToolbarButton() } }
            .sheet(item: $sheet) { s in
                switch s {
                case .workClose: WorkCloseSheet(day: day)
                case .evening: EveningCloseSheet(day: day, openDraft: { sheet = .draft })
                case .draft: TomorrowDraftSheet(day: day)
                case .weekly: WeeklyReviewSheet()
                case .principle: PrincipleSheet()
                }
            }
            .sheet(item: $report) { box in NavigationStack { MigrationReportView(report: box.report) } }
        }
    }

    private func stepRow(_ title: String, detail: String, done: Date?, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: done == nil ? symbol : "checkmark.circle.fill")
                    .foregroundStyle(done == nil ? Color.secondary : Color.assetGreen)
                    .frame(width: 24)
                VStack(alignment: .leading) {
                    Text(title).bold()
                    Text(done.map { "完成於 \($0.formatted(date: .omitted, time: .shortened))" } ?? detail)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 下班整理

struct WorkCloseSheet: View {
    let day: LocalDay
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [UUID: WorkCloseChoice] = [:]
    @State private var dates: [UUID: Date] = [:]
    @State private var squeezed = ""

    var body: some View {
        let planner = Planner(context)
        let items = planner.openWorkItems(on: day)
        let actions = planner.actionMap()
        NavigationStack {
            Form {
                Section {
                    if items.isEmpty { Text("今天的工作都有去向了。").foregroundStyle(.secondary) }
                    ForEach(items) { p in
                        VStack(alignment: .leading) {
                            Text(actions[p.actionID]?.title ?? "").bold()
                            Picker("去向", selection: Binding(get: { choices[p.id] ?? .tomorrow }, set: { choices[p.id] = $0 })) {
                                ForEach(WorkCloseChoice.allCases) { Text($0.label).tag($0) }
                            }
                            if (choices[p.id] ?? .tomorrow) == .laterDate {
                                DatePicker("日期", selection: Binding(get: { dates[p.id] ?? Date().addingTimeInterval(2 * 86_400) },
                                                                    set: { dates[p.id] = $0 }), displayedComponents: .date)
                            }
                        }
                    }
                } header: { Text("未完成的工作") } footer: { Text("每一項都選一個去向；預設是延續到明天。") }
                Section("工作有沒有擠壓到個人時間？（可略過）") {
                    TextField("例：臨時會議佔掉了晚上的閱讀", text: $squeezed, axis: .vertical)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("下班整理")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("稍後") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        var all = choices
                        for p in items where all[p.id] == nil { all[p.id] = .tomorrow }
                        planner.closeWork(day: day, choices: all, dates: dates, squeezedNote: squeezed)
                        Notifier.sync(context)
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 440)
    }
}

// MARK: - 晚間日結

struct EveningCloseSheet: View {
    let day: LocalDay
    var openDraft: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var confirmedDone: Set<UUID> = []
    @State private var outcomeSelected: Set<UUID> = []
    @State private var outcomeNotes: [UUID: String] = [:]
    @State private var extraGoalID: UUID?
    @State private var extraNote = ""
    @State private var isRestDay = false
    @State private var energy = 0
    @State private var blockers = ""
    @State private var blocked: Set<UUID> = []
    @State private var principle = ""
    @State private var note = ""

    var body: some View {
        let planner = Planner(context)
        let actions = planner.actionMap()
        let unfinished = planner.placements(on: day).filter { !$0.isDone && $0.isActiveToday }
        let candidates = planner.outcomeCandidates(on: day)
        NavigationStack {
            Form {
                Section {
                    if unfinished.isEmpty { Text("今天的安排都確認過了。").foregroundStyle(.secondary) }
                    ForEach(unfinished) { p in
                        Toggle(isOn: Binding(get: { confirmedDone.contains(p.id) },
                                             set: { if $0 { confirmedDone.insert(p.id) } else { confirmedDone.remove(p.id) } })) {
                            Text(actions[p.actionID]?.title ?? "")
                        }
                    }
                } header: { Text("1. 今天實際做完了哪些？") } footer: { Text("沒勾的會成為明日草案的延續候選。") }

                Section {
                    Toggle("今天是休息日／沒有可量化的進度", isOn: $isRestDay)
                    if !isRestDay {
                        ForEach(candidates) { c in
                            Toggle(isOn: Binding(get: { outcomeSelected.contains(c.placement.id) },
                                                 set: { if $0 { outcomeSelected.insert(c.placement.id) } else { outcomeSelected.remove(c.placement.id) } })) {
                                VStack(alignment: .leading) {
                                    Text(c.action.title)
                                    Text(c.goal.title).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if outcomeSelected.contains(c.placement.id) {
                                TextField("成果是什麼？（例：讀完第 3 章）", text: Binding(get: { outcomeNotes[c.placement.id] ?? "" },
                                                                                set: { outcomeNotes[c.placement.id] = $0 }))
                            }
                        }
                        Picker("其他成果的目標", selection: $extraGoalID) {
                            Text("不記錄").tag(UUID?.none)
                            ForEach(planner.goals.filter(\.isOpen)) { Text($0.title).tag(UUID?.some($0.id)) }
                        }
                        if extraGoalID != nil { TextField("其他成果", text: $extraNote) }
                    }
                } header: { Text("2. 記下至少一項成果") } footer: { Text("完成行動不等於成果；只勾選真的有推進的。") }

                Section("3. 選填") {
                    Picker("精力", selection: $energy) {
                        Text("略過").tag(0)
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("今天卡住的地方", text: $blockers, axis: .vertical)
                    if !blockers.trimmed.isEmpty {
                        ForEach(planner.focusGoals) { g in
                            Toggle("「\(g.title)」受阻", isOn: Binding(get: { blocked.contains(g.id) },
                                                                    set: { if $0 { blocked.insert(g.id) } else { blocked.remove(g.id) } }))
                        }
                    }
                    TextField("值得保留的原則", text: $principle, axis: .vertical)
                    TextField("其他筆記", text: $note, axis: .vertical)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("晚間日結")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("稍後") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成日結") {
                        for p in unfinished where confirmedDone.contains(p.id) { planner.complete(p) }
                        var evidence: [EveningEvidenceInput] = []
                        if !isRestDay {
                            for c in candidates where outcomeSelected.contains(c.placement.id) {
                                evidence.append(EveningEvidenceInput(goalID: c.goal.id, kind: .note, value: nil,
                                                                     note: outcomeNotes[c.placement.id] ?? c.action.title, actionID: c.action.id))
                            }
                            if let g = extraGoalID, !extraNote.trimmed.isEmpty {
                                evidence.append(EveningEvidenceInput(goalID: g, kind: .note, value: nil, note: extraNote, actionID: nil))
                            }
                        }
                        planner.closeEvening(day: day, evidence: evidence, energy: energy == 0 ? nil : energy, blockers: blockers,
                                             blockedGoalIDs: Array(blocked), principle: principle, isRestDay: isRestDay, note: note)
                        dismiss()
                        openDraft()
                    }
                }
            }
            .onAppear {
                for c in candidates { outcomeSelected.insert(c.placement.id) }
            }
        }
        .frame(minWidth: 460, minHeight: 600)
    }
}

// MARK: - 明日草案（建議，不自動承諾）

struct TomorrowDraftSheet: View {
    let day: LocalDay
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID> = []
    @State private var loaded = false

    var body: some View {
        let planner = Planner(context)
        let draft = planner.tomorrowDraft(from: day)
        let chosenMinutes = (draft.included + draft.excluded).filter { selected.contains($0.id) && $0.candidate.source != .lockedCommitment }
            .reduce(0) { $0 + $1.candidate.minutes }
        let lockedMinutes = draft.included.filter { $0.candidate.source == .lockedCommitment }.reduce(0) { $0 + $1.candidate.minutes }
        let over = chosenMinutes + lockedMinutes - draft.capacity.committableMinutes
        NavigationStack {
            Form {
                Section {
                    HStack {
                        CapacityBadge(state: draft.capacity.state)
                        Spacer()
                        Text("可承諾 \(formatDuration(draft.capacity.committableMinutes)) · 已選 \(formatDuration(chosenMinutes + lockedMinutes))")
                            .font(.callout.monospacedDigit())
                    }
                    if over > 0 {
                        Label("勾選的項目比可承諾容量多 \(formatDuration(over))，建議縮小或少選幾項。", systemImage: "exclamationmark.circle")
                            .foregroundStyle(Color.attention)
                    }
                } header: { Text("明天的容量") }

                Section("固定與保護") {
                    ForEach(draft.fixed) { e in
                        HStack {
                            Text(e.candidate.title)
                            Spacer()
                            Text("\(e.candidate.source.label) · \(formatDuration(e.candidate.minutes))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if draft.fixed.isEmpty { Text("明天沒有工作模板區段。").foregroundStyle(.secondary) }
                }

                Section {
                    ForEach(draft.included) { e in entryRow(e) }
                    if draft.included.isEmpty { Text("沒有需要承諾的項目。").foregroundStyle(.secondary) }
                } header: { Text("建議承諾") }

                if !draft.excluded.isEmpty {
                    Section {
                        ForEach(draft.excluded) { e in entryRow(e) }
                    } header: { Text("這次裝不下") } footer: { Text("沒選的項目不會消失，之後仍可安排。") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("明日草案")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("稍後再看") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("接受勾選項") {
                        planner.accept((draft.included + draft.excluded).filter { selected.contains($0.id) }, from: day)
                        Notifier.sync(context)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                selected = Set(draft.included.filter { $0.candidate.source != .lockedCommitment }.map(\.id))
            }
        }
        .frame(minWidth: 460, minHeight: 560)
    }

    @ViewBuilder
    private func entryRow(_ e: DraftEntry) -> some View {
        if e.candidate.source == .lockedCommitment {
            HStack {
                Image(systemName: "lock.fill").font(.caption)
                Text(e.candidate.title)
                Spacer()
                Text("已承諾 · \(formatDuration(e.candidate.minutes))").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Toggle(isOn: Binding(get: { selected.contains(e.id) },
                                 set: { if $0 { selected.insert(e.id) } else { selected.remove(e.id) } })) {
                VStack(alignment: .leading) {
                    Text(e.candidate.title)
                    Text("\(e.reason) · \(formatDuration(e.candidate.minutes))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 每週回顧

struct WeeklyReviewSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var decisions: [UUID: String] = [:]
    @State private var reasons: [UUID: String] = [:]
    @State private var capacityNote = ""
    @State private var note = ""

    private let options = ["continue", "tweak", "replace", "pause"]
    private func label(_ k: String) -> String {
        ["continue": "繼續", "tweak": "微調", "replace": "替換", "pause": "暫停"][k] ?? k
    }

    var body: some View {
        let planner = Planner(context)
        let goals = planner.focusGoals
        let nextWeek = (1...7).map { planner.today.adding(days: $0, calendar: planner.calendar) }
        let templateMinutes = planner.activeTemplate.map { t in
            nextWeek.filter { t.weekdays.contains($0.weekday(in: planner.calendar)) }.count
                * planner.templateItems(t).filter { $0.kind == .work }.reduce(0) { $0 + $1.durationMinutes }
        } ?? 0
        NavigationStack {
            Form {
                ForEach(goals) { g in
                    let o = planner.outcomeProgress(g)
                    let t = planner.actionTrend(g)
                    let s = planner.activeStrategy(for: g.id)
                    Section(g.title) {
                        LabeledContent("成果", value: o.text)
                        LabeledContent("行動（7 天）", value: "完成 \(t.done7) 項 · 投入 \(formatDuration(t.minutes7))")
                        LabeledContent("延後次數（7 天）", value: "\(planner.deferralCount(g, days: 7))")
                        if let s {
                            Picker("策略「\(s.title)」", selection: Binding(get: { decisions[g.id] ?? "continue" }, set: { decisions[g.id] = $0 })) {
                                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
                            }
                            TextField("簡短原因（選填）", text: Binding(get: { reasons[g.id] ?? "" }, set: { reasons[g.id] = $0 }))
                            if decisions[g.id] == "replace" || decisions[g.id] == "tweak" {
                                Text("完成後到目標頁調整策略；舊策略的紀錄會保留。").font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("還沒有策略，可以到目標頁補上。").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if goals.isEmpty { Text("目前沒有焦點目標。").foregroundStyle(.secondary) }
                Section("下週容量") {
                    LabeledContent("工作模板固定工作", value: formatDuration(templateMinutes))
                    TextField("下週有什麼已知的忙碌或休假？", text: $capacityNote, axis: .vertical)
                }
                Section("筆記") { TextField("這週學到什麼？", text: $note, axis: .vertical) }
            }
            .formStyle(.grouped)
            .navigationTitle("每週回顧")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("稍後") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        let list = goals.compactMap { g -> (goal: Goal, strategy: Strategy, decision: String, reason: String)? in
                            guard let s = planner.activeStrategy(for: g.id) else { return nil }
                            return (g, s, decisions[g.id] ?? "continue", reasons[g.id] ?? "")
                        }
                        planner.completeWeekly(planner.weeklyReview(for: planner.weekStart), decisions: list,
                                               capacityNote: capacityNote, note: note)
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 600)
    }
}

// MARK: - 原則（保留 v1 日落三問）

struct PrincipleSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var pain = ""
    @State private var causeType = "系統流程"
    @State private var cause = ""
    @State private var text = ""
    @State private var goalID: UUID?

    var body: some View {
        let planner = Planner(context)
        NavigationStack {
            Form {
                TextField("① 遇到的痛點或卡關", text: $pain, axis: .vertical)
                Picker("② 根本原因出在", selection: $causeType) {
                    Text("人").tag("人")
                    Text("系統流程").tag("系統流程")
                }
                .pickerStyle(.segmented)
                TextField("② 根因診斷", text: $cause, axis: .vertical)
                TextField("③ 下次遇到時，我要怎麼做？", text: $text, axis: .vertical)
                Picker("相關目標（選填）", selection: $goalID) {
                    Text("不連結").tag(UUID?.none)
                    ForEach(planner.goals.filter(\.isOpen)) { Text($0.title).tag(UUID?.some($0.id)) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("寫下一條原則")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        let p = Principle(text: text.trimmed, painPoint: pain.trimmed, causeType: causeType, rootCause: cause.trimmed)
                        p.goalID = goalID
                        context.insert(p)
                        planner.save()
                        dismiss()
                    }
                    .disabled(text.trimmed.isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 420)
    }
}
