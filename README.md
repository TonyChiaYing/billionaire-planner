# 億萬計畫 Billionaire Planner

給自己用的計畫／回顧 App：**少做（巴菲特）→ 排細（馬斯克）→ 復盤（達利奧）→ 深想（蓋茲）**。
SwiftUI 單一多平台 target，iOS 17+ / iPadOS / macOS 14+，資料以 SwiftData 存在本機。

## 取得 .app
- `Planner/BillionairePlanner_v<版本>.app` 就是可直接雙擊的 Mac App（Apple 晶片／Intel 通用）。
- 編譯由 GitHub 私人 repo `TonyChiaYing/billionaire-planner` 的雲端 Mac 完成：推送到 main 就會自動編譯 macOS 版並檢查 iOS 版，成品與紀錄在 `build` 分支。
- 也可以在本機自己編：`bash ~/Desktop/Planner/_Archive/build.sh`（需 Xcode），結果見 `_Archive/build.log`。

## 用 Xcode 開發
1. 用 **Xcode 16 以上** 開啟 `BillionairePlanner.xcodeproj`。
2. 上方執行目標選 **My Mac** → ⌘R，直接在 Mac 上跑。
3. 要裝到 iPhone：Target → Signing & Capabilities → Team 選你的 Apple ID，執行目標改成你的 iPhone。
   若提示 Bundle ID 被佔用，把 `com.chiaying.BillionairePlanner` 改成任何唯一字串即可。

## 四個模組
| 分頁 | 做什麼 |
|---|---|
| 5/25 減法 | 最多 25 個目標，只能啟用 5 個。名額滿時其餘目標灰色鎖定，點擊會震動並警告「這是你的精力殺手！」。完成一個 Top 5 才釋出名額。 |
| 時間顆粒 | 早上先「大腦傾倒」任務（可連結 Top 5 目標，鎖定目標不可選）→ 拖到 06:00–24:00 網格（或點空格選任務）。可切換 15 分／5 分極限模式；長按時間塊可延長、縮短、完成、退回。同標籤被切成多段時會提醒黏合。 |
| 原則復盤 | 日落三問：痛點 → 根因（人／系統流程）→ 原則。存入原則庫，顯示復盤連續天數；同標籤時間塊開始時，推播會附上最新原則。 |
| 思考週 | 一鍵進入全黑模式：只剩主題與黃色法律便箋，所有時間塊提醒暫停，結束後恢復並存入紀錄。 |

## 版本管理（升級／退回）
資料夾結構：
```
Planner/
├── BillionairePlanner_v1.0.0.app  ← 最新版 App（雙擊開啟）
├── BillionairePlanner_v1.0.0/   ← 最新版原始碼（永遠只有一個）
└── _Archive/
    ├── version.sh               ← 版本工具（升級／退回）
    ├── build.sh                 ← 本機編譯 .app
    └── BillionairePlanner_v<版本>_<日期-時間>.zip   ← 舊版封存
```
在「終端機」中：
```bash
cd ~/Desktop/Planner/_Archive
bash version.sh list                          # 看目前版本與所有封存
bash version.sh bump minor "新增每週回顧"      # 封存目前版 → 升到 v1.1.0 → 改新版
bash version.sh restore 1.0.0                 # 退回 v1.0.0（目前版本會先封存，可再 restore 回來）
```
- 版號規則 `主.次.修`：**major** 資料結構不相容的大改、**minor** 新功能、**patch** 修 bug。
- `bump` 會同步更新 Xcode 的版本號（MARKETING_VERSION）與 build 號，並在 `CHANGELOG.md` 最上面加一筆。
- App 內「思考週 → 關於」（Mac 側邊欄底部）會顯示目前版本，方便對照。
- 外層資料夾名稱即版本號，一眼就知道目前是哪一版。

## 資料還原
- macOS 版的資料庫在 `~/Library/Application Support/BillionairePlanner/`，每次封存都會把它一併放進 zip 的 `_data_backup/`。
- 只改畫面／邏輯的版本來回切換，資料不受影響。
- 若退回的舊版開不了資料庫（新版改過資料結構），先結束 App，把封存裡 `_data_backup/` 的檔案複製回上面那個資料夾即可。
- iPhone 上的資料存在 App 自己的沙盒，刪除 App 才會清除。

## 原始規格
`Docs/` 內為原始計劃書與 SwiftUI 規格。
