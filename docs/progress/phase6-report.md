# Phase 6 報告：自動檢查與開源文件完成，人工矩陣待驗證

主要來源 Commit：2ad2c48、311644f、43909cc、717c745、277ad9b。文件／CI 的最後 Commit 可用 `git log -1` 查詢；不虛填文件自身尚未存在的 SHA。

實際已通過：C++ 122項（另2項跳過），Phase1 XCTest130＋Swift Testing87，Phase2 XCTest130＋Swift Testing97，Phase3純組字7項，排序11項，語料／評估器14項；不同階段重複案例不加總成獨立測試總數。`make -C Source/Data check` 退出碼0，工具不輸出個別案例數。最後Debug測試編譯與Release建置成功。最新版套件77個payload檔案逐檔比對通過，雜湊與簽章通過。

使用者回報突然發聲後未再啟動 hosted輸入法測試；這之後僅做純邏輯測試、CLI文字研究、建置與檔案驗證。沒有播放媒體、調音量、安裝／切換輸入法。

待人工驗證：TextEdit、Safari、Chrome、Word、VS Code、Terminal、iTerm2、Markdown編輯器及通訊軟體。完整清單在 docs/manual-validation.md，各項均未冒充通過。

已提供 README、LICENSE、AGENTS、CONTRIBUTING、CHANGELOG、SECURITY，以及架構、安裝、開發、混打、詞庫、排序、benchmark、隱私、故障排除文件。保留上游歷史與授權，沒有推送或公開發行。規格中的「日常取代既有輸入法」仍未驗收。

套件：dist/0.1.0-alpha、dist/0.2.0-alpha、dist/0.3.0-alpha 均保存。未建立正式版本 tag。

更新時間：2026-10-26T16:56:38+08:00

## 最後事件修正補充

Commit cbaf71f：修正上游重複flagsChanged分支與keyUp送入組字的問題。新增按下／放開／修飾鍵／其他事件序列測試，純邏輯8項通過、0失敗，保留真正keyDown自動重複。Release重新編譯成功；新產物dist/0.3.1-alpha，解包77檔、SHA-256與簽章均通過。尚未啟動hosted或GUI測試，未改變聲音／安裝限制。原0.3.0與更早產物保留作研究，不建議安裝日用。
