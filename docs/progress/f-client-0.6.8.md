# 0.6.8 延遲 F 與客戶端相容性

更新時間：2026-10-29T00:32:14+08:00

使用者回報雙 Shift 切入英文後，長按 F 仍出現 f；iTerm2 的注音短按會出現 fㄑ。核對現有 0.6.7，F 功能開啟、輸入監控符合目前簽章，沒有儲存過等待時間，因此不將這次問題歸因於舊簽章。

## 原因與修正範圍

現有控制器在等待 F 時只回傳已處理，沒有立即顯示組字或提交。iTerm2 的 [iTermKeyboardHandler.m](https://github.com/gnachman/iTerm2/blob/8634ad69501d81b49fdb5e1806a1bcb9b1aeaa9b/sources/Keyboard/iTermKeyboardHandler.m) 在 `shouldPassPostCocoaEventToDelegate` 中，若前後都沒有組字且沒有處理結果，會將按鍵再交給終端。空字串提交也不會將 `_keyPressHandled` 設為真。因此「原始 f 先送出，輸入法稍後處理為 ㄑ」與此路徑相符；這是原始碼分析，尚非本機實鍵重現證明。英文模式是否受同一客戶端路徑影響仍待驗收。

新增不可作為已提交文字的 PendingF 狀態，以「·」表示暫時等待，已有組字則維持原組字。進入分層、放開、模式切換、失焦與安全輸入會清除或還原此狀態；標記不進入組字內容、不提交至文件。空的 held QuickSymbols 也保留標記，避免長按重複事件被終端回退為 f。

FHoldGesture 區分被動觀察到放開與 IMK 收到放開，避免監聽器先結束手勢後讓後續 key-up 或 repeat 漏出；正常結束分層不再清除尚待處理的放開事件。新的按鍵／放開事件以原事件時間補算長按門檻，不單獨依賴 Timer 排程。

使用者提出小於 100 毫秒短按、大於 150 毫秒長按與可調時間。灰區暫採放開仍為原鍵，避免吃字；行為等價於 150 毫秒長按門檻，維持一個可調設定。沒有儲存過偏好時預設改為 150 毫秒，既有值保留。沒有新增全域 key-down 監控，也沒有修改 Kanata。

## 檢查

- C++ 122 通過、2 項上游設定跳過。
- MixedInputCore 40 通過，涵蓋灰區、事件順序、重複事件、下一次按鍵與延後計時。
- CandidateRanking 28 通過；Python 14＋4 通過。合計 208 通過、2 跳過。
- 通用 Release 建置與 bundle 驗證成功，含 arm64、x86_64；日誌 artifacts/f-068-release.log。
- Debug build-for-testing 成功；PendingF 的內容保護與偏好案例僅編譯，未執行 hosted／GUI 測試。
- 第一輪 Debug 遇既有 modulemap／PrecompiledHeaders 過期問題；只清除預編譯標頭快取後成功，最終完整腳本通過。
- 證據：artifacts/f-068-headless-final.log；實際輸入與 iTerm2 行為待人工驗收。

## 自行維護

[開發教學](../development.md) 已涵蓋環境、分支、修改符號、偏好與版本、測試、編譯、提交、打包、安裝、備份、回退及輸入監控更新。發布包沿用小麥注音 MIT 與第三方授權。這一輪先產生本機候選版，不自動發布新 GitHub release。

套件驗證：dist/0.6.8-dev.1 的 pkg 解包後 77 個 app 檔案與封裝 app 一致，識別、安裝位置與簽章通過，SHA-256 校驗成功。來源 b17f1ae。備份保存於 artifacts/install-0.6.8；安裝已送出，目前等待系統本人驗證，尚未重啟新版或更新輸入監控。

```text
405a16e3c69b9aae6b304b6cb8fc477c1353c611c31633ee9d901a1a1bd6bedf  ./AI-Bopomofo-0.6.8-dev.1.pkg
ed7b41f2e99f658dac50dc7f346e8dc3d01703283fef4909002c1430b5ee9ce4  ./AI-Bopomofo-0.6.8-dev.1.zip
```
