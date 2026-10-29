# 0.6.9 F 分層退格修正

更新時間：2026-10-29T11:08:20+08:00

使用者確認 0.6.8 的 F 主要功能驗收正常，新增回報「仍按住 F 時退格無效」與「退格無法連續觸發」。本版沒有更動長按門檻或符號配置。

## 修正

- QuickSymbols 原本吞掉未映射的退格事件，且每個符號直接送出，無可編輯組字。本版的獨立長按分層保留數字／符號組字，退格及向前刪除可編輯；放開 F 一次送出。原英文組詞仍保留其內容與游標。
- 分層只保留映射符號鍵的重複事件處理權，不再攔截退格。沒有收到 key-up 時，下一次新的 key-down 也能清除舊紀錄。
- 實體退格鍵的 DEL 字元轉為引擎原有的 Backspace 表示，保留既有注音與英文刪除邏輯。
- 刪除只作用於目前組字，刪完留在分層，還能輸入下一個符號。要刪除先前已送出的文件，先放開 F。手動選單符號模式維持原行為。

## 驗證

- C++ 122 通過、2 項上游設定跳過。
- MixedInputCore 45 通過，含持續退格、刪至空白後續輸入、英文游標、向前刪除、F 放開後 repeat 及漏 key-up 復原。
- CandidateRanking 28、Python 14＋4 通過；總計 213 通過、2 跳過。
- Debug build-for-testing 成功；新增 3 個整合案例只編譯，未執行 hosted／GUI 測試。
- Debug 首次遇既有 PCH 與 modulemap 快取不一致，只移除預編譯標頭快取後重建成功。
- 通用 Release 建置成功。日誌：artifacts/f-069-headless.log、f-069-debug-retry.log、f-069-release.log。
- 本版仍需 MacBook Air 與 iTerm2 實鍵驗收，不能以自動測試取代。

## 交付方式

使用者已更改後續授權：不再自動安裝或重啟，固定交付 iCloud 文件中的 pkg 與 app，並更新個人 GitHub。專案規則同步記錄此要求。沒有操作本機安裝、輸入監控、Kanata、音效或詞庫。

## Air 驗收

1. 注音與雙 Shift 英文各測一次：按住 F 達門檻，依序按 Y U I，組字應為 789。
2. F 不放開，長按退格，應連續刪到空白；再按 R，放開 F，應只送出 +。
3. 放開 F 後長按退格，應可連續刪除文件內容。
4. Shift 字母開始英文組詞後進入 F 分層，退格不提前提交英文，放開回到英文組詞。
5. 在 iTerm2 重做，確認沒有 f、ㄑ或等待點殘留。

## 交付結果

更新時間：2026-10-29T11:12:27+08:00

來源 7466dbc 已推送 fix/f-layer-backspace 與 v0.6.9 標籤。dist/0.6.9-dev.1 封裝及驗證成功，77 個 app 檔案與 pkg 解包結果一致。iCloud 文件的 AI-Bopomofo-0.6.9 僅複製 pkg 與 app，校驗一致，雲端同步與 Air 收到檔案未驗證。

GitHub 發布附件受阻：Brave 擴充套件未允許檔案 URL 存取，系統選檔替代路徑因 Mac 鎖定而無法操作。已保存 0.6.9 發布草稿，尚未公開 Release 或上傳附件。草稿位址：https://github.com/edwardhome/AI-Bopomofo/releases/edit/untagged-44782cee7304be5a6c50 。下次使用此草稿續傳，勿重建重複版本。需要本人解鎖 Mac 才能繼續原生選檔；不可代為解鎖。

```text
55b5c3dca1127c4d685d8223ec942f9b8c4095783306f37bac6bc7db778f5ef4  AI-Bopomofo-0.6.9-dev.1.pkg
7e325b1fd145356e72359e9f1f2befedb16d64c3fa640fbb6019f0e767af3639  AI-Bopomofo-0.6.9-dev.1.zip
```
