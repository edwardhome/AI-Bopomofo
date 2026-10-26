# 獨立 F 分層與 Markdown 輸入調整

本次分支：feature/ai-name-symbol-layer。以既有功能選單、CandidateProvider 與 KeyHandler 擴充，保留 Big5，不將它改成數字編碼器。F 計時只在 IMK 控制器內，計時器與事件由純狀態機管理，實際輸出經 KeyHandler 與不可變的 QuickSymbols 狀態。

產品名稱統一、簡化主選單、44 鍵映射、短按回放、長按放開退出、快捷鍵透傳、焦點生命週期清理與半形反引號已實作。未完成的注音音節不被 F 手勢取代；英文字串內不攔截 F。預設半形標點，保留舊版標點清單開關。

選字按鍵問題：NSComboBox 的選取通知可能早於編輯欄位字串同步。改為讀取 objectValueOfSelectedItem，並同步 stringValue，避免結束編輯再覆寫成舊值。編譯成功，需人工確認選取 asdfghjkl 後重新開啟設定仍保留。

實測結果與限制見 release-notes.md、quick-symbols.md。建置初次遇到既有預編譯標頭快取失效，僅清除產生的 PrecompiledHeaders 後重建；後續編譯錯誤已修正，最終 Debug 測試建置與 Release 建置成功。

沒有改動 Kanata 設定、全域鍵盤事件、私人憑證或遠端倉庫。使用者已授權本機安裝與重啟，備份與結果另記交付報告。最高原則為 Markdown 友善；Vim 專用全英文介面與原始 ji3 顯示暫緩。

更新時間：2026-10-26T17:34:05+08:00
