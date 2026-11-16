import SwiftUI

/// V207-DELETE：封存／永久刪除的共用確認。永久刪除一定先列出會一起刪掉的內容，並要再按一次確認。
struct GoalDeleteConfirmation: ViewModifier {
    @Binding var goal: Goal?
    /// 刪除前要先做的事（例如詳細頁先返回列表）
    var beforeDelete: () -> Void = {}
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        let planner = Planner(context)
        content.confirmationDialog(
            "永久刪除「\(goal?.title ?? "")」？",
            isPresented: Binding(get: { goal != nil }, set: { if !$0 { goal = nil } }),
            titleVisibility: .visible,
            presenting: goal
        ) { g in
            Button("永久刪除", role: .destructive) {
                let id = g.id
                goal = nil
                beforeDelete()
                // 先讓畫面離開這個目標，再刪資料
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { Planner(context).deleteGoalPermanently(id: id) }
            }
            .accessibilityIdentifier("goal.delete.confirm")
            Button("改為封存") {
                planner.archive(g)
                goal = nil
            }
            .disabled(g.status == .archived)
            Button("取消", role: .cancel) { goal = nil }
        } message: { g in
            Text(planner.deletionSummary(g).description)
        }
    }
}

extension View {
    func confirmGoalDeletion(_ goal: Binding<Goal?>, beforeDelete: @escaping () -> Void = {}) -> some View {
        modifier(GoalDeleteConfirmation(goal: goal, beforeDelete: beforeDelete))
    }
}

/// 目標列的右鍵選單：打開、封存／重新開啟、永久刪除
struct GoalRowMenu: ViewModifier {
    let goal: Goal
    let planner: Planner
    @Binding var deleting: Goal?
    /// 焦點區的列另外有排序與取消焦點（同一個選單，避免兩個 contextMenu 互相蓋掉）
    var focusActions = false

    func body(content: Content) -> some View {
        content.contextMenu {
            if focusActions {
                Button("往上") { planner.moveFocus(goal, by: -1) }
                Button("往下") { planner.moveFocus(goal, by: 1) }
                Button("取消焦點") { planner.unfocus(goal) }
                Divider()
            }
            if goal.status == .archived || goal.status == .completed {
                Button { planner.reopen(goal) } label: { Label("重新開啟", systemImage: "arrow.uturn.backward") }
            }
            if goal.status != .archived {
                Button { planner.archive(goal) } label: { Label("封存", systemImage: "archivebox") }
            }
            Divider()
            Button(role: .destructive) { deleting = goal } label: { Label("永久刪除…", systemImage: "trash") }
                .accessibilityIdentifier("goal.delete")
        }
    }
}
