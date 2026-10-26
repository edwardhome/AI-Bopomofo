# Phase 3 報告

目標：技術詞候選、中英文明確意圖、保留大小寫與未知詞。

實作 Commit：43909cc。新增 Packages/MixedInputCore 純邏輯模組，並整合到 Source/MixedInput.swift、KeyHandler、InputMethodController、AppDelegate 及 Preferences。新增詞庫匯入／匯出與授權補充。

已完成：規格列出的 19 詞加 branch/module；原字串第一候選、Tab／上下鍵選詞、Esc 還原、未知字串原樣保留；預設關閉的 Shift＋字母入口，優先尊重上游切換來源設定。自訂詞沿用原 data.txt 與監視器，按鍵路徑不讀檔。匯入前本地備份、去重，匯出只含英文專業詞。

測試：`swift test --package-path Packages/MixedInputCore`，7 項通過、0 失敗，其中 literalRoundTrip 含 10 組參數。`swift run --package-path Packages/MixedInputCore -c release MixedInputBenchmark`，5000 自訂詞、20000 組字更新，P50 0.132084 ms／P95 0.169250 ms／P99 0.225708 ms；不含 IMK、UI、中文引擎或冷啟動。

建置：`xcodebuild -project McBopomofo.xcodeproj -scheme McBopomofo -configuration Debug -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build-for-testing` 成功；只編譯測試，沒有執行 hosted tests。新增的 2 項 hosted 整合測試尚未執行。`scripts/build.sh Release` 成功，包含 arm64 與 x86_64；Intel 執行未驗證。

已修復：Swift 6 benchmark 的 MainActor 隔離編譯錯誤；取消 ASCII 後再進入的空狀態處理；匯入重複詞的上游 return NO 語意。

套件：dist/0.3.0-alpha/AI-Bopomofo-0.3.0-alpha.pkg、zip、app。打包來源 Commit 277ad9b（包含研究成果）；套件驗證程式解包比對 77 個檔案完全相同，位置固定 /Library/Input Methods，簽章與 SHA-256 通過。

限制：GUI 與匯入／匯出面板尚未操作驗收；只有純邏輯測試實際執行。本版不是任意小寫鍵序列的無感語言辨識，無法宣稱與 Zing 體驗等同。候選、完成中文與英文的實際跨應用流程仍待人工驗收，故不建立正式 v0.3.0-alpha tag。

下一步：人工安裝與候選操作驗證，再決定是否改善英文觸發流程。AI 品質獨立評估。

更新時間：2026-10-26T16:50:00+08:00
