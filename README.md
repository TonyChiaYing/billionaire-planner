# 億萬計畫 Billionaire Planner

給自己用的目標循環 App：**目標 → 策略 → 行動 → 今日安排 → 成果 → 回顧 → 恢復**。
目標是讓「調整」取代「放棄」：沒做到不是失敗，系統會幫你縮小、重排、調期或重新開始，而且不會抹掉過去的成果。

- 平台：iOS 17+、iPadOS 17+、macOS 14+（同一份 SwiftUI 程式碼）
- 資料：SwiftData，完全存在本機，不需要網路、帳號或 AI 服務
- 產品基準：`BillionairePlanner_v2.0.0.0_PRD.md`；開發規則：`.claude/skills/billionaire-planner-v2/`

## 四個分頁

| 分頁 | 做什麼 |
|---|---|
| **今天** | 最重要的下一步（可開始專注或直接完成）→ 今天裝得下嗎（寬鬆／可行／偏滿／過載＋原因）→ 需要處置的項目 → 今日安排（工作／個人／固定區段分組）→ 最近推進的成果。可快速插入臨時工作（只需標題），有時間衝突會先預覽局部重排，確認後套用、可一鍵復原。 |
| **目標** | 焦點目標（建議 3 個、上限 5 個）、草稿、其他、暫停中。目標詳情同時顯示「成果」與「行動證據」兩種進度；策略可替換並保留歷史；里程碑、成果紀錄、期限歷史、暫停／完成／開始新週期。 |
| **回顧** | 下班整理（工作去向，1–2 分鐘）→ 晚間日結（確認今天、記成果，2–4 分鐘）→ 明日草案（逐項接受）；每週回顧（趨勢、策略決定、下週容量）；原則庫。 |
| **思考** | v1 的思考週模式：全黑畫面＋黃色便箋，可連結目標，期間暫停非必要提醒。 |

設定（iOS 右上角齒輪；macOS 選單「設定…」或 ⌘,）：一天的範圍、緩衝 %（預設 20%）、休息底線、工作模板、精細時段模式、通知（預設不顯示內容）、各類建議開關、匯出 JSON、v1 遷移報告。

v1 的四套方法在 v2 的位置：5/25 → 焦點限制；時間顆粒 → 選用的精細時段模式；原則復盤 → 日結／週結與原則庫；思考週 → 思考分頁。

## 從 v1 升級

第一次開啟 v2 時會自動：

1. 把 v1 資料庫整組備份到 `~/Library/Application Support/BillionairePlanner/Backups/v1-<時間>/`（不會自動刪除）
2. 只讀取備份副本，**v1 原檔完全不被修改**
3. 匯入目標（沿用原 UUID）、腦傾倒項、時間塊、原則、思考紀錄；用目標名稱連結的項目只在「正好一個同名目標」時才連結，其餘列在「目標」頁最下方讓你手動連結
4. 顯示遷移報告（之後可在「回顧」或「設定」再看）

中途失敗或被中斷，下次開啟會安全重試、不會產生重複資料。v2 的資料存在新的 `PlannerV2.store`，所以退回 v1 時，v1 仍會看到升級前的資料。

## 開發與編譯

```
BillionairePlanner/          App（SwiftUI）
  Features/                  今天／目標／回顧／思考／設定（只負責呈現與輸入）
  Application/               所有會改資料的指令（Planner）
  Persistence/               v2 schema、v1 legacy schema、遷移
  Platform/                  通知、匯出、設定
PlannerCore/                 純規則（容量、估時、落後、恢復、重排、草案、介入、遷移映射），可 `swift test`
BillionairePlannerTests/     SwiftData 遷移與主要流程整合測試
```

- 雲端：推送到 GitHub `main` 會自動跑 Domain 測試、App 測試、macOS Release（Apple 晶片＋Intel）與 iOS 編譯；成品與紀錄在 `build` 分支。
- 本機測試（在 Planner 資料夾也穩定，產物放在系統暫存區）：
  ```bash
  cd ~/Desktop/Planner/BillionairePlanner_v<版本>
  bash scripts/test.sh --core   # 只跑 PlannerCore（最快）
  bash scripts/test.sh --unit   # Domain＋App 整合
  bash scripts/test.sh          # 全部（含 macOS UI 測試，第一次會要求「輔助使用」權限）
  ```
- 本機執行：Xcode 16 以上開啟 `BillionairePlanner.xcodeproj`，⌘R；或 `bash ~/Desktop/Planner/_Archive/build.sh` 產生 .app。
- 裝到 iPhone：Target → Signing & Capabilities 選你的 Apple ID。

## 版本管理

```
Planner/
├── BillionairePlanner_v<版本>.app   ← 最新版 App
├── BillionairePlanner_v<版本>/      ← 最新版原始碼
└── _Archive/                         ← 舊版 zip（原始碼＋.app）、version.sh、build.sh
```

```bash
cd ~/Desktop/Planner/_Archive
bash version.sh list
bash version.sh bump build|patch|minor|major "說明"   # 封存目前版 → 升版號 → 重新編譯
bash version.sh restore 1.0.0                        # 退回（目前版本先封存，可再 restore 回來）
```

版號四段 `主.次.修.建置`，目前版本見 `VERSION` 與 `CHANGELOG.md`。Apple 的顯示版本只能三段，所以 `MARKETING_VERSION` 用前三段，完整四段放在 build 號（`CURRENT_PROJECT_VERSION`）；App 內顯示 `v<版本>`，與資料夾名稱 `BillionairePlanner_v<版本>` 相同。GitHub 的 `v1` 分支保存 v1.0.0 原始碼。
