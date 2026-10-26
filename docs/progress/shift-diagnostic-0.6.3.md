# 0.6.3 雙 Shift 限時診斷

更新時間：2026-10-27T00:16:24+08:00

0.6.2 使用者驗收未通過：目前注音及選單直接切換正常，雙 Shift 仍無效。本版是診斷版，並非已驗證的修復。

## 診斷邊界

手動點選「進階工具 → 診斷雙擊 Shift（20 秒）」後，回到原輸入欄位，連按放 Shift 兩次；可再重複一次。一般使用預設不記錄。每次上限為 20 秒、80 筆事件及一筆終止原因；Secure Input 會終止該次記錄。

只用輸入法原本收到的 IMK 回呼，記錄 flagsChanged 的修飾鍵位元、單調時間、程序內匿名控制器識別、啟用／停用／setValue 重設、一般 keyDown 重設類別及切換結果。不讀取或記錄文字、一般鍵碼、用戶端名稱，不新增全域鍵盤監聽，不變更 F 監聽範圍。紀錄存於本機系統日誌，分類 ShiftDiagnostic。

判讀時先確認 start 記錄存在，再比較 flags 是否到達、Shift 按放位元、事件間隔，以及中途是否重設或切換控制器；缺少 start 不能被視為沒有 Shift 事件。

## 檢查

無介面測試 196 項通過、2 項上游案例跳過：C++ 122／2 跳過、MixedInputCore 28、CandidateRanking 28、Python 14＋4。詞庫檢查通過；首次 Debug build-for-testing 遇到既有預編譯標頭快取過期，僅移除該快取再重建後成功。未執行 hosted／GUI 測試、模擬打字或音訊操作。

紀錄：artifacts/shift-diagnostic-headless.log、artifacts/shift-diagnostic-debug-retry.log。Release 與套件核對成功，arm64／x86_64 通用執行檔；77 個套件與安裝檔案完全一致。

## 安裝與待測

驗證時間：2026-10-27T00:20:03+08:00。程式來源提交 7c45c8c，產物 dist/0.6.3-alpha/。安裝前備份至 artifacts/install-0.6.3/，包含 0.6.2 app、偏好與使用者資料狀態；預設詞庫目錄未存在。使用者完成系統安裝及授權驗證，透過系統設定重新加入目前 app，唯讀核對 F 輸入監控允許且簽章需求符合 0.6.3。

已重啟為 PID 50195，目前為已啟用的 AI注音混打來源。偏好沒有差異，使用者資料狀態未變。驗證摘要 artifacts/install-0.6.3/verification.json。尚待使用者開啟限時診斷並手動按 Shift，沒有宣稱雙擊已修復，沒有推送遠端。
