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
            // UAT-03：不用 List 承載入口（macOS 的 List 會把按鈕變成不可按的列），改用真正的按鈕
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Card(title: "今天", symbol: "sun.max.fill") {   // 細線太陽圖示對比不足（稽核），改實心
                        stepButton("下班整理", detail: "工作收尾，約 1–2 分鐘", done: r?.workClosedAt, symbol: "briefcase",
                                   id: "review.workClose") { sheet = .workClose }
                        stepButton("晚間日結", detail: "確認今天、看看有沒有值得保存的成果，約 2–4 分鐘", done: r?.eveningClosedAt,
                                   symbol: "moon.stars", id: "review.evening") { sheet = .evening }
                        stepButton("明日草案", detail: r?.draftAcceptedAt == nil ? "根據今天的紀錄產生，可逐項接受" : "已接受部分草案",
                                   done: r?.draftAcceptedAt, symbol: "sunrise", id: "review.draft") { sheet = .draft }
                        Text("沒有進度或休息日也可以完成日結，不會中斷任何紀錄。").font(.z(.caption)).foregroundStyle(Color.subtleText)
                    }

                    let w = planner.context.all(WeeklyReview.self).first { $0.weekStartKey == planner.weekStart.description }
                    Card(title: "每週", symbol: "calendar") {
                        stepButton("每週回顧", detail: "成果與行動趨勢、策略決定、下週容量", done: w?.completedAt, symbol: "calendar",
                                   id: "review.weekly") { sheet = .weekly }
                    }

                    let principles = planner.context.all(Principle.self).sorted { $0.createdAt > $1.createdAt }
                    Card(title: "原則（痛苦＋反思＝進步）", symbol: "book.closed") {
                        if principles.isEmpty { EmptyHint(text: "從回顧中提煉的做事原則會累積在這裡。") }
                        ForEach(principles.prefix(20)) { p in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.text).bold()
                                if !p.painPoint.isEmpty { Text("起因：\(p.painPoint)").font(.z(.caption)).foregroundStyle(Color.subtleText) }
                                HStack(spacing: 6) {
                                    if !p.rootCause.isEmpty { Text("[\(p.causeType)] \(p.rootCause)") }
                                    if let g = planner.goal(p.goalID) { Text("· \(g.title)") }
                                    if !p.contextTag.isEmpty { Text("· \(p.contextTag)") }
                                }
                                .font(.z(.caption)).foregroundStyle(Color.subtleText)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Button { sheet = .principle } label: { Label("寫下一條原則", systemImage: "plus") }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("review.principle")
                    }

                    let ev = planner.context.all(OutcomeEvidence.self).filter { !$0.isReversed }.sorted { $0.recordedAt > $1.recordedAt }
                    Card(title: "最近的成果", symbol: "checkmark.seal") {
                        if ev.isEmpty { EmptyHint(text: "還沒有成果紀錄。") }
                        ForEach(ev.prefix(15)) { e in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(e.note.isEmpty ? e.kind.label : e.note)
                                    Text(planner.goal(e.goalID)?.title ?? "").font(.z(.caption)).foregroundStyle(Color.subtleText)
                                }
                                Spacer()
                                if let v = e.value { Text("\(v.formatted()) \(e.unit)").font(.z(.callout).monospacedDigit()) }
                                Text(e.recordedAt.shortDay).font(.z(.caption)).foregroundStyle(Color.subtleText)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .accessibilityIdentifier("review.outcomes")

                    if let migration {
                        Button { report = ReportBox(report: migration) } label: { Label("v1 遷移報告", systemImage: "doc.text") }
                            .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .background(Color.black)
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

    /// 可用鍵盤（Tab／空白鍵）與 VoiceOver 啟動的入口按鈕
    private func stepButton(_ title: String, detail: String, done: Date?, symbol: String, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: done == nil ? symbol : "checkmark.circle.fill")
                    .foregroundStyle(done == nil ? Color.secondary : Color.assetGreen)
                    .frame(width: 24)
                VStack(alignment: .leading) {
                    Text(title).bold()
                    Text(done.map { "完成於 \($0.formatted(date: .omitted, time: .shortened))" } ?? detail)
                        .font(.z(.caption)).foregroundStyle(Color.subtleText)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.z(.caption)).foregroundStyle(Color.subtleText)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
        .accessibilityHint(done == nil ? detail : "已完成，可以再次開啟")
        .accessibilityIdentifier(id)
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
                    if items.isEmpty { Text("今天的工作都有去向了。").foregroundStyle(Color.subtleText) }
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
                } header: { Text("未完成的工作") } footer: { if !items.isEmpty { Text("每一項都選一個去向；預設是延續到明天。") } }
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
        .plannerZoom(minWidth: 440, minHeight: 440)
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
        let done = planner.placements(on: day).filter(\.isDone)
        let candidates = planner.outcomeCandidates(on: day)
        NavigationStack {
            Form {
                if let closed = planner.existingReview(for: day)?.eveningClosedAt {
                    Label("已於 \(closed.formatted(date: .omitted, time: .shortened)) 完成日結；可以補充或修改，不會重複記錄。",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(Color.subtleText)
                        .accessibilityIdentifier("evening.alreadyClosed")
                }
                Section {
                    // V202-DAILY-03：先列出已完成的，讓使用者看得到今天做了什麼
                    ForEach(done) { p in
                        Label("\(actions[p.actionID]?.title ?? "") · \(formatDuration(planner.plannedMinutes(p, action: actions[p.actionID])))",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.assetGreen)
                            .accessibilityIdentifier("evening.done.item")
                    }
                    if unfinished.isEmpty && done.isEmpty { Text("今天沒有安排；休息日也可以完成日結。").foregroundStyle(Color.subtleText) }
                    ForEach(unfinished) { p in
                        Toggle(isOn: Binding(get: { confirmedDone.contains(p.id) },
                                             set: { if $0 { confirmedDone.insert(p.id) } else { confirmedDone.remove(p.id) } })) {
                            Text(actions[p.actionID]?.title ?? "")
                        }
                    }
                } header: { Text("1. 今天實際做完了哪些？") } footer: { if !unfinished.isEmpty { Text("還沒做完的：做完了就勾起來；沒勾的會成為明日草案的延續候選。") } }

                Section {
                    if candidates.isEmpty {
                        Text("今天沒有連結目標的完成行動。").font(.z(.caption)).foregroundStyle(Color.subtleText)
                    }
                    ForEach(candidates) { c in
                      if let rec = planner.recordedOutcome(for: c.action.id) {
                        // V203-REVIEW-01：已記錄的成果直接顯示，不再問一次
                        VStack(alignment: .leading) {
                            Label("已記錄成果：\(rec.note)", systemImage: "checkmark.seal")
                                .foregroundStyle(Color.assetGreen)
                            Text("\(c.action.title) · \(c.goal.title)").font(.z(.caption)).foregroundStyle(Color.subtleText)
                        }
                        .accessibilityIdentifier("evening.recorded")
                      } else {
                        Toggle(isOn: Binding(get: { outcomeSelected.contains(c.id) },
                                             set: { if $0 { outcomeSelected.insert(c.id) } else { outcomeSelected.remove(c.id) } })) {
                            VStack(alignment: .leading) {
                                Text("「\(c.action.title)」有帶來成果嗎？")
                                Text(c.goal.title).font(.z(.caption)).foregroundStyle(Color.subtleText)
                            }
                        }
                        .accessibilityIdentifier("evening.candidate")
                        if outcomeSelected.contains(c.id) {
                            TextField("成果是什麼？（例：第一次連續慢跑 10 分鐘）", text: Binding(get: { outcomeNotes[c.id] ?? "" },
                                                                                  set: { outcomeNotes[c.id] = $0 }))
                                .accessibilityIdentifier("evening.outcomeNote")
                            // 保留位置，輸入時版面不跳動（按鈕不會移位）
                            let empty = (outcomeNotes[c.id] ?? "").trimmed.isEmpty
                            Text("請寫下成果內容，或取消勾選。").font(.z(.caption)).foregroundStyle(Color.attention)
                                .opacity(empty ? 1 : 0)
                                .accessibilityHidden(!empty)
                        }
                      }
                    }
                    Picker("其他成果的目標", selection: $extraGoalID) {
                        Text("不記錄").tag(UUID?.none)
                        ForEach(planner.goals.filter(\.isOpen)) { Text($0.title).tag(UUID?.some($0.id)) }
                    }
                    if extraGoalID != nil { TextField("其他成果", text: $extraNote) }
                    Toggle("今天是休息日", isOn: $isRestDay)
                } header: { Text("2. 今天有沒有值得保存的成果？") } footer: {
                    Text("完成行動不等於成果；沒有可量化的成果也完全沒關係，不勾就好。")
                }

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
            .onAppear {
                // 重開已完成的日結：帶入上次的內容，避免空白覆蓋
                guard let r = planner.existingReview(for: day), r.eveningClosedAt != nil else { return }
                energy = r.energy ?? 0
                blockers = r.blockers
                blocked = Set(r.blockedGoalIDs)
                isRestDay = r.isRestDay
                note = r.note
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("稍後") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成日結") {
                        for p in unfinished where confirmedDone.contains(p.id) { planner.complete(p) }
                        let confirmed = outcomeNotes.filter { outcomeSelected.contains($0.key) }
                        let evidence = planner.eveningEvidence(candidates: candidates, confirmed: confirmed,
                                                               extraGoalID: extraGoalID, extraNote: extraNote)
                        planner.closeEvening(day: day, evidence: evidence, energy: energy == 0 ? nil : energy, blockers: blockers,
                                             blockedGoalIDs: Array(blocked), principle: principle, isRestDay: isRestDay, note: note)
                        dismiss()
                        openDraft()
                    }
                    .disabled(outcomeSelected.contains { (outcomeNotes[$0] ?? "").trimmed.isEmpty })
                    .accessibilityIdentifier("evening.done")
                }
            }
        }
        .plannerZoom(minWidth: 460, minHeight: 600)
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
                            .font(.z(.callout).monospacedDigit())
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
                            Text("\(e.candidate.source.label) · \(formatDuration(e.candidate.minutes))").font(.z(.caption)).foregroundStyle(Color.subtleText)
                        }
                    }
                    if draft.fixed.isEmpty { Text("明天沒有工作模板區段。").foregroundStyle(Color.subtleText) }
                }

                Section {
                    ForEach(draft.included) { e in entryRow(e) }
                    if draft.included.isEmpty { Text("沒有需要承諾的項目。").foregroundStyle(Color.subtleText) }
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
        .plannerZoom(minWidth: 460, minHeight: 560)
    }

    @ViewBuilder
    private func entryRow(_ e: DraftEntry) -> some View {
        if e.candidate.source == .lockedCommitment {
            HStack {
                Image(systemName: "lock.fill").font(.z(.caption))
                Text(e.candidate.title)
                Spacer()
                Text("已承諾 · \(formatDuration(e.candidate.minutes))").font(.z(.caption)).foregroundStyle(Color.subtleText)
            }
        } else {
            Toggle(isOn: Binding(get: { selected.contains(e.id) },
                                 set: { if $0 { selected.insert(e.id) } else { selected.remove(e.id) } })) {
                VStack(alignment: .leading) {
                    Text(e.candidate.title)
                    Text([e.reason, e.candidate.goalTitle, formatDuration(e.candidate.minutes)].compactMap { $0 }.joined(separator: " · ")).font(.z(.caption)).foregroundStyle(Color.subtleText)
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
                if let done = existingWeekly(planner)?.completedAt {
                    Label("本週已於 \(done.formatted(date: .abbreviated, time: .shortened)) 完成；可以修改，不會重複記錄。",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(Color.subtleText)
                        .accessibilityIdentifier("weekly.alreadyDone")
                }
                ForEach(goals) { g in
                    let o = planner.outcomeProgress(g)
                    let t = planner.actionTrend(g)
                    let s = planner.activeStrategy(for: g.id)
                    Section(g.title) {
                        LabeledContent("成果", value: o.text)
                        LabeledContent("行動（7 天）", value: "完成 \(t.done7) 項 · 投入 \(formatDuration(t.minutes7))")
                        LabeledContent("延後次數（7 天）", value: "\(planner.deferralCount(g, days: 7))")
                        if let missing = planner.missingSetup(g).label {
                            // V203-REVIEW-03：每週回顧是補上缺漏的時機
                            Label(missing, systemImage: "square.dashed").foregroundStyle(Color.attention)
                                .accessibilityIdentifier("weekly.missing")
                        }
                        if let s {
                            Picker("策略「\(s.title)」", selection: Binding(get: { decisions[g.id] ?? "continue" }, set: { decisions[g.id] = $0 })) {
                                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
                            }
                            TextField("簡短原因（選填）", text: Binding(get: { reasons[g.id] ?? "" }, set: { reasons[g.id] = $0 }))
                            if decisions[g.id] == "replace" || decisions[g.id] == "tweak" {
                                Text("完成後到目標頁調整策略；舊策略的紀錄會保留。").font(.z(.caption)).foregroundStyle(Color.subtleText)
                            }
                        } else {
                            Text("還沒有策略，可以到目標頁補上。").font(.z(.caption)).foregroundStyle(Color.subtleText)
                        }
                    }
                }
                if goals.isEmpty { Text("目前沒有焦點目標。").foregroundStyle(Color.subtleText) }
                Section("下週容量") {
                    LabeledContent("工作模板固定工作", value: formatDuration(templateMinutes))
                    TextField("下週有什麼已知的忙碌或休假？", text: $capacityNote, axis: .vertical)
                }
                Section("筆記") { TextField("這週學到什麼？", text: $note, axis: .vertical) }
            }
            .formStyle(.grouped)
            .navigationTitle("每週回顧")
            .onAppear {
                guard let w = existingWeekly(planner), w.completedAt != nil else { return }
                capacityNote = w.nextWeekCapacityNote
                note = w.note
                for g in goals {
                    if let d = planner.weeklyDecision(w, goalID: g.id) { decisions[g.id] = d.decision; reasons[g.id] = d.reason }
                }
            }
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
        .plannerZoom(minWidth: 480, minHeight: 600)
    }

    private func existingWeekly(_ planner: Planner) -> WeeklyReview? {
        let key = planner.weekStart.description
        return context.all(WeeklyReview.self).first { $0.weekStartKey == key }
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
        .plannerZoom(minWidth: 420, minHeight: 420)
    }
}
