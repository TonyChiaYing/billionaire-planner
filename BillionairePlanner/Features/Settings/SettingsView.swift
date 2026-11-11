import SwiftUI
import SwiftData
import PlannerCore

/// 次級入口：工作模板、可用容量、通知、建議、資料管理（PRD 5.1）
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingKey.dayStart) private var dayStart = 7 * 60
    @AppStorage(SettingKey.dayEnd) private var dayEnd = 22 * 60
    @AppStorage(SettingKey.bufferPercent) private var buffer = 20
    @AppStorage(SettingKey.restFloor) private var restFloor = 30
    @AppStorage(SettingKey.defaultEstimate) private var defaultEstimate = 30
    @AppStorage(SettingKey.breakAfter) private var breakAfter = 50
    @AppStorage(SettingKey.fineTimeMode) private var fineTimeMode = false
    @AppStorage(SettingKey.notifications) private var notifications = true
    @AppStorage(SettingKey.notificationDetails) private var notificationDetails = false
    @AppStorage(SettingKey.estimateSuggestions) private var estimateSuggestions = true
    @AppStorage(SettingKey.recoveryPrompts) private var recoveryPrompts = true
    @AppStorage(SettingKey.weeklyPrompts) private var weeklyPrompts = true
    @AppStorage(SettingKey.deadlinePrompts) private var deadlinePrompts = true
    @State private var exportDoc: JSONDocument?
    @State private var showExport = false
    @State private var report: ReportBox?
    @State private var showTemplates = false
    @State private var showTutorial = false

    var body: some View {
        let migration = context.all(MigrationRun.self).first { $0.completedAt != nil }
        NavigationStack {
            Form {
                Section {
                    ZoomControl()
                    Button {
                        #if os(iOS)
                        showTutorial = true
                        #else
                        NotificationCenter.default.post(name: .showTutorial, object: nil)
                        #endif
                    } label: { Label("打開使用教學", systemImage: "questionmark.circle") }
                    .accessibilityIdentifier("settings.tutorial")
                } header: { Text("顯示與說明") } footer: { Text("Mac 也可以用 ⌘＋／⌘－／⌘0 調整版面大小。") }
                Section {
                    MinutePicker(title: "一天開始", minutes: $dayStart)
                    MinutePicker(title: "一天結束", minutes: $dayEnd)
                    Stepper("緩衝 \(buffer)%（預設 20%）", value: $buffer, in: 0...50, step: 5)
                    Stepper("休息底線 \(restFloor) 分", value: $restFloor, in: 0...180, step: 15)
                    Stepper("未估時以 \(defaultEstimate) 分計算", value: $defaultEstimate, in: 5...120, step: 5)
                } header: { Text("可用容量") } footer: {
                    Text("可承諾容量 = 可用時間 − 固定工作 − 休息／生活 − 緩衝。不會用 100% 時間排程。")
                }

                Section("工作模板") {
                    Button { showTemplates = true } label: { Label("編輯工作模板", systemImage: "square.stack.3d.down.right") }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("settings.templates")
                }

                Section {
                    Toggle("精細時段模式（指定幾點開始）", isOn: $fineTimeMode)
                    Stepper("專注 \(breakAfter) 分後建議休息", value: $breakAfter, in: 20...120, step: 5)
                } header: { Text("規劃方式") } footer: { Text("預設用上午／下午／晚上的輕量規劃；精細時段是選用的。") }

                Section {
                    Toggle("安排開始時提醒", isOn: $notifications)
                    Toggle("鎖定畫面顯示完整內容", isOn: $notificationDetails).disabled(!notifications)
                } header: { Text("通知") } footer: { Text("預設只顯示「有一個安排即將開始」，不洩漏目標或工作內容。") }

                Section("建議（都可以關掉）") {
                    Toggle("估時建議（依本機歷史）", isOn: $estimateSuggestions)
                    Toggle("目標恢復建議", isOn: $recoveryPrompts)
                    Toggle("每週回顧提醒", isOn: $weeklyPrompts)
                    Toggle("重要期限提醒", isOn: $deadlinePrompts)
                }

                Section {
                    Button { exportDoc = JSONDocument(data: DataExporter.json(context)); showExport = true } label: {
                        Label("匯出全部資料（JSON）", systemImage: "square.and.arrow.up")
                    }
                    if let r = migration?.report {
                        Button { report = ReportBox(report: r) } label: { Label("v1 遷移報告", systemImage: "doc.text") }
                    }
                    LabeledContent("資料位置") {
                        Text(StoreLocation.directory.path).font(.z(.caption)).textSelection(.enabled)
                    }
                } header: { Text("資料") } footer: { Text("所有資料只存在這台裝置，不需要網路或帳號。") }

                Section("關於") {
                    LabeledContent("版本", value: AppInfo.display)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("設定")
            .sheet(isPresented: $showTutorial) { TutorialView() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    #if os(iOS)
                    Button("完成") { dismiss() }
                    #endif
                }
            }
            .fileExporter(isPresented: $showExport, document: exportDoc, contentType: .json,
                          defaultFilename: "BillionairePlanner-\(LocalDay.today().description)") { _ in }
            .sheet(item: $report) { box in NavigationStack { MigrationReportView(report: box.report) } }
            .navigationDestination(isPresented: $showTemplates) { TemplateEditor() }
            .onChange(of: notifications) { Notifier.sync(context) }
            .onChange(of: notificationDetails) { Notifier.sync(context) }
        }
    }
}

struct TemplateEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dataVersion) private var dataVersion
    @Query private var items: [WorkTemplateItem]
    @Query private var templates: [WorkTemplate]
    @State private var editing: WorkTemplateItem?

    private let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        let planner = Planner(context)
        Form {
            if let t = planner.activeTemplate {
                Section("適用的日子") {
                    HStack {
                        ForEach(1...7, id: \.self) { d in
                            Toggle(weekdayNames[d - 1], isOn: Binding(get: { t.weekdays.contains(d) }, set: { on in
                                var w = t.weekdays
                                if on { w.insert(d) } else { w.remove(d) }
                                t.weekdays = w
                                planner.save()
                            }))
                            .toggleStyle(.button)
                        }
                    }
                }
                Section {
                    ForEach(planner.templateItems(t)) { item in
                        Button { editing = item } label: {
                            HStack {
                                Image(systemName: item.kind.symbol).frame(width: 22)
                                Text(item.title)
                                Spacer()
                                Text("\(formatMinute(item.startMinute))–\(formatMinute(item.startMinute + item.durationMinutes))")
                                    .font(.z(.caption).monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.borderless)
                        .contextMenu { Button("刪除", role: .destructive) { context.delete(item); planner.save() } }
                        .swipeActions { Button("刪除", role: .destructive) { context.delete(item); planner.save() } }
                    }
                    Button {
                        let i = WorkTemplateItem(templateID: t.id, kind: .work, title: "工作", startMinute: 9 * 60, durationMinutes: 60,
                                                 order: planner.templateItems(t).count)
                        context.insert(i)
                        planner.save()
                        editing = i
                    } label: { Label("新增區段", systemImage: "plus") }
                } header: { Text("「\(t.name)」的區段") } footer: {
                    Text("模板只影響之後套用的日子；已經安排好的日子不會被改動。")
                }
            } else {
                Section {
                    Button { planner.createDefaultTemplate() } label: { Label("建立平日模板（可再修改）", systemImage: "wand.and.stars") }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("工作模板")
        .sheet(item: $editing) { TemplateItemEditor(item: $0) }
    }
}

struct TemplateItemEditor: View {
    @Bindable var item: WorkTemplateItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("名稱", text: $item.title)
                Picker("類型", selection: $item.kindRaw) { ForEach(BlockKind.allCases) { Text($0.label).tag($0.rawValue) } }
                MinutePicker(title: "開始", minutes: $item.startMinute)
                Stepper("時長 \(formatDuration(item.durationMinutes))", value: $item.durationMinutes, in: 5...720, step: 5)
            }
            .formStyle(.grouped)
            .navigationTitle("模板區段")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { try? context.save(); dismiss() } } }
        }
        .plannerZoom(minWidth: 380, minHeight: 320)
    }
}
