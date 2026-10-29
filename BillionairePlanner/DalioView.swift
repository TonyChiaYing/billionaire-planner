import SwiftUI
import SwiftData

/// 達利奧：痛苦 + 反思 = 進步。日落三問 → 原則庫。
struct DalioView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PrincipleLog.createdAt, order: .reverse) private var logs: [PrincipleLog]

    @State private var pain = ""
    @State private var causeType = "系統流程"
    @State private var cause = ""
    @State private var principle = ""
    @State private var tag = ContextTag.strategy.rawValue
    @State private var search = ""

    private var canSave: Bool {
        ![pain, cause, principle].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var shown: [PrincipleLog] {
        search.isEmpty ? logs : logs.filter {
            [$0.painPoint, $0.rootCause, $0.concretePrinciple, $0.tag].joined(separator: " ")
                .localizedCaseInsensitiveContains(search)
        }
    }

    /// 連續復盤天數（今天還沒寫則從昨天算起）
    private var streak: Int {
        let cal = Calendar.current
        let days = Set(logs.map { cal.startOfDay(for: $0.createdAt) })
        var d = cal.startOfDay(for: .now)
        if !days.contains(d) { d = cal.date(byAdding: .day, value: -1, to: d) ?? d }
        var n = 0
        while days.contains(d) {
            n += 1
            d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return n
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label("復盤連續 \(streak) 天", systemImage: "flame.fill")
                            .foregroundStyle(streak > 0 ? Color.assetGreen : .guardGray)
                        Spacer()
                        Text("原則庫 \(logs.count) 條").foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("① 今天的痛點／失敗／虧損是什麼？", text: $pain, axis: .vertical)
                    Picker("② 根本原因出在", selection: $causeType) {
                        Text("人").tag("人")
                        Text("系統流程").tag("系統流程")
                    }
                    .pickerStyle(.segmented)
                    TextField("② 根因診斷：為什麼會發生？", text: $cause, axis: .vertical)
                    TextField("③ 提煉原則：下次遇到時我要怎麼做？", text: $principle, axis: .vertical)
                    Picker("適用情境", selection: $tag) {
                        ForEach(ContextTag.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Button(action: save) {
                        Text("寫入人生運作原則").bold().frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.assetGreen)
                    .foregroundStyle(.black)
                    .disabled(!canSave)
                } header: {
                    Text("日落三問 · 痛苦 + 反思 = 進步")
                } footer: {
                    Text("同標籤的時間塊開始時，最新的原則會隨提醒跳出來指導你。")
                }

                Section("原則進化鏈") {
                    if shown.isEmpty { Text("還沒有原則。今晚寫下第一條。").foregroundStyle(.secondary) }
                    ForEach(shown) { log in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(log.tag).font(.caption).foregroundStyle(ContextTag.color(log.tag))
                                Spacer()
                                Text(log.createdAt, format: .dateTime.year().month().day())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("💥 \(log.painPoint)").foregroundStyle(Color.alertRed)
                            Text("🔍 [\(log.causeType)] \(log.rootCause)").font(.callout).foregroundStyle(.secondary)
                            Text("📜 \(log.concretePrinciple)").bold().foregroundStyle(Color.assetGreen)
                        }
                        .padding(.vertical, 4)
                        .contextMenu { Button("刪除", role: .destructive) { context.delete(log) } }
                    }
                    .onDelete { idx in idx.map { shown[$0] }.forEach { context.delete($0) } }
                }
            }
            .formStyle(.grouped)
            .cyberList()
            .searchable(text: $search, prompt: "搜尋原則")
            .navigationTitle("達利奧原則日誌")
        }
    }

    private func save() {
        guard canSave else { return }
        context.insert(PrincipleLog(painPoint: pain, causeType: causeType, rootCause: cause,
                                    concretePrinciple: principle, tag: tag))
        pain = ""; cause = ""; principle = ""
    }
}
