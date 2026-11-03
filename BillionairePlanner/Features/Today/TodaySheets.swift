import SwiftUI
import SwiftData
import PlannerCore

// MARK: - 快速插入（只需要標題）＋局部重排預覽（AC-08）

struct QuickInsertSheet: View {
    let day: LocalDay
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingKey.fineTimeMode) private var fineTimeMode = false

    @State private var title = ""
    @State private var kind: ItemContext = .work
    @State private var urgency = 1
    @State private var estimate: Int? = nil
    @State private var timed = false
    @State private var start = 9 * 60
    @State private var preview: ReplanPreview?

    var body: some View {
        let planner = Planner(context)
        NavigationStack {
            Form {
                Section {
                    TextField("發生了什麼事？", text: $title)
                    Picker("類型", selection: $kind) {
                        ForEach(ItemContext.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("緊急程度", selection: $urgency) {
                        Text("一般").tag(0)
                        Text("急").tag(1)
                        Text("很急").tag(2)
                    }
                    .pickerStyle(.segmented)
                } footer: { Text("只有標題是必填；其他都可以略過。") }

                Section("時間（選填）") {
                    OptionalMinutesField(title: "預估時間", minutes: $estimate)
                    Toggle("放在指定時間", isOn: $timed)
                    if timed { MinutePicker(title: "開始", minutes: $start) }
                }

                if timed, let preview {
                    Section {
                        if !preview.hasConflicts {
                            Text("不會影響其他安排。").foregroundStyle(.secondary)
                        }
                        ForEach(preview.immovableConflicts, id: \.self) { _ in
                            Label("和已完成／進行中／鎖定的項目重疊，那些不會移動。", systemImage: "lock")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Array(preview.changes.enumerated()), id: \.element.id) { i, change in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(change.title).bold()
                                Text("原本 \(formatMinute(change.originalStart))–\(formatMinute(change.originalStart + change.originalDuration))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Picker("改成", selection: Binding(get: { self.preview?.changes[i].selected ?? change.selected },
                                                                set: { self.preview?.changes[i].selected = $0 })) {
                                    ForEach(change.options, id: \.choice) { o in
                                        Text("\(o.choice.label) \(o.summary)").tag(o.choice)
                                    }
                                }
                            }
                        }
                    } header: { Text("受影響的安排（只動這些）") } footer: { Text("確認後才會套用，之後可以一鍵復原。") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("快速插入")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("插入") {
                        planner.quickInsert(title: title, kind: kind, urgency: urgency, estimate: estimate,
                                            startMinute: timed ? start : nil, preview: timed ? preview : nil, on: day)
                        dismiss()
                    }
                    .disabled(title.trimmed.isEmpty)
                }
            }
            .onAppear {
                start = planner.nextQuarter()
                estimate = planner.estimateSuggestion(title: title, goalID: nil, kind: kind, userEstimate: nil)?.minutes
            }
            .onChange(of: [timed ? 1 : 0, start, estimate ?? 0]) { refresh(planner) }
        }
        .frame(minWidth: 420, minHeight: 480)
    }

    private func refresh(_ planner: Planner) {
        preview = timed ? planner.replanPreview(insertStart: start, duration: estimate ?? 30, on: day) : nil
    }
}

// MARK: - 加入今天（從目標下一步、未安排事項或新事項）

struct AddToTodaySheet: View {
    let day: LocalDay
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataVersion) private var dataVersion
    @AppStorage(SettingKey.fineTimeMode) private var fineTimeMode = false

    @State private var period: DayPeriod? = nil
    @State private var start = 9 * 60
    @State private var newTitle = ""
    @State private var newKind: ItemContext = .personal
    @State private var newGoalID: UUID? = nil
    @State private var newEstimate: Int? = nil
    @State private var added: Set<UUID> = []

    var body: some View {
        let _ = dataVersion
        let planner = Planner(context)
        let placedIDs = Set(planner.placements(on: day).filter(\.isActiveToday).map(\.actionID))
        NavigationStack {
            Form {
                Section("放在") {
                    if fineTimeMode {
                        MinutePicker(title: "開始時間", minutes: $start)
                    } else {
                        Picker("時段", selection: $period) {
                            Text("不指定").tag(DayPeriod?.none)
                            ForEach(DayPeriod.allCases) { Text($0.label).tag(DayPeriod?.some($0)) }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                ForEach(planner.focusGoals) { g in
                    let candidates = planner.openActions(for: g.id).filter { !placedIDs.contains($0.id) && !added.contains($0.id) }
                    Section("焦點：\(g.title)") {
                        if candidates.isEmpty {
                            Text(planner.activeStrategy(for: g.id) == nil ? "先到「目標」補上策略與下一步" : "下一步都安排好了")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(candidates) { a in addRow(a, planner: planner) }
                    }
                }

                let inbox = planner.context.all(ActionItem.self).filter {
                    $0.goalID == nil && ($0.status == .inbox || $0.status == .ready) && !placedIDs.contains($0.id) && !added.contains($0.id)
                }
                if !inbox.isEmpty {
                    Section("未安排的事項") { ForEach(inbox) { addRow($0, planner: planner) } }
                }

                Section("新增事項") {
                    TextField("標題", text: $newTitle)
                    Picker("類型", selection: $newKind) {
                        ForEach(ItemContext.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    if newKind == .personal {
                        Picker("目標", selection: $newGoalID) {
                            Text("不連結").tag(UUID?.none)
                            ForEach(planner.goals.filter(\.isOpen)) { Text($0.title).tag(UUID?.some($0.id)) }
                        }
                    }
                    OptionalMinutesField(title: "預估時間", minutes: $newEstimate)
                    if newEstimate == nil, let s = planner.estimateSuggestion(title: newTitle, goalID: newGoalID, kind: newKind, userEstimate: nil) {
                        HStack {
                            Text("建議 \(s.minutes) 分").bold()
                            Text(s.basis).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("採用") { newEstimate = s.minutes }
                        }
                    }
                    Button("新增並加入今天") {
                        let a = planner.addAction(title: newTitle, kind: newKind, goal: planner.goal(newGoalID), estimate: newEstimate)
                        place(a, planner: planner)
                        newTitle = ""
                        newEstimate = nil
                    }
                    .disabled(newTitle.trimmed.isEmpty)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("加入今天")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .frame(minWidth: 460, minHeight: 560)
    }

    private func addRow(_ a: ActionItem, planner: Planner) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(a.title)
                if let m = a.estimateMinutes {
                    Text("約 \(formatDuration(m))").font(.caption).foregroundStyle(.secondary)
                } else if let s = planner.estimateSuggestion(title: a.title, goalID: a.goalID, kind: a.kind, userEstimate: nil) {
                    Text("建議約 \(s.minutes) 分（\(s.sampleCount) 筆紀錄）").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("加入") { place(a, planner: planner) }.buttonStyle(.bordered)
        }
    }

    private func place(_ a: ActionItem, planner: Planner) {
        planner.plan(a, on: day, period: fineTimeMode ? nil : period, startMinute: fineTimeMode ? start : nil,
                     duration: fineTimeMode ? (a.estimateMinutes ?? 30) : nil)
        added.insert(a.id)
    }
}

// MARK: - 今日骨架（工作模板的當日實例；只改今天）

struct DaySkeletonSheet: View {
    let day: LocalDay
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataVersion) private var dataVersion
    @State private var editing: DayBlock?
    @State private var adding = false

    var body: some View {
        let _ = dataVersion
        let planner = Planner(context)
        let blocks = planner.dayBlocks(on: day)
        NavigationStack {
            List {
                Section {
                    if blocks.isEmpty { Text("今天沒有固定區段。").foregroundStyle(.secondary) }
                    ForEach(blocks) { b in
                        Button { editing = b } label: {
                            HStack {
                                Image(systemName: b.kind.symbol).frame(width: 22)
                                VStack(alignment: .leading) {
                                    Text(b.title)
                                    Text(b.kind.label + (b.isOverride ? " · 今天已修改" : "")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(formatMinute(b.startMinute))–\(formatMinute(b.endMinute))").font(.caption.monospacedDigit())
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions { Button("今天移除", role: .destructive) { planner.removeDayBlock(b) } }
                        .contextMenu { Button("今天移除", role: .destructive) { planner.removeDayBlock(b) } }
                    }
                } footer: {
                    Text("這裡的修改只影響今天。想讓以後也一樣，請在編輯時選「同時更新模板」。")
                }
                Section {
                    Button { adding = true } label: { Label("新增區段（休息、用餐、工作…）", systemImage: "plus") }
                    if let t = planner.activeTemplate {
                        Button { planner.applyTemplate(t, to: day) } label: { Label("套用「\(t.name)」模板", systemImage: "square.stack.3d.down.right") }
                    } else {
                        Button { planner.applyTemplate(planner.createDefaultTemplate(), to: day) } label: {
                            Label("建立平日工作模板並套用", systemImage: "wand.and.stars")
                        }
                    }
                }
            }
            .navigationTitle("今日骨架")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $editing) { DayBlockEditor(block: $0, day: day) }
            .sheet(isPresented: $adding) { DayBlockEditor(block: nil, day: day) }
        }
        .frame(minWidth: 440, minHeight: 480)
    }
}

struct DayBlockEditor: View {
    let block: DayBlock?
    let day: LocalDay
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind: BlockKind = .rest
    @State private var start = 12 * 60
    @State private var duration = 30
    @State private var alsoTemplate = false

    var body: some View {
        let planner = Planner(context)
        NavigationStack {
            Form {
                TextField("名稱", text: $title)
                Picker("類型", selection: $kind) { ForEach(BlockKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) } }
                MinutePicker(title: "開始", minutes: $start)
                Stepper("時長 \(formatDuration(duration))", value: $duration, in: 5...720, step: 5)
                if block?.sourceTemplateItemID != nil {
                    Toggle("同時更新模板（影響之後的日子）", isOn: $alsoTemplate)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(block == nil ? "新增區段" : "只改今天")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        if let block {
                            planner.editDayBlock(block, title: title, kind: kind, start: start, duration: duration)
                            if alsoTemplate { planner.pushBlockToTemplate(block) }
                        } else {
                            planner.addDayBlock(day, kind: kind, title: title, start: start, duration: duration)
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let b = block {
                    title = b.title; kind = b.kind; start = b.startMinute; duration = b.durationMinutes
                }
            }
        }
        .frame(minWidth: 380, minHeight: 360)
    }
}

// MARK: - 調整單一安排

struct PlacementEditSheet: View {
    let placement: PlanPlacement
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var timed = false
    @State private var start = 9 * 60
    @State private var period: DayPeriod? = nil
    @State private var duration: Int? = nil
    @State private var locked = false

    var body: some View {
        let planner = Planner(context)
        NavigationStack {
            Form {
                Toggle("指定時間（精細模式）", isOn: $timed)
                if timed {
                    MinutePicker(title: "開始", minutes: $start)
                } else {
                    Picker("時段", selection: $period) {
                        Text("不指定").tag(DayPeriod?.none)
                        ForEach(DayPeriod.allCases) { Text($0.label).tag(DayPeriod?.some($0)) }
                    }
                }
                OptionalMinutesField(title: "時長", minutes: $duration)
                Toggle("鎖定（重排時不動）", isOn: $locked)
            }
            .formStyle(.grouped)
            .navigationTitle(planner.actionMap()[placement.actionID]?.title ?? "安排")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        placement.type = timed ? .timed : (period == nil ? .ordered : .period)
                        placement.startMinute = timed ? start : nil
                        placement.period = timed ? DayPeriod.of(minute: start) : period
                        placement.durationMinutes = duration
                        planner.setLocked(placement, locked)
                        Notifier.sync(context)
                        dismiss()
                    }
                }
            }
            .onAppear {
                timed = placement.type == .timed
                start = placement.startMinute ?? planner.nextQuarter()
                period = placement.period
                duration = placement.durationMinutes
                locked = placement.isLocked
            }
        }
        .frame(minWidth: 380, minHeight: 340)
    }
}

// MARK: - 專注計時（不是完成的必要條件）＋休息建議

struct FocusTimerSheet: View {
    let placement: PlanPlacement
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingKey.breakAfter) private var breakAfter = 50
    @State private var startedAt = Date()
    @State private var restDismissedAt: Int = 0

    var body: some View {
        let planner = Planner(context)
        let action = planner.actionMap()[placement.actionID]
        let target = planner.plannedMinutes(placement, action: action)
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { tl in
                let elapsed = Int(tl.date.timeIntervalSince(startedAt))
                let minutes = elapsed / 60
                VStack(spacing: 18) {
                    Text(action?.title ?? "").font(.title2.bold()).multilineTextAlignment(.center)
                    Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit())
                        .accessibilityLabel("已專注 \(minutes) 分鐘")
                    ProgressView(value: min(1, Double(elapsed) / Double(max(1, target * 60))))
                        .tint(.assetGreen)
                    Text("預計 \(formatDuration(target))").foregroundStyle(.secondary)
                    if minutes >= breakAfter && minutes - restDismissedAt >= breakAfter {
                        VStack(spacing: 8) {
                            Label("已專注 \(minutes) 分，建議休息 10 分鐘。", systemImage: "cup.and.saucer")
                            HStack {
                                Button("再專注一下") { restDismissedAt = minutes }.buttonStyle(.bordered)
                            }
                        }
                        .padding()
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 10))
                    }
                    HStack {
                        Button {
                            planner.logFocus(placement, minutes: max(1, minutes), markDone: true)
                            dismiss()
                        } label: { Label("完成，記錄 \(max(1, minutes)) 分", systemImage: "checkmark") }
                            .buttonStyle(.borderedProminent).foregroundStyle(.black)
                        Button {
                            planner.logFocus(placement, minutes: minutes, markDone: false)
                            dismiss()
                        } label: { Label("先停，記錄投入", systemImage: "pause") }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(24)
            }
            .navigationTitle("專注")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("不記錄，關閉") { dismiss() } } }
            .onAppear {
                startedAt = Date()
                planner.start(placement)
            }
        }
        .frame(minWidth: 420, minHeight: 420)
    }
}
