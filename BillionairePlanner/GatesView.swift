import SwiftUI
import SwiftData

/// 蓋茲思考週：啟動頁與紀錄。
struct GatesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ThinkSession.startedAt, order: .reverse) private var sessions: [ThinkSession]
    @State private var topic = ""
    @State private var hours = 24

    private let durations = [1, 4, 24, 168]
    private func label(_ h: Int) -> String { [1: "1 小時", 4: "半天", 24: "思考日", 168: "思考週"][h] ?? "\(h) 小時" }
    private var finished: [ThinkSession] { sessions.filter { $0.endedAt != nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("當前閱讀／研究主題", text: $topic, axis: .vertical)
                    Picker("時長", selection: $hours) {
                        ForEach(durations, id: \.self) { Text(label($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button(action: start) {
                        Label("一鍵進入思考模式", systemImage: "moon.fill").bold().frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("比爾蓋茲 Think Week")
                } footer: {
                    Text("啟動後畫面全黑，隱藏所有待辦與時間塊提醒，只留下主題與黃色法律便箋。")
                }

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
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.topic).bold()
                                Text(s.startedAt, format: .dateTime.year().month().day().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                                if !s.notes.isEmpty {
                                    Text(s.notes).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .contextMenu { Button("刪除", role: .destructive) { context.delete(s) } }
                    }
                    .onDelete { idx in idx.map { finished[$0] }.forEach { context.delete($0) } }
                }

                Section("關於") {
                    LabeledContent("版本", value: "v\(AppInfo.version) (build \(AppInfo.build))")
                }
            }
            .formStyle(.grouped)
            .cyberList()
            .navigationTitle("思考週")
        }
    }

    private func start() {
        context.insert(ThinkSession(topic: topic.trimmingCharacters(in: .whitespaces), hours: hours))
        topic = ""
        Notifier.sync(context)   // 思考期間清空所有提醒
    }
}

/// 全黑極簡的思考模式畫面（RootView 偵測到未結束的 session 時顯示）。
struct ThinkModeView: View {
    @Environment(\.modelContext) private var context
    @Bindable var session: ThinkSession
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
                        .foregroundStyle(left > 0 ? Color.white : .assetGreen)
                }
                Button("結束") { confirmEnd = true }.buttonStyle(.bordered).tint(.guardGray)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("當前閱讀／研究主題").font(.caption).foregroundStyle(.secondary)
                TextField("主題", text: $session.topic, axis: .vertical)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
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
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .confirmationDialog("結束思考模式？", isPresented: $confirmEnd) {
            Button("結束並存檔") {
                session.endedAt = .now
                Notifier.sync(context)   // 恢復時間塊提醒
            }
        }
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
    }
}
