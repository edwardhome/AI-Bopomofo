# AI-Bopomofo 本次交付

已完成上游取得、獨立本地Fork、三份可安裝候選產物，以及不依賴AI的明確英文／ASCII組字與技術詞候選。原始碼與研究均已本地提交，沒有推送、公開發行或系統安裝。

最新版：`dist/0.3.1-alpha/AI-Bopomofo-0.3.1-alpha.pkg`，另有zip與app。來源Commitcbaf71f；主要功能Commit43909cc。arm64/x86_64 Release編譯成功，77個套件檔案逐一比對一致。沒有使用私人憑證，pkg未簽署、app僅ad-hoc，尚未公證。

pkg SHA-256：`e5b352e7905b87ca161865c14558f5381b262888bc6b747df5b565f751a9eeab`。

已實作：原生注音與上游候選、明確ASCII數字符號、Enter送出／Esc取消、游標編輯、技術詞Tab補全、可選Shift字母英文入口、專業詞匯入／匯出與備份。原版Shift標點保持；Kanata設定未更改。

AI研究：本機FM可執行，原生adapter及非同步協調器完成；500筆模板語料全數評估。但有害重排14.23%、P95約682ms，未接入app。此數據不能代表真實McBopomofo提升。

自動化實測見各phase報告，不重複加總跨階段案例。使用者回報發聲後未再執行hosted／GUI測試，後續僅純邏輯與編譯。Kanata設定校驗值仍為f60746ca8dfb10316e213d98ef6925df2963f14b03a11030f54ec6d592320455。

未完成：實機安裝／設定辨識、跨應用輸入與Kanata Unicode、詞庫面板操作、完整鍵盤事件P95、Secure Input／睡眠喚醒／長時間測試、無感小寫混打、AI品質與候選視窗生命週期整合、Developer ID／公證／公開遠端。因此沒有正式版本tag或daily-use beta聲明。

第一個人工驗收入口：檢視docs/installation.md後，自行選擇使用者層安裝最新版bundle，再依docs/manual-validation.md檢查。開發階段不自動安裝或改變目前輸入來源。

更新時間：2026-10-26T16:56:38+08:00

最後修正：cbaf71f將keyUp與修飾鍵分流，防止放開按鍵再進入組字。純事件／組字測試8項通過、Release重建與套件77檔比對通過；未執行GUI。先前0.1／0.2／0.3.0為已被取代的研究產物，請改用0.3.1做人工驗收。
