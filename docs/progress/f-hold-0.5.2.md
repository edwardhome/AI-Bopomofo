# F 分層 0.5.2 回歸修正

使用者回報 0.5.1 的 F 分層完全無法開啟。唯讀檢查確認系統安裝 0.5.1、FHoldSymbolsEnabled 為 1，AI注音輸入法程序執行中，未發現 Kanata 程序。沒有改動設定或重新啟動輸入法。

程式檢查發現 0.5.1 將每次系統按鍵查詢的 false 直接作為 release，可能在 100 毫秒前提前取消手勢。沒有捕捉使用者真實按鍵，因此這是已確認的程式缺陷與合理原因，並非已重現的現場診斷。

修正為每次手勢獨立建立觀察狀態：查詢曾看到 true 後才接受 false 作為放開證據；否則依輸入法 key-down 與 100 毫秒計時進入。key-up 維持直接退出。分層中新的 F key-down 可退出，自動重複事件不退出。Esc 與切換輸入來源仍清除狀態。

限制：若應用沒有提供 key-up，且系統查詢也無法讀出按下，自動放開退出仍無法保證。此時使用再按 F 或 Esc 的退出方式；同樣情況下短按也可能被判成長按。無法以純邏輯測試保證所有應用的 IMK 事件行為。

MixedInputCore 20 項測試通過，其中新增全程 false 不取消長按、新的 F 按下退出、重複事件不退出及跨手勢不沿用觀察狀態。沒有執行 hosted／GUI 測試、音效、修改音量、改動 Kanata 或推送。

英文續字沿用系統 NSSpellChecker 優先、Foundation Models 稍後補充的流程；不能從使用者提供的單一句子判定建議來源。本次沒有變更 AI 流程。

更新時間：2026-10-26T21:52:48+08:00

Debug build-for-testing 與 Release 建置成功。工作分支為 fix/f-hold-unreliable-key-state。新版本尚未自動安裝；保留目前系統版本。

來源 Commit：a917941。候選產物位於 dist/0.5.2-alpha/；arm64／x86_64、識別碼、資源及簽章驗證通過。pkg 解包 77 檔與 app 一致，pkg／zip 校驗成功。app 為 ad-hoc 簽章，pkg 未簽署／公證。

```
865bda707608dca2d241bb31c1b78ef4ee2d4a24ef80cc3fae1c05f47d41eab1  ./AI-Bopomofo-0.5.2-alpha.pkg
fb5e8a993633dfbee5f5206c7d3e74bfce4091989e9a9a9eedd9c294b54bdc92  ./AI-Bopomofo-0.5.2-alpha.zip
```

## 安裝與重啟確認

使用者後續明確授權本對話每次完成檢查後直接備份、安裝與重啟。檢查時已安裝 0.5.2／build 502，77 個檔案與候選 app 完全一致、簽章通過，因此沒有重複安裝。發現舊程序仍在執行，先備份偏好設定至 artifacts/install-0.5.2/，切換鍵盤配置後僅終止本專案舊程序，再啟動已驗證的 0.5.2。新 PID：32537。TIS 啟用及選取回傳 0，確認目前輸入來源為 AI注音輸入法。

系統只有一份 AI注音輸入法，位於 /Library/Input Methods；使用者目錄的原版 McBopomofo 與 ZingIME 為不同產品，予以保留。未修改詞庫、Kanata 或音量，未執行實際按鍵測試。先前版本包仍保存在 dist，未刪除。

確認時間：2026-10-26T21:55:57+08:00
