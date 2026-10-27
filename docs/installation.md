# 0.6.7 開發測試版安裝

適用於 Apple Silicon 與 Intel Mac；基本功能部署目標為 macOS 13 以上，舊系統相容性尚待實測。Apple 模型功能另外需要 macOS 26 以上及可用的 Apple Intelligence。建議朋友先保留原有輸入法作為備用。

## 下載與核對

從 [0.6.7 Release](https://github.com/edwardhome/AI-Bopomofo/releases/tag/v0.6.7) 下載：

- `AI-Bopomofo-0.6.7-dev.1.pkg`：一般安裝，固定安裝到 `/Library/Input Methods/AI-Bopomofo.app`。
- `AI-Bopomofo-0.6.7-dev.1.zip`：app 備用封裝，僅在選擇使用者層安裝時使用。
- `checksums.txt`：下載檔案 SHA-256 校驗。
- `technical-terms-example.txt`：可匯入的公開技術詞彙範例。

若已下載兩個安裝封裝，可在相同資料夾執行 `shasum -a 256 -c checksums.txt`；只下載 pkg 時，核對校驗檔中該 pkg 的一列即可，未下載的 zip 不會通過檔案存在檢查。

本版 app 使用 ad-hoc 簽章，pkg 未以 Developer ID 簽署，亦未經 Apple 公證。若 macOS 阻擋，先確認下載來源與校驗值，再依 [Apple 官方說明](https://support.apple.com/en-gb/102445)從「系統設定 → 隱私權與安全性」針對該套件選擇「仍要打開」，並自行完成系統驗證。不要關閉整體 Gatekeeper、SIP，或使用全域略過檢查指令。

## 一般安裝

1. 若已有 AI注音，先切換其他輸入法，備份現有 app、偏好與使用者詞庫；不要同時保留系統層與使用者層兩份 AI-Bopomofo.app。
2. 開啟 pkg，依 macOS 提示核准安裝到原系統位置。首次安裝後，先保存工作並登出再登入。
3. 在「系統設定 → 鍵盤 → 文字輸入 → 編輯 → 加入輸入方式」加入「AI注音輸入法」，並從選單列選取。
4. 開啟「長按 F 輸入數字／符號」。再到「隱私權與安全性 → 輸入監控」加入並允許 `/Library/Input Methods/AI-Bopomofo.app`，依系統提示結束並重新打開。
5. **重啟後先切到 US／ABC 等既有輸入來源，再切回 AI注音。** 只看到來源名稱被選取，不保證重啟後的連線已恢復；若仍無法組字，保存工作後登出再登入。
6. 要使用中文逗號，取消勾選第一層選單「使用半形標點符號」；此時 Shift＋逗號輸出「，」。要使用 Shift＋字母英文組字，另開啟同名選項。
7. 在「AI注音輸入法偏好設定 → 進階 → F 長按等待時間」選擇 100～1000 毫秒，每格 50 毫秒；初始值維持 100 毫秒。詳見 [F 設定與驗收](installation-0.6.7.md)。
8. 試注音組字、雙擊 Shift 來回切換，以及長按 F＋R 輸出 `+` 後放開退出。對照[測試清單](testing.md)。

ad-hoc 版本每次程式更新，舊的輸入監控項目可能不再符合新版簽章。若 F 失效，透過系統設定移除舊 AI-Bopomofo.app 項目，再重新加入目前安裝的 app；僅切換開關不一定更新簽章。由使用者完成系統驗證，不修改權限資料庫。

## MacBook Air 與 Kanata

同一個通用 pkg 即可用於 MacBook Air。先備份該機器的 Kanata 設定與自動啟動設定，再停用 Kanata，避免兩套 F 分層同時處理按鍵。確認 AI注音的注音、英文、F 分層及常用應用正常後，再依 Kanata 原本的安裝方式解除安裝。

Homebrew、手動執行檔與 launchd 的移除方式不同；先確認目標 Mac 的安裝來源，不套用猜測的服務名稱或刪除路徑。保留設定備份以便復原。AI注音安裝程式不會安裝、設定或移除 Kanata，也不依賴 Kanata 執行 F 分層。

## 使用者層安裝（替代方式）

若不要使用 pkg，可在原始碼目錄執行 `scripts/install-debug.sh /絕對路徑/AI-Bopomofo.app`，把已解壓的 app 安裝到 `~/Library/Input Methods/AI-Bopomofo.app`。腳本會驗證 bundle，遇到既有系統層安裝或同名使用者層安裝時拒絕覆寫。兩種安裝方式擇一，不要同時安裝兩份。

## 保留資料解除安裝

先切到其他輸入法並從鍵盤設定移除 AI注音。系統層安裝可將 `/Library/Input Methods/AI-Bopomofo.app` 移到垃圾桶並完成系統驗證；不要移除原版 McBopomofo.app。使用者層可執行 `scripts/uninstall-debug.sh`，腳本把 app 移到備份位置。

保留 `~/Library/Application Support/AI-Bopomofo`、使用者指定的詞庫位置，以及 `org.aibopomofo.inputmethod.AIBopomofo` 偏好，可保留個人設定與詞彙。完成後登出再登入。
