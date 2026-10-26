# AI注音輸入法交接：0.6.0 的 F 分層失效

更新時間：2026-10-26T22:57:50+08:00

## 先讀這裡

後續更新：本次 F 失效已確認為輸入監控授權仍符合舊版 0.5.4、未符合已安裝的 0.6.0。透過系統設定移除舊項目並重新加入目前 app、重啟後，使用者已實測 F＋R 輸出 `+` 且放開正常。沒有修改程式或升級版本。詳見 [授權修復與驗證](f-layer-permission-recovery.md)；以下保留修復前的交接背景，原「先修程式再安裝」順序不再適用於此已定位問題。

使用者最新實測：「英文跟 AI 是正常的，但是分層失效」。目前首要工作是修復 F 長按分層，保留中英混打、英文提示、Shift 與 Vim 功能。這次只整理交接，沒有修正程式、重新安裝或執行登出。

使用者曾要求代為正常登出；先前 GUI 操作被中斷，沒有完成登出的可靠證據。不要重播舊登出要求，也不要假設已完成登出。若需要登入工作階段資訊，重新查核即可。不能把最新英文／AI 正常的回報，當作 Vim 自動切換或 F 分層已成功的證據。

## 工作區及版本

- 路徑：`/Volumes/DATA/DATA/AI_Bopomofo`。
- 分支：`feature/vim-friendly-input`；本次交接開始前工作目錄乾淨。
- `bfb21cc feat(input): add Vim English mode and double Shift with F layers`：0.6.0 安裝包的程式來源。
- `a131d08 fix(vim): discover installed modes and document activation pending`：後續 helper 與文件修正。
- `682229f fix(input): observe F release with authorized passive event tap`：0.5.4 的 F 修正，使用者曾實測成功；`387389c` 記錄其安裝驗證。
- 本次重新讀取已安裝 app 的 Info.plist，確認仍為 **0.6.0 / build 600**。
- 安裝位置：`/Library/Input Methods/AI-Bopomofo.app`。
- 套件：`dist/0.6.0-alpha/`；備份 app 與偏好：`artifacts/install-0.6.0/`。
- 詳細前次報告：`docs/progress/vim-0.6.0.md`；總交付記錄：`docs/DELIVERY.md`。舊文件中的功能描述是設計／實作狀態，不等於最新實機驗收通過。

## 不可遺漏的需求與授權

先讀根目錄 `AGENTS.md`，其規則優先適用。後續修正使用 `fix/*` 等隔離分支，保留上游功能、版權及詞庫；不推送遠端。

- 中文、全英文直接輸入、Shift 開始的英文組詞，都必須保留 F 分層，不依賴 Kanata。
- F **按住超過 100 毫秒**才進入分層；放開立刻離開，不是按一下進、再按一下退出。不要顯示分層選單。
- 按住 F 再按 R 輸出 `+`。Shift＋F 短按仍是大寫 F；長按須能分層，不能破壞既有 Shift 大寫與快捷鍵。
- 英文組詞中的符號插入原組字／游標位置，不提前送出、不丟掉前文。
- 雙擊 Shift 切換全英文／混打；Vim Normal 使用英文、Insert 恢復混打。使用者選擇 VSCodeVim，終端 Vim／Neovim 也要支援。
- 已授權後續迭代在檢查及可回復備份後安裝、重啟輸入法；保存既有安裝位置、偏好與使用者字典。
- 已授權 Input Monitoring，但只允許本機 F 手勢期間的被動 key-up event tap；立即丟棄非 F 鍵碼，不記錄文字、不繞過系統權限。
- 曾發生聲音驚嚇事件：禁止 hosted IME／GUI 測試、模擬打字、音訊及音量操作。預設使用 `scripts/test-headless.sh`；實際輸入由使用者驗收。
- 不修改 Kanata、不使用私人簽章、不記錄任何憑證。原始規格附件與 Kanata 可讀取但勿把私人內容複製到公開報告。
- AI 只處理目前未送出的組字；原文第一、明確接受，預測只能附加並保留前綴。失焦、編輯、切換及 Secure Input 均需使舊結果失效。

## 已知現象與尚未證實事項

0.5.4 使用被動 F 放開事件監測後，使用者明確回報數字與符號分層順暢。升級 0.6.0 後回報失效；最近又確認中文／英文／AI 可以使用，F 分層仍失效。

前次診斷曾讀到 `FHoldSymbolsEnabled = 1`、`MixedEnglishEnabled = 1`，系統設定 Input Monitoring 開關為開，當時 Kanata 沒有執行。這些是歷史觀察，需要必要時重新驗證。設定開啟不等於執行中的 app 能成功建立／維持 event tap。

前次有時讀到目前來源是 macOS US，後來選回 AI注音，使用者仍回報 F 不行且中文正常。因此不能只歸因於選錯輸入法；GUI 操作本身也可能影響目前來源。

新增英文模式先前可列舉，啟用呼叫回傳 0 但 IsEnabled 仍 false，選取回傳 -50。新登入後的真實狀態尚未重新查核。不要把這個來源啟用問題與 F 故障直接當成同一個原因。

## 程式定位與比較重點

- `Source/InputMethodController.swift`：F 計時、事件處理、短按重播、`FReleaseMonitor`、雙 Shift、直接英文與狀態切換。
- `Packages/MixedInputCore/Sources/MixedInputCore/QuickSymbolLayer.swift`：F 手勢與符號層模型。
- `Packages/MixedInputCore/Sources/MixedInputCore/DoubleShiftGesture.swift`：雙 Shift 辨識。
- `Source/KeyHandler.mm`：可否開始分層與組字狀態；`Source/InputState.swift`：QuickSymbols 保存 originalASCII。QuickSymbolHandler 的實際宣告位置請用 rg 查找，不要假設有獨立同名檔案。

0.5.4 流程：IMK 本機 F keyDown 建立 pending，保存原事件；被動 `.cgSessionEventTap`／`.listenOnly` 只訂閱 keyUp。每 0.01 秒檢查時間、Secure Input、client、tap 與權限。超過 0.1 秒進 held；F keyUp 結束。短按則重播原 F。tap 只在手勢期間存在。早期以 CGEventSource 鍵狀態輪詢的版本曾造成黏住或完全無法進層，不應直接恢復那條路。

0.6.0 差異：F 允許 Shift；pending F 期間 Shift flagsChanged 不再視為其他鍵；directEnglish 的一般按鍵放行在 F 處理之後；直接英文短按重播改送原字元。QuickSymbols 新增 originalASCII，進出分層保存／恢復英文組字；Shift＋F 長按可能先 beginASCII 再 beginQuickSymbols。狀態轉換中也調整取消 F 的條件。

下一步應比較 `682229f..bfb21cc` 的事件處理與狀態生命週期，查核手勢是否未起動、tap 建立失敗、計時被取消、進層後立刻退出，或事件被直接英文分支放行。這些是待查方向，不是已確定根因。必要診斷只記狀態／錯誤碼，不記使用者文字或非 F 鍵碼。

## 測試與建置證據

以下是前次結果，本次僅整理文件，沒有重跑：

| 檢查 | 前次結果 | 證據 |
| --- | --- | --- |
| MixedInputCore | 24 項通過 | `artifacts/vim-core-tests.log` |
| Vim／Neovim 無介面替身測試 | 2 項通過 | `artifacts/vim-integration-tests.log` |
| Debug build-for-testing | 成功，未執行 hosted 測試 | `artifacts/vim-build.log` |
| arm64／x86_64 Release | 成功 | `artifacts/vim-release.log` |
| 安裝包與安裝內容 | 前次 77 個檔案一致，簽章與校驗通過 | `artifacts/vim-package.log`、`artifacts/vim-verify.log`、前次進度報告 |

新增兩項英文組詞 F 整合案例與既有 Shift＋F → FPGA 案例僅編譯，不能稱為實際執行通過。純模型與替身測試不能證明 macOS 真實事件傳遞正常。

建置用 `scripts/build.sh`，封裝用 `scripts/package.sh`、`scripts/verify-package.sh`。曾遇到切換 Debug／Release 後預編譯標頭過期；只有出現相同診斷時才清理 `build/DerivedData/Build/Intermediates.noindex/PrecompiledHeaders` 後重建。

## Vim 與安裝細節

- `integrations/vim/` 包含 `input-source.swift`、`build-helper.sh`、`install.py`、`ai-bopomofo.vim`、`test-integration.py`。
- helper 已安裝到 `~/.local/bin/ai-bopomofo-input`；`current` 讀取來源，`normal`／`insert` 會實際切來源，並非唯讀。
- Normal 來源 ID：`org.aibopomofo.inputmethod.AIBopomofo.AIBopomofo.English`。必須使用本專案英文模式才能保留 F，不應直接改成 ABC 當作修復。
- Vim／Neovim 外掛安裝於 `~/.vim/plugin/` 與 `~/.config/nvim/plugin/`。未覆寫 vimrc／init.lua；原 dotfiles 中 macism InsertLeave 設定仍在，需留意與 ModeChanged 互動。
- VSCodeVim 1.32.4 已安裝，四個 autoSwitchInputMethod 設定已寫入 `~/Library/Application Support/Code/User/settings.json`，備份在 `artifacts/install-vim/`。
- 組字中的 Esc 先處理組字／提示；只有 Vim 真正收到 Esc 才回 Normal，不能聲稱任何情境單次 Esc 即切換。
- `artifacts/install-0.6.0/check-modes.swift` 可查模式；舊 `artifacts/install-0.4.0/check-source.swift` 可查來源。register／select／enable 類腳本會改狀態，使用前先讀內容。
- 前次安裝經系統 installer；外接磁碟上的 pkg 曾因權限讀取失敗，複製至獨立 `/private/tmp/` 目錄、驗 SHA 相同後才成功。安裝前備份；之後核對 app、版本、簽章並只重啟目標輸入法。

## 下一個視窗的執行順序

1. 讀 AGENTS.md、本文件及現有進度報告；確認 git 狀態，從現有成果建立 `fix/*` 分支，不丟棄 0.6.0 功能。
2. 唯讀核對實際來源、已安裝版本、執行程序與必要權限狀態，釐清新的登入狀態；勿重播登出或聲音相關操作。
3. 對照可用的 0.5.4 與 0.6.0，找出 F 失效的證據，再做最小修正。保留短按、大寫、英文組詞游標、放開即退出等需求。
4. 執行適合的無介面測試、建置與封裝驗證，寫出台灣正體中文結果及實際數量，提交 Conventional Commit。
5. 依既有授權備份、安裝及重啟；請使用者驗證中文／直接英文／Shift 英文組詞中的長按 F＋R、短按 F／Shift＋F 及放開後恢復輸入。
6. 再驗證新英文來源與 Vim Normal／Insert 切換。未實測完成的項目明確標示，不推送遠端。
