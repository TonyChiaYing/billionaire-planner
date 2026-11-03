import SwiftUI
import SwiftData
import PlannerCore
import UniformTypeIdentifiers

// MARK: - 設計 token（延續 v1 深色控制台風格；不用紅色警報逼人）

extension ShapeStyle where Self == Color {
    static var assetGreen: Color { Color(red: 0, green: 1, blue: 0.4) }                       // #00FF66
    static var attention: Color { Color(red: 1, green: 0.72, blue: 0.2) }                     // 需要處置（琥珀）
    static var guardGray: Color { Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255) }  // #8E8E93
    static var legalPad: Color { Color(red: 1, green: 0.96, blue: 0.62) }
    static var cardBackground: Color { Color.white.opacity(0.06) }
}

extension LoadState {
    var color: Color {
        switch self {
        case .comfortable, .feasible: .assetGreen
        case .tight: .attention
        case .overloaded: .orange
        }
    }
}

extension ItemContext {
    var label: String {
        switch self {
        case .personal: "個人目標"
        case .work: "工作"
        case .maintenance: "生活維護"
        }
    }
    var symbol: String {
        switch self {
        case .personal: "target"
        case .work: "briefcase"
        case .maintenance: "house"
        }
    }
    var color: Color {
        switch self {
        case .personal: .assetGreen
        case .work: .cyan
        case .maintenance: .guardGray
        }
    }
}

struct Card<Content: View>: View {
    var title: String?
    var symbol: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label(title, systemImage: symbol ?? "circle")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

struct StatusBadge: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

struct CapacityBadge: View {
    let state: LoadState
    var body: some View { StatusBadge(text: state.label, symbol: state.symbol, color: state.color) }
}

/// 以「當日分鐘」綁定的時間選擇器
struct MinutePicker: View {
    let title: String
    @Binding var minutes: Int

    private var date: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date(timeIntervalSince1970: 0)) ?? Date() },
            set: { minutes = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) }
        )
    }

    var body: some View {
        DatePicker(title, selection: date, displayedComponents: .hourAndMinute)
    }
}

/// 可選估時：不強迫輸入
struct OptionalMinutesField: View {
    let title: String
    @Binding var minutes: Int?
    var range: ClosedRange<Int> = 5...240

    var body: some View {
        Toggle(isOn: Binding(get: { minutes != nil }, set: { minutes = $0 ? (minutes ?? 30) : nil })) {
            Text(title)
        }
        if let m = minutes {
            Stepper(value: Binding(get: { m }, set: { minutes = $0 }), in: range, step: 5) {
                Text("約 \(formatDuration(m))")
            }
        }
    }
}

struct EmptyHint: View {
    let text: String
    var symbol: String = "sparkles"
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 讓 View 在資料變動時刷新（Application 層用 context 查詢，這裡只負責觀察）
struct DataObserver: ViewModifier {
    @Query private var goals: [Goal]
    @Query private var actions: [ActionItem]
    @Query private var placements: [PlanPlacement]
    @Query private var blocks: [DayBlock]
    @Query private var evidence: [OutcomeEvidence]
    @Query private var strategies: [Strategy]
    @Query private var milestones: [Milestone]
    @Query private var reviews: [DailyReview]
    @Query private var episodes: [RecoveryEpisode]
    @Query private var revisions: [DeadlineRevision]
    @Query private var principles: [Principle]
    @Query private var weekly: [WeeklyReview]
    @Query private var events: [InterventionEvent]

    func body(content: Content) -> some View {
        let token = goals.count + actions.count + placements.count + blocks.count + evidence.count + strategies.count
            + milestones.count + reviews.count + episodes.count + revisions.count + principles.count + weekly.count + events.count
        // 新增／刪除由計數變化通知；屬性修改由 Observation 自動追蹤
        return content.environment(\.dataVersion, token)
    }
}

private struct DataVersionKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var dataVersion: Int {
        get { self[DataVersionKey.self] }
        set { self[DataVersionKey.self] = newValue }
    }
}

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

extension View {
    func darkCanvas() -> some View {
        scrollContentBackground(.hidden).background(Color.black)
    }
}

extension Date {
    var shortDay: String { formatted(.dateTime.month().day().weekday(.abbreviated)) }
}
