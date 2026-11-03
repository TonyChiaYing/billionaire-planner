import SwiftUI
import SwiftData
import PlannerCore

/// 蓋茲思考週：主動的深度思考工具（不是日常主流程），可連結目標與策略
struct ThinkView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dataVersion) private var dataVersion
    @State private var topic = ""
    @State private var hours = 24
    @State private var goalID: UUID?

    private let durations = [1, 4, 24, 168]
    private func label(_ h: Int) -> String { [1: "1 小時", 4: "半天", 24: "思考日", 168: "思考週"][h] ?? "\(h) 小時" }

    var body: some View {
        let _ = dataVersion
        let planner = Planner(context)
        let finished = context.all(ThinkingSession.self).filter { $0.endedAt != nil }.sorted { $0.startedAt > $1.startedAt }
        NavigationStack {
            Form {
                Section {
                    TextField("當前閱讀／研究主題", text: $topic, axis: .vertical)
                    Picker("連結目標（選填）", selection: $goalID) {
                        Text("不連結").tag(UUID?.none)
                        ForEach(planner.goals.filter(\.isOpen)) { Text($0.title).tag(UUID?.some($0.id)) }
                    }
                    Picker("時長", selection: $hours) {
                        ForEach(durations, id: \.self) { Text(label($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button {
                        let s = ThinkingSession(topic: topic.trimmed, hours: hours)
                        s.goalID = goalID
                        s.strategyID = goalID.flatMap { planner.activeStrategy(for: $0)?.id }
                        context.insert(s)
                        planner.save()
                        topic = ""
                        Notifier.sync(context)
                    } label: {
                        Label("進入思考模式", systemImage: "moon.fill").bold().frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .disabled(topic.trimmed.isEmpty)
                } header: { Text("思考週") } footer: { Text("畫面會變成全黑，只留主題與黃色便箋；非必要提醒暫停，結束後恢復。") }

                Section("思考紀錄") {
                    if finished.isEmpty { Text("尚無紀錄").foregroundStyle(.secondary) }
                    ForEach(finished) { s in
                        NavigationLink {
                            ScrollView {
                                Text(s.notes.isEmpty ? "（空白）" : s.notes)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            }
                            .background(Color.black)
                            .navigationTitle(s.topic)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.topic).bold()
                                HStack {
                                    Text(s.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    if let g = planner.goal(s.goalID) { Text("· \(g.title)") }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .darkCanvas()
            .navigationTitle("思考")
            .toolbar { ToolbarItem { SettingsToolbarButton() } }
        }
    }
}

struct ThinkModeView: View {
    @Environment(\.modelContext) private var context
    @Bindable var session: ThinkingSession
    @State private var confirmEnd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("THINK WEEK", systemImage: "moon.fill").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = session.plannedEnd.timeIntervalSince(ctx.date)
                    Text(left > 0 ? Duration.seconds(left).formatted(.time(pattern: .hourMinuteSecond)) : "時間到")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(left > 0 ? Color.white : Color.assetGreen)
                }
                Button("結束") { confirmEnd = true }.buttonStyle(.bordered)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("當前閱讀／研究主題").font(.caption).foregroundStyle(.secondary)
                TextField("主題", text: $session.topic, axis: .vertical).font(.title2.bold()).textFieldStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("黃色法律便箋 · 跨領域合成思考").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $session.notes)
                    .font(.body)
                    .foregroundColor(.black)
                    .tint(.black)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color.legalPad, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("思考便箋")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .confirmationDialog("結束思考模式？", isPresented: $confirmEnd) {
            Button("結束並存檔") {
                session.endedAt = .now
                try? context.save()
                Notifier.sync(context)
            }
        }
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
    }
}
