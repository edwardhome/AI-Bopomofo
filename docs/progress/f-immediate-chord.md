# F 立即組合鍵開發紀錄

更新時間：2026-11-02T00:21:07+08:00

分支：fix/f-immediate-chord。開始前工作目錄已有 QuickSymbolLayer.swift 與 InputMethodController.swift 修改，已保存至忽略目錄 artifacts/f-immediate/pre-existing-changes.patch，再建立分支承接。沒有移除使用者既有修改的目的。

## 已完成

- FHoldGesture.Event.otherKey 明確帶入 isMapped。F 等待中收到合格映射鍵，立即沿用 timeout 的 beginLayer 路徑，不回傳 invalidate，不提前停止 FReleaseMonitor 或健康檢查計時器。
- 控制器先啟動分層，再呼叫 SymbolKeyOwnership.keyDown，最後把相同事件交給文字處理一次；第一個組合鍵的內容及放開 F 後的重複事件處理權均保留。
- 所有非按鍵觸發的 otherKey（提交、失焦、停用功能）明確使用 false；快捷鍵、修飾鍵與既有按鍵 repeat 不會提前啟動。
- Esc 實體鍵 53 加入反引號映射；按住 F 時可以立即使用，手動符號選單的 Esc 仍退出。ASCII 組詞內容與游標保留。
- 短按 F、原長按設定、未完成注音音節不攔截 F 的規則保留。F 先放開再按下一鍵仍正常打字；F 未放開就按映射鍵則視為組合鍵，包含快速打字的按鍵重疊，不能宣稱能辨識兩種相同事件序列的使用意圖。

## Shift 與 FM 後續實作

- 已依使用者澄清完成 Shift 首字母放開後組單字、第二個新字母確認連續大寫的兩種模式。空白／Enter 送出單字後回注音；刪空仍可輸入 mm。
- Shift 放開會遞迴更新 F 暫存／符號層中的英文狀態，保留外層 F 手勢及放開監聽。選單 ASCII 與雙 Shift 直接英文保持獨立。
- FM 使用整段未送出組字，提示詞補充容量及在／再語意；驗證阻擋漢字刪增、數值／單位改寫及中文旁的技術縮寫刪除。原文第一項，明確接受才提交。
- 完成中文 Mermaid 架構／依賴圖與主要事件路徑註解；上游授權保留。

## 驗證

- scripts/test-headless.sh 成功：C++ 122 通過、2 跳過，MixedInputCore 56 通過，CandidateRanking 32 通過，Python 14＋4 通過，合計 228 通過、2 跳過。
- Debug build-for-testing 成功。F 首鍵、Esc、Shift 放開與 F 包裝狀態等 IMK 整合案例只編譯，沒有執行 hosted／GUI 測試或模擬打字。
- 本機 Foundation Models 的 12 個人工編寫案例中，最終 11 個符合預期；「他跑的很快」沒有提出「得」建議。這是提示詞開發用案例，不是獨立準確率評估。[結果](../../research/text-assistance/context-results-0.6.10.json)。
- 通用 Release 建置與 bundle 身分、模式、詞庫及簽章檢查通過；app 版本 0.6.10／610。
- 詳細日誌在忽略目錄 artifacts/shift-context/，不包含私人輸入。

## 交付範圍

版本 0.6.10，build 610。使用者指定交付目錄改為 Documents 下的 AI Bopomofo，依版本分資料夾，只放 pkg 與 app。原始碼推送個人 GitHub 的本開發分支，不建立 Release 或草稿；不安裝、不重啟輸入法、不更改 Kanata。封裝與交付結果待最後核對。

## 尚待實鍵驗收

F＋R／Esc 在等待時間內立即生效、F 放開退出、中文與直接英文短 F、按鍵不重疊的快速打字、按住 F 連續退格、Shift 大寫與單字兩種模式，以及 MacBook Air／iTerm2 相容性。自動測試與模型探測不能取代這些實際操作。
