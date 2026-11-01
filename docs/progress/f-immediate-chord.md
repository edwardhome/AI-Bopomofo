# F 立即組合鍵開發紀錄

更新時間：2026-11-01T23:49:53+08:00

分支：fix/f-immediate-chord。開始前工作目錄已有 QuickSymbolLayer.swift 與 InputMethodController.swift 修改，已保存至忽略目錄 artifacts/f-immediate/pre-existing-changes.patch，再建立分支承接。沒有移除使用者既有修改的目的。

## 已完成

- FHoldGesture.Event.otherKey 明確帶入 isMapped。F 等待中收到合格映射鍵，立即沿用 timeout 的 beginLayer 路徑，不回傳 invalidate，不提前停止 FReleaseMonitor 或健康檢查計時器。
- 控制器先啟動分層，再呼叫 SymbolKeyOwnership.keyDown，最後把相同事件交給文字處理一次；第一個組合鍵的內容及放開 F 後的重複事件處理權均保留。
- 所有非按鍵觸發的 otherKey（提交、失焦、停用功能）明確使用 false；快捷鍵、修飾鍵與既有按鍵 repeat 不會提前啟動。
- Esc 實體鍵 53 加入反引號映射；按住 F 時可以立即使用，手動符號選單的 Esc 仍退出。ASCII 組詞內容與游標保留。
- 短按 F、原長按設定、未完成注音音節不攔截 F 的規則保留。F 先放開再按下一鍵仍正常打字；F 未放開就按映射鍵則視為組合鍵，包含快速打字的按鍵重疊，不能宣稱能辨識兩種相同事件序列的使用意圖。

## 驗證

- scripts/test-headless.sh 成功：C++ 122 通過、2 跳過，MixedInputCore 50 通過，CandidateRanking 28 通過，Python 14＋4 通過，合計 218 通過、2 跳過。
- 新增核心案例涵蓋提前啟動的監聽生命週期、全部映射鍵的首次處理與放開後 repeat、快捷鍵及未映射鍵、F 先放開的快速打字、取消及監聽失效。
- Debug build-for-testing 成功；新增整合案例驗證英文／中文分層的首鍵與 Esc、手動選單 Esc，僅編譯未執行。
- scripts/build.sh Release 成功，bundle 驗證通過。沒有執行 hosted／GUI 測試，沒有安裝、重啟、封裝、上傳 iCloud、推送 GitHub 或發布。
- 日誌保存在 artifacts/f-immediate/core.log、headless.log、release.log。

## 待確認

使用者另外要求「Shift 輸入若全程長按 Shift，直接跳出回到注音」，但放開 Shift 返回、單獨長按 Shift 返回、以及 Shift 按住時不進英文是三種不同互動。已提出澄清，尚未收到答案，因此這輪未改 Shift，以免破壞原有大寫英文及雙擊切換。實際 F 按鍵驗收亦待使用者確認。
