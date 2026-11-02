# 快速注音的 F 組合鍵保護

更新時間：2026-11-03T01:20:20+08:00

分支：`fix/f-phonetic-overlap`。版本：0.6.11／build 611。

## 問題與決定

使用者在 0.6.10 快速輸入「其實我是要告訴你怎麼去這裡」時，F 尚未放開就按 U／M，產生 8／2 而非 ㄑㄧ／ㄑㄩ。調高等待時間無效，因為立即組合鍵原本略過長按門檻。

採用注音優先：等待中的單義 ㄑ接ㄧ／ㄩ一律回注音引擎；先長按 F 超過設定門檻，再按對應鍵才輸出數字。等於門檻仍屬等待中。其他立即組合鍵及直接英文、Shift 英文、選單 ASCII 模式維持原行為。沿用既有時間設定，不寫入或重設使用者偏好。

## 實作

- KeyHandler 的 `prefersPhoneticFChord(firstKey:nextKey:state:)` 唯讀查詢目前注音鍵盤配置，排除英文狀態、未完成音節、非 ASCII 與多義映射；不試打或修改引擎。
- 控制器先依事件時間更新 F 手勢，只有仍等待、一般注音、兩鍵均無 Shift／快捷鍵修飾且非 repeat 時才查詢。
- `QuickSymbolLayer.canStartChord` 新增預設為 false 的 `prefersPhonetic` 參數。注音優先沿用 `.otherKey(isMapped: false)`，先還原 F，再處理目前鍵一次，不建立符號鍵歸屬。
- 取消這次等待後，晚到的 timeout、F repeat、被動監聽與 IMK 放開通知不能再次輸出 F 或啟動分層。真正進層的其他組合仍保留原有監聽生命週期。

## 自動驗證

- `scripts/test-headless.sh`：C++ 122 通過、2 跳過；MixedInputCore 60 通過；CandidateRanking 32 通過；Python 14＋4 通過。合計 **232 通過、2 跳過**。
- 新增四項純 Swift 測試，涵蓋兩個鍵、100／150／250／1000 毫秒門檻、門檻內／相等／超過、兩種放開順序、殘留 repeat／計時器、取消與其他立即組合鍵。
- 三項新增 IMK 整合案例涵蓋唯讀判斷、重播後的 ㄑㄧ／ㄑㄩ與長按數字、英文入口及各注音配置。Debug build-for-testing 成功，這些整合案例僅編譯，未執行。
- 通用 Release 建置及 bundle 身分、詞庫資源與簽章檢查通過。
- 過程修正 Swift Testing 對直接呼叫 mutating Bool 方法的巨集限制；舊 PCH 快取失效後移到忽略的 artifacts 目錄，再完整重跑成功。
- 日誌位於忽略目錄 `artifacts/f-phonetic-overlap/`。沒有 hosted／GUI 測試、模擬打字或音效。

## 手動驗收與交付

仍需由使用者在實際輸入欄位確認「其實我是要告訴你怎麼去這裡」、「其他、其中、去年、去除」，以及先長按 F 後的 8／2、F＋R／Esc、按住 F 退格、雙 Shift 與英文入口。自動檢查不代表 MacBook Air／iTerm2 實鍵驗收完成。

交付目標為 `/Users/defu/Documents/AI Bopomofo/0.6.11/` 的 pkg 與 app ZIP；沿用 ZIP 避免同步服務替未封裝 app 加入 Finder 資訊破壞簽章。只推送本修正分支，合併及 Release 由使用者自行操作。不安裝或重啟本機輸入法，不變更 Kanata、偏好或詞庫。

## 交付核對

已複製 pkg 與 app ZIP 至指定的 0.6.11 資料夾。兩個檔案 SHA-256 與封裝原件一致；從交付 ZIP 解開後的 77 個 app 檔案逐一一致，嚴格簽章檢查通過。

安裝包來源提交：`41dc00d0044488eb82c89385a75ee3dabc22ad81`。後續提交只補交付紀錄。

- `AI-Bopomofo-0.6.11-dev.1.pkg`：`c9feb6225ee4b8111afd6e9443c058ef268b5aed5bbd4f7f1c7c54c50446bb30`
- `AI-Bopomofo-0.6.11-dev.1.zip`：`609d038b46083ee66823c2dabde208fa327fe682137f91d51ac2330ad8a2e4a8`

## 使用者實鍵回報

記錄時間：2026-11-03T01:34:06+08:00。使用者回報：等待時間設為 100 毫秒時，「去、七、其」即使按鍵重疊也可正常輸入，手感合適。這是使用者實際驗收，不是 GUI 自動測試；沒有據此推定其他裝置或所有應用皆通過，也沒有修改新使用者的 150 毫秒預設值。
