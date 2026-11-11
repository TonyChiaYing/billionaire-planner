import SwiftUI

/// V204-TUTORIAL：功能範例教學。用同一個例子（晨間閱讀）從頭走到尾，每頁都可以「帶我去」實際畫面。
/// 只說明、不自動建立資料：範例目標要使用者在真正的建立流程裡自己按下一步才會存。
struct TutorialPage: Identifiable {
    let id: Int
    let symbol: String
    let title: String
    let why: String
    let example: String
    let steps: [String]
    var tab: AppTab? = nil
}

enum Tutorial {
    static let exampleGoal = "[範例] 完成 20 分鐘晨間閱讀"
    static let exampleOutcome = "能在上班前讀完一本書的 10 頁"
    static let exampleStrategy = "每天起床後先閱讀再看手機"
    static let exampleAction = "明早閱讀 10 頁"

    static let pages: [TutorialPage] = [
        TutorialPage(id: 0, symbol: "sparkles", title: "歡迎使用億萬計畫",
                     why: "這個 app 幫你把「想達成的事」拆成今天就能做的一小步，並在每天、每週回顧時看見真正的進展。",
                     example: "整份教學都用同一個例子：想養成「上班前讀 20 分鐘書」的習慣。",
                     steps: ["目標：想達成什麼、完成時看得到什麼",
                             "策略：打算怎麼做",
                             "下一步：5–90 分鐘能完成的一個行動",
                             "今天 → 晚間日結 → 明日草案 → 每週回顧，形成循環"]),
        TutorialPage(id: 1, symbol: "target", title: "1. 建立目標",
                     why: "先寫清楚「完成時會看到什麼」，之後才分得出做了事和有成果的差別。",
                     example: "目標「\(exampleGoal)」；完成時看到「\(exampleOutcome)」。",
                     steps: ["到「目標」按右上角「＋」",
                             "第 1 步：寫目標名稱與完成時看到什麼",
                             "第 2 步：期限、里程碑可以先略過",
                             "第 3 步：寫策略「\(exampleStrategy)」和下一步「\(exampleAction)」（約 25 分）",
                             "第 4 步：選「加入焦點並安排今天」；畫面會先顯示「安排前預估」的容量"],
                     tab: .goals),
        TutorialPage(id: 2, symbol: "sun.max", title: "2. 今天：最重要的下一步",
                     why: "打開 app 先看今天：最上面是最重要的一件事，下面是今天裝不裝得下。",
                     example: "「\(exampleAction)」出現在「最重要的下一步」，容量顯示「已安排 25 分／可承諾 …」。",
                     steps: ["「開始專注」計時；做完按「完成」",
                             "臨時插進來的事用工具列的「快速插入」（閃電圖示）",
                             "想從目標再挑一步，用「加入今天」（＋）",
                             "固定的上班、通勤、休息在「今日骨架」調整，只影響今天"],
                     tab: .today),
        TutorialPage(id: 3, symbol: "timer", title: "3. 專注與停止",
                     why: "專注計時的時間會用來改善之後的估時；被打斷也不用硬記。",
                     example: "讀了 10 分鐘被叫走：選「停止但不記錄」，今天頁回到「開始專注」。",
                     steps: ["完成：記錄這次專注的時間",
                             "停止但不記錄：放棄這次計時，不留下進行中狀態",
                             "在背景繼續：關掉視窗也繼續計時，今天頁會顯示專注中"],
                     tab: .today),
        TutorialPage(id: 4, symbol: "arrow.triangle.branch", title: "4. 需要處置",
                     why: "時間過了沒做很正常。app 不會偷偷幫你搬，而是請你選一個新去向。",
                     example: "昨天的「\(exampleAction)」沒做到，今天出現在「需要處置」並標示「昨天」。",
                     steps: ["現在開始、縮小、移到稍後：都放在今天",
                             "移到明日：排到明天",
                             "今天先不做／不需要了：留下紀錄但不再提醒"],
                     tab: .today),
        TutorialPage(id: 5, symbol: "moon.stars", title: "5. 下班整理與晚間日結",
                     why: "完成行動不等於有成果。日結時只把真正看得到的變化記成成果，沒有也完全沒關係。",
                     example: "完成「\(exampleAction)」後，日結勾選它並寫成果「上班前讀完 10 頁」。",
                     steps: ["回顧 →「下班整理」：替沒做完的工作選去向",
                             "回顧 →「晚間日結」：第 1 步先看今天完成了哪些",
                             "第 2 步：有成果才勾，並寫下成果內容",
                             "重開已完成的日結可以補充，不會重複記錄"],
                     tab: .review),
        TutorialPage(id: 6, symbol: "sunrise", title: "6. 明日草案",
                     why: "日結完成後會產生明天的草案，你逐項勾選接受，不會自動塞滿。",
                     example: "草案建議「\(exampleAction)」，並標出它屬於哪個目標、是延續還是新的下一步。",
                     steps: ["上方先看明天可承諾多少時間",
                             "取消不想要的項目，再按「接受勾選項」",
                             "還沒想好就按「稍後再看」，什麼都不會改"],
                     tab: .review),
        TutorialPage(id: 7, symbol: "calendar", title: "7. 每週回顧",
                     why: "一週看一次每個焦點目標：成果、行動、延後次數，決定策略要繼續、微調、替換還是暫停。",
                     example: "閱讀這週完成 5 次、延後 2 次 → 策略選「微調」，原因「週四太累，改成睡前讀」。",
                     steps: ["回顧 →「每週回顧」",
                             "每個焦點目標選一個策略決定，可寫簡短原因",
                             "缺策略或下一步的目標會被標出來",
                             "寫下下週已知的忙碌或休假"],
                     tab: .review),
        TutorialPage(id: 8, symbol: "brain.head.profile", title: "8. 思考",
                     why: "需要深度思考時（例如重新規劃閱讀清單），開一段專屬時間，可連結到目標。",
                     example: "主題「今年想讀哪 12 本書」，連結閱讀目標，時長「1 小時」。",
                     steps: ["到「思考」寫主題、選時長後開始",
                             "思考模式期間畫面只留下思考內容",
                             "結束後的紀錄會留在思考頁"],
                     tab: .think),
        TutorialPage(id: 9, symbol: "plus.magnifyingglass", title: "小技巧：版面大小",
                     why: "字太小或太大都可以調整，會記住你的選擇。",
                     example: "在這裡直接試試看，或用選單「顯示方式」。",
                     steps: ["放大 ⌘＋、縮小 ⌘－、實際大小 ⌘0（Mac）",
                             "也可以在「設定」調整（iPhone／iPad 在設定裡）",
                             "教學隨時可從側邊欄「使用教學」或「輔助說明」選單再打開"]),
    ]
}

struct TutorialView: View {
    /// 帶我去：切到某個分頁（nil 表示只關閉）
    var go: ((AppTab) -> Void)?
    /// 用範例開始建立目標（打開真正的建立流程，內容預先填好）
    var startExample: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    var body: some View {
        let page = Tutorial.pages[index]
        let last = Tutorial.pages.count - 1
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(page.title, systemImage: page.symbol)
                        .font(.z(.title2).bold())
                        .accessibilityIdentifier("tutorial.title")
                    Text(page.why)
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("範例", systemImage: "lightbulb").font(.z(.caption).bold()).foregroundStyle(Color.assetGreen)
                            Text(page.example)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(page.steps.enumerated()), id: \.offset) { i, s in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(i + 1)").font(.z(.caption).bold()).foregroundStyle(.black).frame(width: 20, height: 20)
                                    .background(Circle().fill(Color.assetGreen))   // 黑字＋實心綠：對比足夠
                                Text(s)
                            }
                        }
                    }
                    if page.id == 9 { ZoomControl() }
                    HStack {
                        if page.id == 1, let startExample {
                            Button {
                                dismiss()
                                startExample()
                            } label: { Label("用範例建立目標", systemImage: "wand.and.stars") }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("tutorial.example")
                        }
                        if let tab = page.tab, let go {
                            Button {
                                dismiss()
                                go(tab)
                            } label: { Label("帶我去「\(tab.title)」", systemImage: "arrow.right.circle") }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("tutorial.go")
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("使用教學 · \(index + 1)/\(Tutorial.pages.count)")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    #if os(macOS)
                    // Mac：關閉與上一步／下一步放在同一列（不再多一排工具列）
                    Button("關閉") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("tutorial.close")
                    #endif
                    Button("上一步") { index -= 1 }
                        .disabled(index == 0)
                        .accessibilityIdentifier("tutorial.prev")
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(Tutorial.pages) { p in
                            Circle().fill(p.id == index ? Color.assetGreen : Color.secondary.opacity(0.4))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .accessibilityHidden(true)
                    Spacer()
                    if index < last {
                        Button("下一步") { index += 1 }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("tutorial.next")
                    } else {
                        Button("開始使用") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("tutorial.finish")
                    }
                }
                .padding(16)
                .background(.bar)
            }
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }.accessibilityIdentifier("tutorial.close")
                }
            }
            #endif
        }
        .plannerZoom(minWidth: 560, minHeight: 520)
    }
}

/// 從「輔助說明」選單打開教學
extension Notification.Name {
    static let showTutorial = Notification.Name("BillionairePlanner.showTutorial")
}

struct HelpCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("億萬計畫使用教學") { NotificationCenter.default.post(name: .showTutorial, object: nil) }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}
