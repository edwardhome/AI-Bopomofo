# 0.6.6 重複 Shift 狀態修復

更新時間：2026-10-27T01:01:55+08:00

## 實機證據

0.6.5 使用者啟動診斷後只按 Shift，同一 IMK 控制器依序收到 Shift 按下、重複按下、放開、重複放開。兩次相同快照相隔約 5–11 毫秒，實際短按約 80–100 毫秒。所有 flags 為 131072（Shift）或 0，沒有其他修飾鍵、焦點重設或文字記錄。來源 artifacts/install-0.6.5/shift-only-diagnostic.log。

原模型遇到重複按下就取消，且這個錯誤假設被原本的「重疊 Shift」案例固定下來。新增匿名時序重放先驗證修正前會失敗：前 16 筆預期切換兩次，實際零次，記錄 artifacts/duplicate-shift-reproduction.log。

## 修正

只依實際 Shift 狀態轉換開始或結束一次短按。重複快照不取消，也不重設首次按下時間，確保長按仍會被拒絕；其他修飾鍵、打字、失焦與安全輸入的取消機制保持。以連續 Shift 狀態僅算一次按住取代不可靠的左右 Shift 推測；完整放開後才能開始下一次。

新增實機時序與重複按下不得縮短長按的兩項案例；把原錯誤重疊假設改成連續狀態單次計數及焦點重設案例。無介面測試 198 項通過、2 項上游案例跳過：C++ 122／2 跳過、MixedInputCore 30、CandidateRanking 28、Python 14＋4。詞庫、Debug build-for-testing 與 Release 成功；Debug 僅在已知快取過期錯誤後清除預編譯標頭再重建。記錄 artifacts/duplicate-shift-headless.log、artifacts/duplicate-shift-debug-retry.log、artifacts/duplicate-shift-release.log。沒有 hosted／GUI 自動打字測試、音訊或 Kanata 變更。

已備份目前 0.6.5 至 artifacts/install-0.6.6/，77 檔案核對一致，含偏好與使用者資料狀態。套件及安裝待完成，雙 Shift 實機尚待驗收。

## 安裝與驗收完成

2026-10-27T01:12:56+08:00：0.6.6／606 已安裝至原系統位置，77 檔案與套件一致。使用者完成安裝並自行更新輸入監控；唯讀核對允許且符合目前簽章。程序 PID 56116，切至既有 US 再選回 AI注音以重建連線。偏好差異鍵：NSNavPanelExpandedSizeForOpenMode, NSOSPLastRootDirectory，使用者資料未變，半形標點保持 false。摘要 artifacts/install-0.6.6/verification.json。

使用者明確確認雙擊 Shift 已能順利在英文與注音間切換。0.6.5 已確認中文逗號與診斷啟動；尚未對全部 macOS 版本、應用與詞庫匯入／匯出完成實機矩陣。程式來源 b0ba814，純測試 198 通過／2 跳過，GUI 人工驗收與自動測試分開記錄。
