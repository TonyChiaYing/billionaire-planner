import SwiftUI
import SwiftData

/// 巴菲特 5/25：列 25 個，只准啟用 5 個，其餘鎖定。
struct BuffettView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RichGoal.createdAt) private var goals: [RichGoal]
    @State private var newTitle = ""
    @State private var showKillerAlert = false
    @State private var buzz = 0

    private var active: [RichGoal] { goals.filter(\.isActive) }
    private var locked: [RichGoal] { goals.filter { !$0.isTopFive && !$0.isCompleted } }
    private var done: [RichGoal] {
        goals.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
    private var openCount: Int { active.count + locked.count }
    private var slotsLeft: Int { max(0, 5 - active.count) }
    private var canAdd: Bool { openCount < 25 && !newTitle.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("核心戰略防線").font(.headline)
                        Spacer()
                        Text("\(active.count) / 5")
                            .font(.title2.monospacedDigit().bold())
                            .foregroundStyle(active.count == 5 ? Color.assetGreen : .white)
                    }
                    HStack {
                        TextField(openCount < 25 ? "寫下一個長期目標（\(openCount)/25）" : "已達 25 個上限：先完成或刪除", text: $newTitle)
                            .onSubmit(add)
                            .disabled(openCount >= 25)
                        Button(action: add) { Image(systemName: "plus.circle.fill").font(.title2) }
                            .buttonStyle(.borderless)
                            .disabled(!canAdd)
                    }
                } footer: {
                    Text("列出 25 個目標，只啟用 5 個。Top 5 完成前，其餘目標一律鎖定，也不能排進時間塊。")
                }

                Section("核心衝刺 Top 5") {
                    if active.isEmpty {
                        Text("從下方候補清單選出最重要的 5 個").foregroundStyle(.secondary)
                    }
                    ForEach(active) { g in
                        HStack {
                            Image(systemName: "bolt.fill").foregroundStyle(Color.assetGreen)
                            Text(g.title).bold()
                            Spacer()
                            Button("完成") { g.isCompleted = true; g.completedAt = .now }
                                .buttonStyle(.borderedProminent)
                                .tint(.assetGreen)
                                .foregroundStyle(.black)
                        }
                        .listRowBackground(Color.assetGreen.opacity(0.12))
                        .swipeActions {
                            demoteButton(g)
                            deleteButton(g)
                        }
                        .contextMenu {
                            demoteButton(g)
                            deleteButton(g)
                        }
                    }
                }

                Section {
                    ForEach(locked) { g in
                        HStack {
                            Image(systemName: slotsLeft > 0 ? "circle.dashed" : "lock.fill")
                            Text(g.title)
                            Spacer()
                            if slotsLeft > 0 {
                                Button("啟用") { g.isTopFive = true }.buttonStyle(.bordered)
                            }
                        }
                        .foregroundStyle(Color.guardGray)
                        .contentShape(Rectangle())
                        .onTapGesture { if slotsLeft == 0 { buzz += 1; showKillerAlert = true } }
                        .swipeActions { deleteButton(g) }
                        .contextMenu { deleteButton(g) }
                    }
                } header: {
                    Text(slotsLeft > 0 ? "候補清單（還有 \(slotsLeft) 個名額）" : "精力殺手 · 已鎖定 \(locked.count)")
                }

                if !done.isEmpty {
                    Section("已達成 \(done.count)") {
                        ForEach(done) { g in
                            HStack {
                                Text(g.title).strikethrough().foregroundStyle(.secondary)
                                Spacer()
                                if let d = g.completedAt {
                                    Text(d, format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions { deleteButton(g) }
                            .contextMenu { deleteButton(g) }
                        }
                    }
                }
            }
            .cyberList()
            .navigationTitle("巴菲特 5/25")
            .sensoryFeedback(.error, trigger: buzz)
            .alert("這是你的精力殺手！", isPresented: $showKillerAlert) {
                Button("我知道了", role: .cancel) {}
            } message: {
                Text("在目前的 Top 5 完成之前，不准把任何時間或精力分配給其餘目標。")
            }
        }
    }

    private func demoteButton(_ g: RichGoal) -> some View {
        Button("降回候補") { g.isTopFive = false }.tint(.guardGray)
    }

    private func deleteButton(_ g: RichGoal) -> some View {
        Button("刪除", role: .destructive) { context.delete(g) }
    }

    private func add() {
        guard canAdd else { return }
        context.insert(RichGoal(title: newTitle.trimmingCharacters(in: .whitespaces)))
        newTitle = ""
    }
}
