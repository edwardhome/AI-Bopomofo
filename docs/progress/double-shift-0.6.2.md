# 0.6.2 雙 Shift 辨識修正

更新時間：2026-10-26T23:55:48+08:00

## 問題與修改

0.6.1 使用者回報：選單直接切換出現英文提示，F＋R 正常，但雙擊 Shift 完全不切換、沒有提示。因此此輪只修改雙 Shift 的事件適配與手勢模型，不修改提示繪製、F 分層、文字協助或已移除的 Vim 整合。

原適配層先以事件 keyCode 是否等於左右 Shift 決定能否辨識，再將 modifierFlags 交給純模型；既有模型測試皆假設 isShift 為真，未覆蓋這個入口條件。新版本直接使用 flagsChanged 中 Shift 狀態的按下／放開變化，不要求實體鍵碼，並以本機單調遞增的接收時間計時。完成雙擊切換後回報事件已處理。

重複的空閒修飾鍵快照不清掉第一下 Shift；Shift 持續按住時再收到按下通知則保守取消，以避免左右 Shift 重疊被當成雙擊。其他修飾鍵、打字、長按、失焦及 Secure Input 仍會取消。只處理 IMK 原本送達的事件，沒有增加全域監聽，也沒有記錄使用者文字或按鍵碼。

這是針對入口相容性的修正；尚未記錄實機事件序列，不能把「用戶端沒有傳入左右 Shift 鍵碼」視為已直接觀測的根因。安裝後仍須使用者實測確認。

## 檢查

新增 4 項純邏輯案例：重複空閒修飾鍵狀態、組合鍵釋放順序、兩個 Shift 完整重疊與釋放、無效及倒退時間。MixedInputCore 共 **28 項通過**。

`scripts/test-headless.sh` 整體 **196 項通過、2 項上游案例跳過**：C++ 122 通過／2 跳過、MixedInputCore 28、CandidateRanking 28、Python 14＋4。詞庫完整性與 Debug build-for-testing 成功，沒有執行 hosted／GUI 測試、模擬打字、音訊或音量操作。記錄：`artifacts/double-shift-core.log`、`artifacts/double-shift-headless.log`。

## 交付

版本 0.6.2／build 602，分支 `fix/double-shift-modifier-events`。建置、封裝、安裝與授權結果於完成後補記；目前不能宣稱實機修復通過。安裝前備份原 app 與偏好，更新後必須重新核對 F 輸入監控授權是否符合新簽章。不推送遠端。
