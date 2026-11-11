import SwiftUI

/// 版面縮放（V204-ZOOM）：80%–150%，每次 10%。
/// macOS 沒有 Dynamic Type，所以用「縮小版面再等比放大」讓整個視窗（含表單）一起縮放；
/// iOS 用 dynamicTypeSize，文字清晰且仍可捲動。100% 時完全不套用，維持原本外觀。
enum UIZoom {
    static let key = "uiZoom"
    static let levels: [Double] = [0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5]

    /// 吃掉任意值（包括手改設定檔）：落在最接近的檔位
    static func clamp(_ z: Double) -> Double {
        levels.min { abs($0 - z) < abs($1 - z) } ?? 1.0
    }
    static func zoomIn(_ z: Double) -> Double { levels.first { $0 > clamp(z) + 0.001 } ?? levels.last! }
    static func zoomOut(_ z: Double) -> Double { levels.last { $0 < clamp(z) - 0.001 } ?? levels.first! }
    static func label(_ z: Double) -> String { "\(Int((clamp(z) * 100).rounded()))%" }

    /// UI 測試寫到獨立的設定區，絕不改到使用者自己的縮放
    static let store: UserDefaults = {
        guard AppEnvironment.isUITesting, let d = UserDefaults(suiteName: "BillionairePlanner.uitest") else { return .standard }
        d.removePersistentDomain(forName: "BillionairePlanner.uitest")   // 每次 UI 測試都從 100% 開始
        return d
    }()

    static var current: Double {
        get { clamp(store.object(forKey: key) as? Double ?? 1.0) }
        set { store.set(clamp(newValue), forKey: key) }
    }

    #if os(iOS)
    static func typeSize(_ z: Double) -> DynamicTypeSize {
        switch clamp(z) {
        case ..<0.85: .small
        case ..<0.95: .medium
        case ..<1.05: .large
        case ..<1.15: .xLarge
        case ..<1.25: .xxLarge
        case ..<1.35: .xxxLarge
        case ..<1.45: .accessibility1
        default: .accessibility2
        }
    }
    #endif
}

struct PlannerZoom: ViewModifier {
    @AppStorage(UIZoom.key, store: UIZoom.store) private var zoom = 1.0
    var minWidth: CGFloat?
    var minHeight: CGFloat?

    func body(content: Content) -> some View {
        let z = UIZoom.clamp(zoom)
        #if os(macOS)
        // macOS 沒有 Dynamic Type：字級直接依縮放計算（Font.z），重新排版而不是放大圖像，
        // 所以 VoiceOver 與點擊位置都正確。縮放改變時以 id 重建畫面，讓所有字級套用新值。
        // ponytail: 重建會重置該畫面內的暫存狀態（例如捲動位置）；縮放很少調整，可接受
        if z == 1.0 {
            content.frame(minWidth: minWidth, minHeight: minHeight)
        } else {
            content
                .font(.z(.body))
                .id(z)
                .frame(minWidth: minWidth.map { $0 * z }, minHeight: minHeight.map { $0 * z })
        }
        #else
        // V205-IOS-01：最小尺寸是 Mac 視窗用的；iPhone 螢幕比它窄，套用會把表單切掉，所以 iOS 不設
        if z == 1.0 { content } else { content.dynamicTypeSize(UIZoom.typeSize(z)) }   // 100% 時尊重系統字級
        #endif
    }
}

extension Font {
    /// 依版面縮放的文字樣式。100% 或 iOS 時就是原本的系統樣式（iOS 由 dynamicTypeSize 處理）。
    static func z(_ style: Font.TextStyle) -> Font {
        #if os(macOS)
        let z = UIZoom.current
        guard z != 1.0 else { return .system(style) }
        // macOS 各文字樣式的預設點數
        let base: CGFloat = switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption, .caption2: 10
        @unknown default: 13
        }
        return .system(size: base * z, weight: style == .headline ? .bold : .regular)
        #else
        return .system(style)
        #endif
    }
}

extension View {
    /// 套用使用者的版面縮放；minWidth／minHeight 是 100% 時的最小尺寸，會跟著縮放
    func plannerZoom(minWidth: CGFloat? = nil, minHeight: CGFloat? = nil) -> some View {
        modifier(PlannerZoom(minWidth: minWidth, minHeight: minHeight))
    }
}

/// 「顯示方式」選單：放大 ⌘+／縮小 ⌘−／實際大小 ⌘0
struct ZoomCommands: Commands {
    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("放大") { UIZoom.current = UIZoom.zoomIn(UIZoom.current) }
                .keyboardShortcut("+", modifiers: .command)
            Button("縮小") { UIZoom.current = UIZoom.zoomOut(UIZoom.current) }
                .keyboardShortcut("-", modifiers: .command)
            Button("實際大小") { UIZoom.current = 1.0 }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
        }
    }
}

/// 設定頁與教學共用的縮放控制
struct ZoomControl: View {
    @AppStorage(UIZoom.key, store: UIZoom.store) private var zoom = 1.0

    var body: some View {
        HStack {
            Text("版面大小")
            Spacer()
            Button { zoom = UIZoom.zoomOut(zoom) } label: { Image(systemName: "minus.magnifyingglass") }
                .accessibilityLabel("縮小")
                .accessibilityIdentifier("zoom.out")
                .disabled(UIZoom.clamp(zoom) <= UIZoom.levels.first!)
            Text(UIZoom.label(zoom))
                .monospacedDigit()
                .frame(minWidth: 48)
                .accessibilityIdentifier("zoom.value")
            Button { zoom = UIZoom.zoomIn(zoom) } label: { Image(systemName: "plus.magnifyingglass") }
                .accessibilityLabel("放大")
                .accessibilityIdentifier("zoom.in")
                .disabled(UIZoom.clamp(zoom) >= UIZoom.levels.last!)
            Button("實際大小") { zoom = 1.0 }
                .accessibilityIdentifier("zoom.reset")
                .disabled(UIZoom.clamp(zoom) == 1.0)
        }
        .buttonStyle(.bordered)
    }
}
