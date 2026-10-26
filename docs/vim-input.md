# Vim 與 Shift 英文操作

## Shift 與 F

單按 Shift 不切換模式；Shift＋英文字母仍進入既有英文組詞、保留大小寫。只有兩次獨立的短按 Shift 才切換全英文直接輸入／混打：每次按住不超過 250 毫秒，兩次放開間隔不超過 350 毫秒。中間打字、其他修飾鍵、重疊左右 Shift、長按或切換輸入欄位都會取消辨識。選單「全英文直接輸入（雙擊 Shift）」顯示目前狀態。

全英文直接輸入把一般按鍵直接交給應用程式，不組注音、不顯示英文預測；混打保留既有英文組詞與 FM 提示。切換時先送出目前組字，未接受的預測不會自動接受。跨輸入來源或重新啟用欄位時，回到該輸入來源的預設模式。

**F 分層在中文、全英文直接輸入及英文組詞都保留。** 短按 f／Shift＋F 分別輸入 f／F；按住超過 100 毫秒則當作分層修飾鍵，不插入該次 f／F。保持 F 按住再按 R 就是 +；連按 R 可加入多個 +，放開 F 返回原文字模式。Shift 可以與長按 F 共存，Cmd／Ctrl／Option 的 F 快捷鍵不啟動分層。需要已允許的輸入監控權限。

英文組詞中，分層輸出的符號加入原本組字及游標位置，沒有提前送出或清掉文字。例如先有 Hello，再長按 F、按 R R、放開，組字變成 Hello++，可以繼續輸入。Shift＋F 長按可從空白進入英文組詞的分層，短按則輸入大寫 F。單純放開 F 後再輸入 rrrr，仍然是英文字母；分層只在 F 保持按住時有效。

## 編輯器整合

新增「AI注音輸入法 英文」系統輸入來源，保留 F 分層。Vim／Neovim 的 Normal、Visual、命令列模式使用它；Insert／Replace 模式回「AI注音輸入法」混打。用真正的 ModeChanged 事件判定，不靠猜測 i／a／o 或全域攔截 Esc。短按 f／F 仍是 Vim 的尋字命令，長按才進分層。

本地工具為 ~/.local/bin/ai-bopomofo-input；Vim 與 Neovim 分別載入 ~/.vim/plugin/ai-bopomofo.vim 與 ~/.config/nvim/plugin/ai-bopomofo.vim。不覆寫原 vimrc／init.lua。離開編輯器或失去焦點時，若仍使用本專案／ABC 來源，恢復啟動時來源；已手動切到別的輸入法則不覆蓋。終端機是否提供 FocusGained／FocusLost 仍取決於終端機支援。

VS Code 使用已安裝的 VSCodeVim（vscodevim.vim）與其 autoSwitchInputMethod 機制。Normal 預設來源為本專案英文模式；Insert 固定恢復本專案混打模式。設定與外掛可能需重新開啟 VS Code 視窗才載入。設定檔原文已備份於 artifacts/install-vim/，其他偏好與註解保留。

**組字尚未送出時，Esc 仍先處理輸入法的取消／隱藏預測；編輯器真正收到 Esc 並退出 Insert 後，才會切成 Normal 的英文來源。** 這版沒有把取消組字的 Esc 強制傳給 Vim。不能宣稱所有情況一次 Esc 就退出 Insert。

遠端 SSH／容器內的 Vim 不會自動控制本機輸入法；目前工具與外掛只支援本機 macOS。VS Code 整合使用官方 VSCodeVim 的模式切換機制，未覆寫所有使用者快捷鍵。

## 安裝與驗證

先安裝／註冊 0.6.0，再執行 integrations/vim/build-helper.sh 與 python3 integrations/vim/install.py。後者備份並安裝 helper、Vim／Neovim 外掛與四個 VSCodeVim 設定。需要本機已安裝 VSCodeVim。

24 項 MixedInputCore 測試通過；兩項無介面的 Vim／Neovim 測試以替身工具驗證模式切換及恢復，沒有改動真實輸入來源。兩項新增英文組詞分層整合案例僅編譯，未執行 hosted／GUI 測試。請人工確認 Shift＋F、大寫字串、Shift 快捷鍵、雙擊 Shift、各文字模式的 F 長按、Vim i／a／o／Esc 與 VSCodeVim 模式切換。

參考：[VSCodeVim 輸入法切換](https://github.com/VSCodeVim/Vim#input-method)、[Neovim 自動命令](https://neovim.io/doc/user/autocmd/)。

更新時間：2026-10-26T22:35:15+08:00

本機 0.6.0 安裝後，新英文來源在本次登入期間尚未啟用（選取回傳 -50）。使用者決定稍後登出再登入；Vim 自動切換仍待重新登入後驗證，不能當作已實機通過。若重新登入後仍未自動啟用，需在鍵盤設定加入「AI注音輸入法 英文」。
