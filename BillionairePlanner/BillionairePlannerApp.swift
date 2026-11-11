import SwiftUI
#if os(macOS)
import AppKit
#endif
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
        .defaultSize(width: AppEnvironment.isUITesting ? 960 : 1180, height: AppEnvironment.isUITesting ? 680 : 820)
        .defaultPosition(.center)
        .commands {
            ZoomCommands()
            HelpCommands()
        }
        #endif

        #if os(macOS)
        Settings {
            if let container {
                SettingsView().modelContainer(container).preferredColorScheme(.dark).tint(.assetGreen)
                    .plannerZoom(minWidth: 520, minHeight: 600)
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
                .modifier(UITestWindowPlacement())
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
            Image(systemName: "externaldrive.badge.exclamationmark").font(.z(.largeTitle)).foregroundStyle(Color.attention)
            Text("v1 資料暫時無法匯入").font(.z(.title2).bold())
            Text("你的 v1 資料完全沒有被更動，也已另外備份。可以再試一次，或先使用 v2，下次開啟時會再自動嘗試。")
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.subtleText)
            Text(message).font(.z(.caption)).foregroundStyle(Color.subtleText).textSelection(.enabled)
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
            Text("無法開啟資料庫").font(.z(.title2).bold())
            Text("資料檔位置：\(StoreLocation.directory.path)").font(.z(.caption)).textSelection(.enabled)
            Text(message).font(.z(.caption)).foregroundStyle(Color.subtleText)
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
    @State private var showTutorial = false
    @State private var showExampleWizard = false
    /// V204-TUTORIAL：第一次開啟時自動顯示一次教學（UI 測試不顯示）
    @AppStorage("tutorialSeenV1", store: UIZoom.store) private var tutorialSeen = false

    var body: some View {
        content
            .plannerZoom()   // 在 RootView 裡套用：縮放時保留目前分頁
            .sheet(isPresented: $showTutorial, onDismiss: { tutorialSeen = true }) {
                TutorialView(go: { tab = $0 }, startExample: {
                    tab = .goals
                    // 等教學表單關閉後再打開建立流程
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showExampleWizard = true }
                })
            }
            .sheet(isPresented: $showExampleWizard) { GoalWizard(example: true) }
            .onReceive(NotificationCenter.default.publisher(for: .showTutorial)) { _ in showTutorial = true }
            .onAppear {
                if !tutorialSeen && (!AppEnvironment.isUITesting || ProcessInfo.processInfo.arguments.contains("-showTutorialOnLaunch")) {
                    showTutorial = true
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let session = openSessions.first {
            ThinkModeView(session: session)
        } else {
            #if os(iOS)
            TabView(selection: Binding(get: { tab ?? .today }, set: { tab = $0 })) {
                ForEach(AppTab.allCases) { t in
                    t.view
                        .tabItem { Label(t.title, systemImage: t.symbol).accessibilityIdentifier("tab.\(t.rawValue)") }
                        .tag(t)
                }
            }
            #else
            NavigationSplitView {
                List(AppTab.allCases, selection: $tab) { t in
                    Label(t.title, systemImage: t.symbol).tag(t)
                        .accessibilityIdentifier("tab.\(t.rawValue)")
                }
                .modifier(SidebarZoom())
                .accessibilityLabel("主要分頁")
                .navigationSplitViewColumnWidth(min: 170, ideal: 190)
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Button { showTutorial = true } label: { Label("使用教學", systemImage: "questionmark.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("sidebar.tutorial")
                        SettingsLink { Label("設定", systemImage: "gearshape") }
                            .buttonStyle(.borderless)
                        Text(AppInfo.display).font(.z(.caption2)).foregroundStyle(Color(white: 0.85))
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

/// V201-UAT-02：UI 測試模式下把主視窗放在主螢幕可見範圍內（忽略先前保存的位置）。一般使用不受影響。
struct UITestWindowPlacement: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content.onAppear {
            guard AppEnvironment.isUITesting else { return }
            DispatchQueue.main.async { Self.fitWindows() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Self.fitWindows() }
        }
        #else
        content
        #endif
    }

    #if os(macOS)
    static func fitWindows() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        for w in NSApplication.shared.windows where w.isVisible && w.styleMask.contains(.titled) {
            let size = NSSize(width: min(960, screen.width - 40), height: min(680, screen.height - 40))
            let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
            w.setFrame(NSRect(origin: origin, size: size), display: true)
            w.makeKeyAndOrderFront(nil)
        }
    }
    #endif
}

#if os(macOS)
/// 側邊欄字級跟隨系統「側邊欄大小」，不吃 font；縮放時改用對應的列大小（100% 沿用系統設定）
struct SidebarZoom: ViewModifier {
    @AppStorage(UIZoom.key, store: UIZoom.store) private var zoom = 1.0
    func body(content: Content) -> some View {
        let z = UIZoom.clamp(zoom)
        if z == 1.0 {
            content
        } else {
            content.environment(\.sidebarRowSize, z < 1.0 ? .small : (z >= 1.2 ? .large : .medium))
        }
    }
}
#endif
