# 🚀 Billionaire Planner App (v1 MVP) - Cross-Platform SwiftUI Spec
## 📌 System Architecture & Design Philosophy
This system is a hyper-focused, non-distractive personal operating system designed to replicate the time-defense, radical prioritization, and algorithmic continuous improvement strategies used by the world's most successful capital allocators.

### Tech Stack Constraints
- **Framework**: SwiftUI (Multiplatform: targeting iOS 17+ & macOS 14+)
- **Architecture**: MVVM (Model-View-ViewModel) + Command-Query Separation
- **Persistence**: SwiftData (Native, lightweight local relational syncing)
- **Design Tokens**: Pure Midnight Deep Cyber Black (`Color.black`), Emerald High-Leverage Accent (`Color.green`), Warn Red (`Color.red`), Guard Gray (`Color.gray`).

---

## 💻 1. Core Data Models (`Models.swift`)
```swift
import Foundation
import SwiftData

@Model
final class RichGoal {
    var id: UUID = UUID()
    var title: String = ""
    var isTopFive: Bool = false
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    
    init(title: String) {
        self.title = title
    }
}

@Model
final class TimeBlock {
    var id: UUID = UUID()
    var taskTitle: String = ""
    var startHour: Int = 9      // 0-23
    var startMinute: Int = 0    // 0, 15, 30, 45
    var durationMinutes: Int = 15
    var category: String = "Strategy" // Strategy, Focus, Buffer, Off
    var date: Date = Date()
    
    init(taskTitle: String, startHour: Int, startMinute: Int, category: String = "Strategy") {
        self.taskTitle = taskTitle
        self.startHour = startHour
        self.startMinute = startMinute
        self.category = category
    }
}

@Model
final class PrincipleLog {
    var id: UUID = UUID()
    var painPoint: String = ""
    var rootCause: String = ""
    var concretePrinciple: String = ""
    var createdAt: Date = Date()
    
    init(painPoint: String, rootCause: String, concretePrinciple: String) {
        self.painPoint = painPoint
        self.rootCause = rootCause
        self.concretePrinciple = concretePrinciple
    }
}
```

---

## 🛡️ 2. Core Modules Implementation

### 2.1 Buffett 5/25 View (`BuffettView.swift`)
```swift
import SwiftUI
import SwiftData

struct BuffettView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \.createdAt, order: .forward) private var goals: [RichGoal]
    @State private var newGoalTitle = ""
    @State private var showingAlert = false
    
    var topFiveCount: Int {
        goals.filter { $0.isTopFive }.count
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Text("核心戰略防線: \(topFiveCount) / 5")
                        .font(.headline)
                        .foregroundColor(topFiveCount == 5 ? .green : .white)
                    Spacer()
                }
                .padding()
                
                if goals.count < 25 {
                    HStack {
                        TextField("輸入長期目標 (上限 25 個)", text: $newGoalTitle)
                            .textFieldStyle(.roundedBorder)
                        Button(action: addGoal) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal)
                }
                
                List {
                    ForEach(goals) { goal in
                        HStack {
                            Text(goal.title)
                                .strikethrough(goal.isCompleted)
                                .foregroundColor(goal.isTopFive ? .white : .secondary)
                            Spacer()
                            
                            if goal.isTopFive {
                                Button(goal.isCompleted ? "已達成" : "標記完成") {
                                    goal.isCompleted.toggle()
                                }
                                .tint(.green)
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button("啟用為 Top 5") {
                                    if topFiveCount < 5 {
                                        goal.isTopFive = true
                                    } else {
                                        showingAlert = true
                                        #if os(iOS)
                                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                        #endif
                                    }
                                }
                                .disabled(topFiveCount >= 5)
                                .tint(.gray)
                            }
                        }
                        .listRowBackground(goal.isTopFive ? Color.green.opacity(0.1) : Color.clear)
                    }
                    .onDelete(perform: deleteGoals)
                }
            }
            .navigationTitle("巴菲特 5/25 減法系統")
            .alert("【專注力警告】", isPresented: $showingAlert) {
                Button("我知道了", role: .cancel) { }
            } message: {
                Text("剩下的 20 個目標是你的『精力殺手』！在目前的 Top 5 徹底解決前，嚴禁分配任何資源給它們。")
            }
        }
    }
    
    private func addGoal() {
        guard !newGoalTitle.isEmpty else { return }
        let goal = RichGoal(title: newGoalTitle)
        modelContext.insert(goal)
        newGoalTitle = ""
    }
    
    private func deleteGoals(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(goals[index])
        }
    }
}
```

### 2.2 Musk Chronos Grid View (`MuskView.swift`)
```swift
import SwiftUI
import SwiftData

struct MuskView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \.startHour, order: .forward) private var blocks: [TimeBlock]
    @State private var taskTitle = ""
    @State private var selectedHour = 9
    @State private var selectedMinute = 0
    @State private var selectedCategory = "Strategy"
    
    let categories = ["Strategy", "Focus", "Buffer", "Off"]
    let minutesArray = [0, 15, 30, 45]
    
    var body: some View {
        VStack {
            VStack(spacing: 10) {
                TextField("大腦傾倒：今日高槓桿任務", text: $taskTitle)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    Picker("時間", selection: $selectedHour) {
                        ForEach(6..<24) { hour in
                            Text("\(hour) 點").tag(hour)
                        }
                    }
                    Picker("分", selection: $selectedMinute) {
                        ForEach(minutesArray, id: \.self) { min in
                            Text(String(format: "%02d", min)).tag(min)
                        }
                    }
                    Picker("類型", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    Button("填入網格") {
                        addBlock()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
            .padding()
            
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(6..<24) { hour in
                        ForEach(minutesArray, id: \.self) { min in
                            let match = blocks.first(where: { $0.startHour == hour && $0.startMinute == min })
                            
                            HStack {
                                Text(String(format: "%02d:%02d", hour, min))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 50)
                                
                                if let block = match {
                                    HStack {
                                        Text(block.taskTitle)
                                            .font(.subheadline)
                                            .bold()
                                        Spacer()
                                        Text("# \(block.category)")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(colorForCategory(block.category).opacity(0.2))
                                            .foregroundColor(colorForCategory(block.category))
                                            .cornerRadius(4)
                                    }
                                    .padding(.horizontal)
                                    .frame(height: 35)
                                    .background(colorForCategory(block.category).opacity(0.1))
                                    .cornerRadius(6)
                                } else {
                                    Rectangle()
                                        .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2]))
                                        .frame(height: 35)
                                        .background(Color.black.opacity(0.02))
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .navigationTitle("馬斯克時間顆粒度")
    }
    
    private func addBlock() {
        guard !taskTitle.isEmpty else { return }
        let block = TimeBlock(taskTitle: taskTitle, startHour: selectedHour, startMinute: selectedMinute, category: selectedCategory)
        modelContext.insert(block)
        taskTitle = ""
    }
    
    private func colorForCategory(_ cat: String) -> Color {
        switch cat {
        case "Strategy": return .green
        case "Focus": return .blue
        case "Buffer": return .orange
        default: return .gray
        }
    }
}
```

### 2.3 Dalio Algorithmic Principles Log View (`DalioView.swift`)
```swift
import SwiftUI
import SwiftData

struct DalioView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \.createdAt, order: .descending) private var principles: [PrincipleLog]
    
    @State private var painPoint = ""
    @State private var rootCause = ""
    @State private var concretePrinciple = ""
    
    var body: some View {
        NavigationStack {
            VStack {
                Form {
                    Section(header: Text("痛楚反思演算法 (Pain + Reflection = Progress)")) {
                        TextField("遭遇痛點 / 失敗事件", text: $painPoint)
                        TextField("根本原因診斷 (系統缺陷 / 人的缺陷)", text: $rootCause)
                        TextField("提煉進化原則 (未來遇到如何行動)", text: $concretePrinciple)
                        
                        Button(action: savePrinciple) {
                            HStack {
                                Spacer()
                                Text("寫入機器運作規則")
                                    .bold()
                                Spacer()
                            }
                        }
                        .disabled(painPoint.isEmpty || rootCause.isEmpty || concretePrinciple.isEmpty)
                        .tint(.green)
                    }
                    
                    Section(header: Text("已有原則進化鏈")) {
                        ForEach(principles) { log in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("💥 痛點: \(log.painPoint)")
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                                Text("🔍 診斷: \(log.rootCause)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("📜 原則: \(log.concretePrinciple)")
                                    .font(.body)
                                    .bold()
                                    .foregroundColor(.green)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deletePrinciples)
                    }
                }
            }
            .navigationTitle("達利奧原則日誌")
        }
    }
    
    private func savePrinciple() {
        let newLog = PrincipleLog(painPoint: painPoint, rootCause: rootCause, concretePrinciple: concretePrinciple)
        modelContext.insert(newLog)
        painPoint = ""
        rootCause = ""
        concretePrinciple = ""
    }
    
    private func deletePrinciples(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(principles[index])
        }
    }
}
```

---

## 🎛️ 3. Cross-Platform Responsive Root UI (`MainAppView.swift`)
Responsive UI adaptive to device platform form factors.

```swift
import SwiftUI

struct MainAppView: View {
    var body: some View {
        #if os(iOS)
        // iOS Tab-Bar Navigation Style
        TabView {
            BuffettView()
                .tabItem {
                    Label("5/25 減法", systemName: "shield.grid.2x2.fill")
                }
            
            MuskView()
                .tabItem {
                    Label("時間顆粒", systemName: "clock.badge.checkmark")
                }
            
            DalioView()
                .tabItem {
                    Label("演算法原則", systemName: "doc.text.magnifyingglass")
                }
        }
        .accentColor(.green)
        
        #else
        // macOS Sidebar Navigation Style
        NavigationSplitView {
            List {
                NavigationLink(destination: BuffettView()) {
                    Label("5/25 減法", systemName: "shield.grid.2x2.fill")
                }
                NavigationLink(destination: MuskView()) {
                    Label("時間顆粒", systemName: "clock.badge.checkmark")
                }
                NavigationLink(destination: DalioView()) {
                    Label("演算法原則", systemName: "doc.text.magnifyingglass")
                }
            }
            .navigationTitle("富人計畫控制台")
            .frame(minWidth: 200)
        } detail: {
            BuffettView() // Default Land
        }
        #endif
    }
}
```

---

## 🏁 4. Application Entry Point (`AppEntryPoint.swift`)
```swift
import SwiftUI
import SwiftData

@main
struct BillionairePlannerApp: App {
    var body: some Scene {
        WindowGroup {
            MainAppView()
                .preferredColorScheme(.dark)
                .modelContainer(for: [RichGoal.self, TimeBlock.self, PrincipleLog.self])
        }
    }
}
```