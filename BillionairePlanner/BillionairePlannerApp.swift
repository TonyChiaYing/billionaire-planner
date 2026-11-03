import SwiftUI
import SwiftData
import PlannerCore

@main
struct BillionairePlannerApp: App {
    private let container: ModelContainer?
    private let storeError: String?

    init() {
        do {
            container = try (AppEnvironment.isUITesting ? PlannerContainer.inMemory() : PlannerContainer.make())
            storeError = nil
        } catch {
            container = nil
            storeError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    LaunchGate().modelContainer(container)
                } else {
                    StoreErrorView(message: storeError ?? "")
                }
            }
            .preferredColorScheme(.dark)
            .tint(.assetGreen)
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 820)
        #endif

        #if os(macOS)
        Settings {
            if let container {
                SettingsView().modelContainer(container).preferredColorScheme(.dark).tint(.assetGreen)
                    .frame(minWidth: 520, minHeight: 600)
            }
        }
        #endif
    }
}

/// 啟動時先完成 v1 遷移（UI 可編輯前），再進入主畫面
struct LaunchGate: View {
    enum Phase: Equatable { case checking, ready, failed(String) }

    @Environment(\.modelContext) private var context
    @State private var phase: Phase = .checking
    @State private var report: ReportBox?

    var body: some View {
        switch phase {
        case .checking:
            ProgressView("正在準備資料…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .task { migrate() }
        case .failed(let message):
            MigrationFailedView(message: message, retry: { phase = .checking }, skip: { phase = .ready })
        case .ready:
            RootView()
                .modifier(DataObserver())
                .sheet(item: $report) { box in
                    NavigationStack { MigrationReportView(report: box.report, isFirstRun: true) }
                }
        }
    }

    private func migrate() {
        if AppEnvironment.isUITesting {
            phase = .ready
            return
        }
        let migrator = V1Migrator(v1Store: StoreLocation.v1Store, backupRoot: StoreLocation.backups, container: context.container)
        switch migrator.runIfNeeded() {
        case .noLegacyStore, .alreadyCompleted:
            phase = .ready
        case .migrated(let r):
            report = ReportBox(report: r)
            phase = .ready
        case .failed(let message):
            phase = .failed(message)
        }
        Notifier.sync(context)
    }
}

struct ReportBox: Identifiable {
    let id = UUID()
    let report: MigrationReport
}

struct MigrationFailedView: View {
    let message: String
    let retry: () -> Void
    let skip: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle).foregroundStyle(Color.attention)
            Text("v1 資料暫時無法匯入").font(.title2.bold())
            Text("你的 v1 資料完全沒有被更動，也已另外備份。可以再試一次，或先使用 v2，下次開啟時會再自動嘗試。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button("再試一次", action: retry).buttonStyle(.borderedProminent)
                Button("先使用 v2", action: skip).buttonStyle(.bordered)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

struct StoreErrorView: View {
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Text("無法開啟資料庫").font(.title2.bold())
            Text("資料檔位置：\(StoreLocation.directory.path)").font(.caption).textSelection(.enabled)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// MARK: - 一級導覽：今天／目標／回顧／思考（PRD 5.1）

enum AppTab: String, CaseIterable, Identifiable {
    case today, goals, review, think
    var id: Self { self }
    var title: String {
        switch self {
        case .today: "今天"
        case .goals: "目標"
        case .review: "回顧"
        case .think: "思考"
        }
    }
    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .goals: "target"
        case .review: "checkmark.circle"
        case .think: "brain.head.profile"
        }
    }
    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .today: TodayView()
        case .goals: GoalsView()
        case .review: ReviewView()
        case .think: ThinkView()
        }
    }
}

struct RootView: View {
    @Query(filter: #Predicate<ThinkingSession> { $0.endedAt == nil }) private var openSessions: [ThinkingSession]
    @State private var tab: AppTab? = .today

    var body: some View {
        if let session = openSessions.first {
            ThinkModeView(session: session)
        } else {
            #if os(iOS)
            TabView(selection: Binding(get: { tab ?? .today }, set: { tab = $0 })) {
                ForEach(AppTab.allCases) { t in
                    t.view
                        .tabItem { Label(t.title, systemImage: t.symbol) }
                        .tag(t)
                }
            }
            #else
            NavigationSplitView {
                List(AppTab.allCases, selection: $tab) { t in
                    Label(t.title, systemImage: t.symbol).tag(t)
                }
                .navigationSplitViewColumnWidth(min: 170, ideal: 190)
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        SettingsLink { Label("設定", systemImage: "gearshape") }
                            .buttonStyle(.borderless)
                        Text(AppInfo.display).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
            } detail: {
                (tab ?? .today).view
            }
            #endif
        }
    }
}

/// iOS 的設定入口（macOS 用系統「設定」視窗 ⌘,）
struct SettingsToolbarButton: View {
    @State private var show = false
    var body: some View {
        #if os(iOS)
        Button { show = true } label: { Image(systemName: "gearshape") }
            .accessibilityLabel("設定")
            .sheet(isPresented: $show) { NavigationStack { SettingsView() } }
        #else
        EmptyView()
        #endif
    }
}
