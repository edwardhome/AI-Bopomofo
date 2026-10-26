# 0.6.0 Vim、Shift 與英文 F 分層

分支 feature/vim-friendly-input。輸入法與候選包來源 Commit bfb21cc；後續另修正外部 helper 必須列舉尚未啟用的已安裝來源。24 項 MixedInputCore 測試及 2 項 Vim／Neovim 無介面替身測試通過，Debug build-for-testing 與 arm64／x86_64 Release 成功。新增的兩項英文組詞分層整合案例僅編譯，未執行 hosted／GUI 測試。上游既有 Shift＋F → FPGA 案例也僅編譯。

新增雙擊 Shift、全英文直接輸入模式、第三個英文系統來源。保留單按 Shift 與 Shift＋字母／快捷鍵。依使用者追加要求，F 長按同時支援全英文及英文組詞；Shift＋F 短按為大寫，長按為分層。ASCII 分層保留組字及游標，符號加入組字，不提前送出。切換全英文會先送出目前組字，不接受尚未確認的預測。

已安裝 VSCodeVim 1.32.4；本機 helper 安裝在 ~/.local/bin/ai-bopomofo-input，Vim／Neovim 自動載入外掛分別放在 ~/.vim/plugin/ 與 ~/.config/nvim/plugin/。未覆寫原 vimrc／init.lua，原有 macism 的 InsertLeave 指令仍保留。VS Code 的四個 autoSwitchInputMethod 設定已寫入並保存其他設定／註解。外部設定及工具備份保存在 artifacts/install-vim/，最初設定備份為 20261026T222601/vscode-settings-before.json。

已備份舊 app／偏好至 artifacts/install-0.6.0/，系統 installer 成功更新為 0.6.0／build 600。77 個安裝檔案與候選 app 完全一致，簽章與 pkg 校驗通過，輸入法已重啟。新 PID：38065。最後已選回本專案混打來源。沒有修改 Kanata、音量或推送遠端。

## 尚未完成的實機啟用

新增英文來源可由 TISRegisterInputSource 列舉，但當前登入工作階段中 TISEnableInputSource 回傳 0 之後 IsEnabled 仍為 false，TISSelectInputSource 回傳 -50。系統設定的加入清單也尚未顯示新英文模式，重新開啟系統設定後仍相同。沒有直接修改系統輸入來源資料庫或自動登出。

使用者選擇稍後自行登出，先保留成果。**Vim Normal／Insert 自動切換不能宣稱已實機成功**；待重新登入後，確認英文來源出現在輸入方式清單並啟用，再用 helper normal／insert 雙向檢查，最後人工測試終端 Vim／Neovim 與 VSCodeVim。VSCodeVim 可能需要重新開啟視窗。雙擊 Shift 與英文組詞中的 F 可先在目前 0.6.0 試用。

組字中的 Esc 仍先取消／隱藏預測，只有編輯器收到 Esc 並真正退出 Insert 才會切英文；不是任意情境單次 Esc 強制切 Normal。遠端 SSH／容器的 Vim 不在此整合範圍。

驗證時間：2026-10-26T22:45:12+08:00
