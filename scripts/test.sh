#!/bin/bash
# 穩定的測試命令（UAT-06）：所有建置產物放在系統暫存區，
# 不受 iCloud 桌面／Finder 延伸屬性影響，也不會在原始碼資料夾留下 .build。
#
#   bash scripts/test.sh            Domain＋App 整合＋UI 測試
#   bash scripts/test.sh --core     只跑 PlannerCore（不需 Xcode 專案，最快）
#   bash scripts/test.sh --unit     Domain＋App 整合（不跑 UI 測試）
#   bash scripts/test.sh --ui       只跑 UI 測試
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="${BP_TEST_TMP:-${TMPDIR:-/tmp}/BillionairePlannerTests}"
mkdir -p "$TMP"
MODE="${1:-all}"
XCB=(xcodebuild test -project "$ROOT/BillionairePlanner.xcodeproj" -scheme BillionairePlanner
     -destination 'platform=macOS' -derivedDataPath "$TMP/DerivedData"
     CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)

if [ "$MODE" = all ] || [ "$MODE" = --core ] || [ "$MODE" = --unit ]; then
  echo "▶ PlannerCore（scratch：$TMP/core-build）"
  CLANG_MODULE_CACHE_PATH="$TMP/module-cache" \
    swift test --package-path "$ROOT/PlannerCore" --scratch-path "$TMP/core-build"
fi
if [ "$MODE" = all ] || [ "$MODE" = --unit ]; then
  echo "▶ App 整合測試（macOS）"
  "${XCB[@]}" -only-testing:BillionairePlannerTests
fi
if [ "$MODE" = all ] || [ "$MODE" = --ui ]; then
  echo "▶ UI 測試（macOS）"
  "${XCB[@]}" -only-testing:BillionairePlannerUITests
fi
echo "✅ 測試完成（產物在 $TMP，可隨時刪除）"
