import SwiftUI
import SwiftData
import UserNotifications

@main
struct BillionairePlannerApp: App {
    /// 資料庫固定放在 Application Support/BillionairePlanner/，版本工具會一併備份
    let container: ModelContainer = {
        let schema = Schema([RichGoal.self, BrainDumpItem.self, TimeBlock.self, PrincipleLog.self, ThinkSession.self])
        let dir = URL.applicationSupportDirectory.appending(path: "BillionairePlanner", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = ModelConfiguration(schema: schema, url: dir.appending(path: "Planner.store"))
        do { return try ModelContainer(for: schema, configurations: config) }
        catch { fatalError("無法開啟資料庫（若剛退回舊版，請見 README「資料還原」）：\(error)") }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(.assetGreen)
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1100, height: 780)
        #endif
    }
}

// MARK: - 導覽

enum Pane: String, CaseIterable, Identifiable {
    case buffett, musk, dalio, gates
    var id: Self { self }

    var title: String {
        switch self {
        case .buffett: "5/25 減法"
        case .musk: "時間顆粒"
        case .dalio: "原則復盤"
        case .gates: "思考週"
        }
    }

    var icon: String {
        switch self {
        case .buffett: "shield.lefthalf.filled"
        case .musk: "clock"
        case .dalio: "doc.text.magnifyingglass"
        case .gates: "brain.head.profile"
        }
    }

    @ViewBuilder var view: some View {
        switch self {
        case .buffett: BuffettView()
        case .musk: MuskView()
        case .dalio: DalioView()
        case .gates: GatesView()
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ThinkSession> { $0.endedAt == nil }) private var openSessions: [ThinkSession]
    @State private var pane: Pane? = .buffett

    var body: some View {
        Group {
            if let session = openSessions.first {
                ThinkModeView(session: session)   // 思考模式：隱藏一切日常
            } else {
                #if os(iOS)
                TabView {
                    ForEach(Pane.allCases) { p in
                        p.view.tabItem { Label(p.title, systemImage: p.icon) }
                    }
                }
                #else
                NavigationSplitView {
                    List(Pane.allCases, selection: $pane) { p in
                        Label(p.title, systemImage: p.icon).tag(p)
                    }
                    .navigationTitle("計畫控制台")
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200)
                    .safeAreaInset(edge: .bottom) {
                        Text("v\(AppInfo.version) (\(AppInfo.build))")
                            .font(.caption2).foregroundStyle(.secondary).padding(8)
                    }
                } detail: {
                    (pane ?? .buffett).view
                }
                #endif
            }
        }
        .background(Color.black)
        .onAppear { Notifier.sync(context) }
    }
}

// MARK: - 設計 Token

extension ShapeStyle where Self == Color {
    static var assetGreen: Color { Color(red: 0, green: 1, blue: 0.4) }                       // #00FF66
    static var alertRed: Color { Color(red: 1, green: 59 / 255, blue: 48 / 255) }             // #FF3B30
    static var guardGray: Color { Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255) }  // #8E8E93
    static var legalPad: Color { Color(red: 1, green: 0.96, blue: 0.62) }
}

extension View {
    func cyberList() -> some View {
        scrollContentBackground(.hidden).background(Color.black)
    }
}

enum AppInfo {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
}

// MARK: - 時間塊開始提醒（附上同標籤的原則）

@MainActor
enum Notifier {
    /// 清掉再重排：所有變更後呼叫即可。思考模式期間不排任何提醒。
    static func sync(_ context: ModelContext) {
        try? context.save()
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let open = FetchDescriptor<ThinkSession>(predicate: #Predicate { $0.endedAt == nil })
        guard ((try? context.fetchCount(open)) ?? 0) == 0 else { return }

        let now = Date()
        let blocks = ((try? context.fetch(FetchDescriptor<TimeBlock>())) ?? [])
            .filter { !$0.isDone && $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(60)   // ponytail: iOS 上限 64 個待發提醒
        guard !blocks.isEmpty else { return }
        let principles = (try? context.fetch(FetchDescriptor<PrincipleLog>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []

        let requests = blocks.map { b -> UNNotificationRequest in
            let content = UNMutableNotificationContent()
            content.title = "⏱ \(b.taskTitle)  \(b.tag)"
            content.body = principles.first { $0.tag == b.tag }.map { "📜 原則：\($0.concretePrinciple)" }
                ?? "開始專注 \(b.durationMinutes) 分鐘。"
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: b.startDate)
            return UNNotificationRequest(identifier: b.id.uuidString, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            requests.forEach { center.add($0) }
        }
    }
}
