# 0.6.1 移除 Vim 整合與游標模式提示

更新時間：2026-10-26T23:26:22+08:00

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

候選版本為 0.6.1／build 601。安裝與套件核對完成後另記錄結果；不推送或公開發布。更新 ad-hoc app 後須重新確認 F 輸入監控授權是否符合新版本，必要時只透過系統設定重新加入。
