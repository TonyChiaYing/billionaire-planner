# 開發進度紀錄（可中斷續作）

> 用途：使用量不足或連線中斷時，下一個工作階段從這裡接續。每完成一步就更新。

## 目前任務：v2.0.0.2 — 依「v2.0.0.1 使用者測試與 Claude 反饋」優化
來源檔：v2.0.0.1_使用者測試與Claude反饋_2026-11-03.md

| # | 項目 | 狀態 |
|---|---|---|
| 1 | V201-UAT-02 UI 測試視窗在螢幕外（uiTesting 固定可見視窗、忽略保存狀態、isHittable 檢查、失敗診斷） | 已完成（待 CI） |
| 2 | V201-UAT-01 建立完成畫面容量重複計算（套用前預估／套用後實際） | 已完成（待 CI） |
| 3 | V201-UAT-03 目標缺漏文案（需要策略／需要下一步／兩者） | 已完成（待 CI） |
| 4 | V201-UAT-04 README 版本文字、V201-UAT-05 CHANGELOG UI 測試數量 | 已完成 |
| 5 | CI 全部通過（67 非 UI＋全部 UI） | 進行中 |
| 6 | 交付到 Desktop/Planner（封存 v2.0.0.1、放 v2.0.0.2），晨間閱讀旅程人工回歸 | 待辦（需要 Mac 連線） |

## 交付方式備忘
- 雲端編譯：推 main → GitHub Actions → `build` 分支有 .app zip 與各測試 log
- Mac 交付：zip（保留執行權限）→ 寫入 Planner → Finder「打開」解壓 → 舊版移垃圾桶（先封存到 _Archive）
- 版本：VERSION 四段；MARKETING_VERSION 三段；CURRENT_PROJECT_VERSION 四段
