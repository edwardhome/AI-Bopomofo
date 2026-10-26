# 0.6.4 雙 Shift 診斷檔

更新時間：2026-10-27T00:25:32+08:00

0.6.3 的兩次人工操作都未取得系統日誌；連獨立日誌探針也未讀回，無法由此判定輸入法事件或選單動作故障。因此只更換診斷輸出，不修改手勢與 F 分層。

選單「進階工具 → 診斷雙擊 Shift（20 秒）」保持不變。手動啟用才寫入使用者快取路徑 `~/Library/Caches/org.aibopomofo.inputmethod.AIBopomofo/shift-diagnostic.log`，以 FileManager 解析使用者快取，不硬編碼 home。80 筆事件加一筆終止狀態，每次覆寫上次報告；目錄權限 0700、檔案 0600。不記錄文字、一般鍵碼、用戶端名稱；不增加全域監聽。Secure Input 立即停止，寫檔失敗也停止診斷而保留輸入功能。

無介面測試 196 項通過、2 項上游案例跳過：C++ 122／2 跳過、MixedInputCore 28、CandidateRanking 28、Python 14＋4。詞庫檢查與 Debug build-for-testing 成功；重建前僅清除已確認過期的預編譯標頭快取。沒有 hosted／GUI 測試、模擬打字或音訊。記錄：artifacts/shift-report-headless.log、artifacts/shift-report-debug-retry.log。

已備份目前 0.6.3 app 與偏好至 artifacts/install-0.6.4/，77 檔案核對一致；預設使用者資料目錄未存在。Release、套件及安裝待完成。此版並非雙 Shift 修復完成。
