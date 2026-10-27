# AI注音輸入法（AI-Bopomofo）

以 [小麥注音 McBopomofo](https://github.com/openvanilla/McBopomofo) 為基礎的 macOS 繁體中文輸入法客製分支，為中文、英文、技術詞彙與程式符號混合輸入而開發。由 [edwardhome](https://github.com/edwardhome) 維護；這是獨立衍生專案，並非小麥注音官方版本。

**目前版本：0.6.7 開發測試版。原始碼、安裝包與校驗檔已公開。** 歡迎朋友協助測試與回報，尚未完成所有 macOS 版本及應用程式的相容性驗證。

[下載 0.6.7](https://github.com/edwardhome/AI-Bopomofo/releases/tag/v0.6.7) · [安裝說明](docs/installation.md) · [專業詞彙匯入](docs/dictionary.md) · [回報問題](https://github.com/edwardhome/AI-Bopomofo/issues)

**0.6.7 新增**：在「偏好設定 → 進階」調整 F 長按等待時間（100～1000 毫秒、每格 50 毫秒），初始值保留 100 毫秒。詳見 [0.6.7 安裝與驗收](docs/installation-0.6.7.md)。先前 [0.6.6](https://github.com/edwardhome/AI-Bopomofo/releases/tag/v0.6.6) 保留供回退。

## 這個版本的特色

| 功能 | 使用方式與範圍 |
| --- | --- |
| 雙擊 Shift 切換英文／注音 | 快速按放 Shift 兩次，在輸入法內切換；游標旁短暫顯示「英文／注音」。0.6.6 已修正重複修飾鍵通知造成無法切換的問題，並完成使用者實機驗收。 |
| 不依賴 Kanata 的 F 數字／符號分層 | 開啟選單中的「長按 F 輸入數字／符號」並授予輸入監控；按住 F 超過設定時間（預設 100 毫秒）後按 R 輸入 `+`，放開 F 退出。中文、直接英文及 ASCII 組字均支援。 |
| 明確英文／ASCII 組字 | 從選單進入，或選擇啟用「Shift＋字母開始英文組字」。保留大小寫、數字與程式符號；Enter 送出。 |
| 專業詞彙候選與匯入／匯出 | 自訂英文技術詞以 UTF-8 純文字每行一詞匯入。原字串保留第一候選，Tab 選取補全，不擅自替換。 |
| 可切換全形／半形標點 | 關閉「使用半形標點符號」後，`Shift + ,` 為 `，`、`Shift + .` 為 `。`；開啟時為 `,`、`.`。普通注音鍵位保持原樣。 |
| Markdown 友善符號 | 反引號預設直接輸入，可搭配 F 分層輸入括號、運算符號與數字。 |
| 本機文字協助 | 對目前尚未送出的組字提供手動錯字檢查與英文續字建議；原文優先，明確接受後才採用。Apple 模型不可用時保留原文與可用的系統拼字回退。 |
| 保留小麥注音的傳統輸入 | 保留注音顯示、選字與既有詞庫；使用獨立識別碼，可與原版並存。 |

F 分層部分鍵位：

| 按住 F，再按 | 輸出 |
| --- | --- |
| Y / U / I | 7 / 8 / 9 |
| H / J / K | 4 / 5 / 6 |
| N / M / 逗號鍵 | 1 / 2 / 3 |
| 空白鍵 / 句點鍵 | 0 / 小數點 |
| Q / W / E / R | `/` / `*` / `-` / `+` |

完整鍵位見 [F 分層說明](docs/quick-symbols.md)，模式操作見 [Shift 與英文輸入](docs/vim-input.md)。短按 F 仍按原模式處理，短按 Shift＋F 保留大寫 F。

## 下載與第一次設定

1. 從 [Releases](https://github.com/edwardhome/AI-Bopomofo/releases/tag/v0.6.7) 下載 `.pkg` 安裝包及 `checksums.txt`。同一套件包含 Apple Silicon（arm64）與 Intel（x86_64），MacBook Air 不需要另外選 CPU 版本。
2. 按照[安裝說明](docs/installation.md)安裝，登出再登入後，於鍵盤設定加入「AI注音輸入法」。
3. 要使用 F 分層，開啟「長按 F 輸入數字／符號」，並在「隱私權與安全性 → 輸入監控」允許目前安裝的 AI-Bopomofo.app。
4. 要使用標準中文標點，取消勾選「使用半形標點符號」。新偏好預設半形，既有設定會保留。
5. 要使用 Shift＋字母英文組字，開啟同名選項；雙擊 Shift 的直接英文切換不依賴該選項。

本開發版使用 ad-hoc 簽章，沒有 Developer ID 簽章或 Apple 公證，下載安裝時可能出現系統確認。請先閱讀安裝說明；不需要停用整體 Gatekeeper 或 SIP。

## 專業詞彙怎麼加入

下載或複製 [technical-terms-example.txt](examples/technical-terms-example.txt)，以 UTF-8 純文字編輯，每行一詞，例如：

```text
SystemVerilog
PySide6
OpenOCD
STM32
```

從 AI注音第一層選單選「匯入專業詞彙…」，選取檔案。檔案上限 1 MiB、5000 詞；每詞最多 64 個可列印 ASCII 字元，至少包含一個英文字母，不含空白。中文詞、帶空白的片語及 CSV 不屬於此匯入格式，中文使用原有「編輯使用者詞庫」。

技術詞候選在「英文／ASCII 組字」模式使用；直接英文模式將按鍵交給應用，不顯示詞庫候選。完整範例、備份與匯出限制見 [專業詞庫](docs/dictionary.md)。

## 系統需求與目前限制

- 基本輸入部署目標為 **macOS 13 以上**；本次開發機實測為 macOS 27.0.1，其他系統與 MacBook Air 仍待測試。
- Apple Foundation Models 文字協助需要 **macOS 26 以上**及裝置上可用的 Apple Intelligence 模型；基本注音、英文模式與 F 分層不依賴模型。這不是雲端聊天或整份文件理解功能。
- 英文技術詞補全是確定性的前綴比對，並非 AI。尚未實作任意小寫英文與注音按鍵的無感自動判別。
- 已移除本專案新增的 Vim／Neovim／VSCodeVim 自動切換整合，避免反覆開啟鍵盤設定；編輯器可使用自己的輸入法套件。
- 0.6.5 已把原先無法執行的進階子選單指令移回第一層；診斷入口已實測可用，詞庫匯入／匯出及跨應用仍歡迎測試。
- 202 項無介面測試通過、2 項上游案例跳過；0.6.6 已有使用者確認雙 Shift 英文／注音來回切換及中文逗號，0.6.7 調整介面與 Air 實機仍待驗收。測試通過不代表所有應用皆相容。

協助測試請看[測試與回報](docs/testing.md)。從 Kanata 遷移時，先保留設定備份，在目標 Mac 確認 AI注音功能後再依原安裝方式停用或移除 Kanata；安裝包不會自行變更 Kanata。

## 隱私

文字協助只處理目前尚未送出的組字；不讀取整份文件，不保存已送出的文字歷史，也不上傳輸入內容。F 分層只在 F 手勢期間使用被動 key-up 監聽，略過非 F 鍵。選用的 20 秒診斷只記錄修飾鍵及控制狀態，不含文字或一般鍵碼，預設關閉。詳見[隱私說明](docs/privacy.md)。

## 開發

需要 Xcode 26 以上與 macOS 26 以上。內部模組／target 保留 `McBopomofo`，產品識別碼為 `org.aibopomofo.inputmethod.AIBopomofo`。

```bash
scripts/test-headless.sh
scripts/build.sh Release
scripts/package.sh 0.6.7-dev.1 Release
scripts/verify-package.sh dist/0.6.7-dev.1
```

詳見 [AGENTS.md](AGENTS.md)、[架構](algorithm.md)與[交付紀錄](docs/DELIVERY.md)。私人詞庫、Kanata 設定、輸入紀錄與本機備份不納入 Git。

## 上游作者與 MIT 授權

本專案衍生自 [OpenVanilla / McBopomofo（小麥注音輸入法）](https://github.com/openvanilla/McBopomofo)，保留其原始碼歷史、作者署名及 MIT License。感謝小麥注音作者與所有貢獻者提供基礎引擎、詞庫及 macOS 輸入法實作。

> MIT License — Copyright (c) 2011-2026 Mengjuei Hsieh et al.

完整授權原文見 [LICENSE.txt](LICENSE.txt)，上游 README 見 [上游 README](docs/README-upstream.markdown)。散布時須保留授權及著作權聲明；本軟體依 MIT 條款按現狀提供，不附保證。本分支新增程式碼亦以 MIT 授權提供，檔案中的個別著作權聲明保持有效。

第三方元件仍依各自授權：請參閱 [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md) 與 [licenses/](licenses/)。安裝包附帶對應授權文件；其中注音字型相關資料另採 Apache License 2.0，並非將所有第三方素材重新授權為 MIT。
