# 0.6.1 移除 Vim 整合與游標模式提示

更新時間：2026-10-26T23:49:02+08:00

## 需求與處理

使用者開啟 Vim 後回報反覆跳出鍵盤設定。先備份並停用本專案的 helper、Vim／Neovim 外掛及 VSCodeVim 自動切換，使用者確認「已停止跳出」。程式查核發現舊 helper 每次切換均呼叫 TISEnableInputSource，尚未啟用的英文來源選取失敗後，外掛又會在 FocusGained 等事件重試；沒有用真實按鍵自動重現事故。

使用者隨後明確要求移除本專案的 Vim 功能，改保留雙擊 Shift 與游標模式提示。因此沒有繼續安裝嘗試修復的整合版本。

- 移除 `integrations/vim/` 的 helper、安裝腳本、外掛及對應替身測試，並移除無介面測試腳本對它的呼叫。
- 本機移除 `~/.local/bin/ai-bopomofo-input`、兩個新增的 Vim／Neovim 外掛與四個新增的 VS Code 設定；逐項核對未更動其餘 VS Code 內容。既有 `.vimrc`、Neovim 設定及 VSCodeVim 擴充套件保留。
- 移除為 Vim 新增的獨立英文系統模式；若 macOS 暫時仍回傳舊模式識別，回退至有效的注音語言模型。沒有直接改寫系統輸入來源資料庫。
- 雙擊 Shift 或選單切換時，在客戶端提供的游標位置顯示「英文」或「注音」約 0.8 秒。獨立、非啟用式提示視窗不取代原有候選／工具提示，打字、組字狀態變更、失焦、來源切換時清除。Secure Input 不顯示；沒有有效游標座標時略過。
- 保留大寫英文組詞、雙 Shift 辨識、F 長按、ASCII 游標與本機文字協助。沒有變更 Kanata、聲音或音量。

本機整合備份在 `artifacts/vim-loop-stop/20261026T231647+0800/` 與 `artifacts/remove-vim/20261026T232126+0800/`。舊 Vim 工作階段仍可能保留記憶體中的自動命令，但已無可執行 helper；保存工作後正常重開即可清除，不強制結束使用者的編輯器。

## 驗證

`scripts/test-headless.sh` 的自動案例共 **192 項通過、2 項跳過**：C++ 122 項通過及 2 項上游跳過、MixedInputCore 24 項、CandidateRanking 28 項、Python 14＋4 項。詞庫完整性檢查通過。此次沒有新增對低影響提示繪製的模擬測試。

首次 Debug build-for-testing 遇到既有預編譯標頭與套件 module map 時間不符；只清理 PrecompiledHeaders 後重新編譯成功。未啟動 hosted／GUI 測試、模擬打字或音訊。

實機提示位置、持續時間、雙 Shift 切換、F 分層與跨應用行為仍需使用者驗收。Vim 設定不再反覆跳出的使用者回報屬先行停用驗收，不能當作新提示介面已驗收。

## 交付狀態

候選版本為 0.6.1／build 601，程式來源提交 `bbc5d32`。arm64／x86_64 Release 建置成功；最終來源的 Debug build-for-testing 亦成功。切換建置組態時再次遇到相同預編譯標頭過期錯誤，清理同一個 PrecompiledHeaders 後通過。證據位於 `artifacts/cursor-mode-headless.log`、`artifacts/cursor-mode-test-build-final-retry.log`、`artifacts/cursor-mode-release.log`。

套件保存在 `dist/0.6.1-alpha/`，pkg／zip 校驗、bundle 資源與簽章核對通過；pkg 解包後 77 個檔案與候選 app 一致。封裝與驗證記錄：`artifacts/cursor-mode-package.log`、`artifacts/cursor-mode-verify.log`。

安裝前已將現有 0.6.0 app 與偏好備份至 `artifacts/install-0.6.1/`，77 個備份檔案逐一核對一致。為避免外接磁碟權限問題，將 pkg 複製到獨立 `/private/tmp/` 目錄，確認 SHA-256 相同後交由系統 Installer 開啟。使用者完成系統驗證後，已確認原位置安裝為 **0.6.1／build 601**，77 個檔案與保存的候選 app 相同，bundle 資源及簽章核對通過。

更新後輸入監控仍為允許，但舊授權需求不符合新簽章。經使用者在系統設定完成驗證，移除舊項目並重新加入同一安裝位置的 app；唯讀驗證確認允許且符合 0.6.1。沒有改寫權限資料庫或修改其他 app 權限。

已重新啟動目標輸入法，PID 由 41030 更換為 44815，並僅選取已啟用的 AI注音混打來源，回傳 0；沒有呼叫 TISEnableInputSource，也沒有重新安裝 Vim helper。最後目前來源為 `org.aibopomofo.inputmethod.AIBopomofo.AIBopomofo.Bopomofo`。

安裝及重啟後的使用者資料雜湊與備份前一致；偏好僅 `NextUpdateCheckDate` 改變，既有輸入設定保持不變。核對摘要保存在 `artifacts/install-0.6.1/verification.json`。沒有推送或公開發布。

## 使用者回報

後續使用者確認選單直接切換會出現英文提示、F＋R 正常；但雙擊 Shift 完全不切換，也沒有提示。不能將選單與 F 的成功當成雙 Shift 已驗收。後續修正位於 `fix/double-shift-modifier-events` 分支。
