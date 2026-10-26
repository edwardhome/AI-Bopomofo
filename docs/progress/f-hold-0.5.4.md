# 具輸入監控權限的 F 手勢

使用者明確同意 AI注音輸入法使用 macOS 輸入監控。分支 fix/f-release-event-monitor；版本 0.5.4／build 504。從 IMK 收到符合條件的 F key-down 後建立 session listen-only key-up tap，主 RunLoop 處理。其他鍵碼立即丟棄，不讀文字、不修改事件；只在 F 手勢期間啟用。停止、切換、Esc 或監聽失效時清除監聽與計時器。權限檢查失敗則普通注音照常處理。

由公開 CGPreflightListenEventAccess／CGRequestListenEventAccess 檢查、申請權限；選單顯示允許狀態及系統設定入口。不寫入 TCC 資料庫、不新增 root 常駐服務、不修改 Kanata。已允許狀態僅代表系統權限，仍以建立 tap 成功才啟動 F 手勢。

19 項 MixedInputCore 測試通過，涵蓋門檻、短按、重複釋放、監聽失效與取消。Debug build-for-testing 成功。事件監聽本身尚未在真實按鍵下驗收，不得把這些測試當作實機成功。沒有執行 GUI／hosted 測試、音效或更改音量。

參考：[Apple 被動事件監聽](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions/listenonly)。

更新時間：2026-10-26T22:10:16+08:00
