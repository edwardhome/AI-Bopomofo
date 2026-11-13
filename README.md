# AI注音輸入法（AI-Bopomofo）

以 [小麥注音 McBopomofo](https://github.com/openvanilla/McBopomofo) 為基礎的 macOS 繁體中文輸入法，由 [edwardhome](https://github.com/edwardhome) 維護。保留傳統注音、選字與詞庫，加入英文組字、F 數字／符號層及本機文字協助。這是獨立衍生專案，並非小麥注音官方版本。

**主線固定為 `main`；目前正式版為 [1.1.0](https://github.com/edwardhome/AI-Bopomofo/releases/tag/v1.1.0)。** 新增可編輯 QWERTY F 分層、F 按下預覽與長按判定，修正 Shift＋F 長按轉小寫並精簡選單；使用者與工程詞彙可在統一 SQLite 中管理。[更新內容與驗證](docs/releases/1.1.0.md)

[下載版本](https://github.com/edwardhome/AI-Bopomofo/releases) · [安裝說明](docs/installation.md) · [F 分層](docs/quick-symbols.md) · [Shift 英文](docs/vim-input.md) · [詞彙匯入](docs/dictionary.md) · [自行編譯](docs/development.md) · [GitHub 命令列指南](docs/github-workflow.md)

## 1.2.0-dev.1：Ctrl＋數字加入詞組

開發分支新增 Ctrl＋2～9，從尚未送出的注音組字取對應字數，立即加入使用者詞庫，不必再按 Enter。預設取游標前方，可在「偏好設定 → 使用者詞彙」調整方向；原本 Shift＋方向鍵選取、Enter 加詞保留。本版未合併或發布，正式版仍是 1.1.0。[操作說明](docs/dictionary.md#ctrl數字加入中文詞組12-開發版) · [驗證與實鍵清單](docs/releases/1.2.0-dev.1.md)

## 1.1.0：可自訂 F 分層與精簡選單

F 按下即預覽 ㄑ／f，門檻內接任何下一鍵均正常打字；只有超過門檻才撤回預覽進入符號層。Shift＋F 優先英文大小寫，不再進層。偏好設定新增「F 分層」頁，可調整兩種長按時間、編輯 QWERTY 鍵位與還原預設。

不常用的 AI、診斷、標點及詞庫指令集中至「工具與詞庫…」視窗；既有功能保留。實鍵與畫面仍待使用者驗收，詳見 [操作說明](docs/quick-symbols.md)。

## 1.0.4：恢復組字內的長按轉小寫

1.0.3 經使用者實測仍未恢復。本版恢復原本已實測的組字內 repeat 轉換，加上每次組字保存的時間門檻；外層計時器即使沒有啟動或被取消，也不會讓長按永久失效。選單內容查詢不再取消計時，設定介面保留。1.0.4 實鍵仍待驗收。[共同版本規則](docs/versioning.md)

## 1.0.1：首字母長按與統一詞庫

Shift＋S 短按保留 `S`；持續按住字母 **S**，到達設定時間後將尚未送出的首字母改成 `s`，不連續產生 ssss。放開 Shift 後繼續組英文單字；第二個新 Shift 字母仍沿用連續大寫。長按的是字母鍵，在「偏好設定 → F 分層 → 首字母轉小寫等待時間」調整 100～1000 毫秒，預設 250 毫秒；與 F 分層分開設定。

透過「工具與詞庫 → 使用者與工程詞庫」：中文詞、英文碼、工程詞、Unicode 與中文別名關聯，在同一份版本化 SQLite 管理。中文別名需填確認過的注音，例如 `甲烷／ㄐㄧㄚˇ-ㄨㄢˊ` 可用注音選取「甲烷」，工程碼 `ch4` 則可選 `CH₄`。

提供新增、編輯、刪除、選取／完整匯出、匯入預覽核准、完整還原與上一版本回復。先採離線檔案交換，不加入雲端同步或語境記憶。原有私人文字詞庫與內建工程資源保留，需主動匯入管理副本；原版編輯及引擎學習仍沿用原儲存。已核准管理詞庫的使用不依賴 FM 或詞彙觀察。

[操作與實鍵驗收](docs/lexicon-learning/unified-sqlite-user-guide.md) · [SQLite 共用格式與資料流](docs/lexicon-learning/unified-sqlite-format.md)

## 0.6.14：停頓後自動建議

預設啟用組字旁的 AI 副駕駛：完整中文組字停頓後嘗試校正，未知英文／技術碼可取得拼字或 Unicode 排版候選。原文預設選中，Tab 選取、Enter 確認；繼續打字、退格、方向鍵與 F 都保留原本操作。模型失敗不改字，既有工程詞庫先回應。

只處理尚未送出的組字，不新增句子記憶。[操作與限制](docs/automatic-assistance.md) · [驗證報告](docs/automatic-assistance-test-report.md) · [未來語境規劃，尚未實作](docs/context-assistance-proposal.md)

## 0.6.13 開發版：長期詞彙學習與核准擴充詞庫

背景累積已送出的可靠候選，以本機 SQLite 彙總；Apple FM 僅在閒置時提出整理建議。觀察與背景整理預設開啟、可分別關閉。新增「AI 詞庫管理」可記住目前詞、篩選匯出 JSON、預覽校對結果、明確核准、停用及回復版本。未核准資料不進入正式候選；第一版只支援 `candidate_only`。

已核准詞庫可透過 JSON 更新，不必重新編譯輸入法。中文仍由原有引擎自動組句；擴充詞只有明確選取才影響當次組字，工程符號仍維持原文第一。模型使用獨立 XPC 服務，SQLite 與模型失效不作為正常輸入的必要依賴。

與 AI 新酷音的開發整合沿用 Lexicon JSON 1.0.0；Mac 可使用既有管理選單匯入／匯出選定詞條。共用的是完整交換檔，各機器仍需預覽核准；不共用運作中的資料庫，不自動同步。中文別名與傳統私人中文詞庫自動匯出尚不支援。參見 [跨平台交換操作、驗證與限制](docs/lexicon-learning/shared-integration.md)。

此功能已納入 0.6.14；完整管理介面與實鍵驗收仍需依文件逐項確認。詳見 [操作](docs/lexicon-learning/user-guide.md)、[規格](docs/lexicon-learning/spec.md)、[架構](docs/lexicon-learning/architecture.md)、[交換格式](docs/lexicon-learning/schema.md)、[測試與限制](docs/lexicon-learning/test-report.md)。

## 0.6.12 新增：工程與自然科學候選詞庫

預載 103 個整理後詞條，預設啟用；「工具與詞庫 → 工程與自然科學詞庫」可獨立關閉。用 Shift 英文單字或選單 ASCII 組字，輸入 `sio2` 可選 `SiO₂`／`SiO2`，`i2c` 可選 `I²C`／`I2C`，`lambda` 可選 `λ`，並附繁體中文提示。

三字元起展開前綴；兩字元只做完整比對，例如 `si` 只新增 `Si`，到 `sio` 才展開 `SiO₂`。**原文始終第一候選，明確選取才轉換**；有工程候選時不讓英文 AI 預測蓋過候選。雙擊 Shift 的直接英文與連續大寫行為不變。

原報告 97 列已逐列審核，其中 31 列修正，複雜且無法可靠表示的公式保留材料簡稱。這是實用輸入對照表，不是官方學術名詞認證；不自動更正文件，也不把預載資料寫入私人詞庫。[操作與實鍵驗收](docs/science-terms.md) · [完整對照表](docs/science-terms-catalog.md) · [審核紀錄](docs/science-terms-review.json)

## 快速打字與 F 分層

1.1.0 起，F 在門檻內接任何下一鍵都視為正常打字，不再只有 ㄑㄧ／ㄑㄩ 例外。等於門檻仍屬等待，超過門檻才進層；進層後 F 放開監聽持續到真正放開。

使用者原有 100／250 毫秒等設定保留，可在「偏好設定 → F 分層」調整 100～1000 毫秒。實際跨應用相容性仍需驗收。[完整說明](docs/quick-symbols.md)

## 主要功能

| 功能 | 使用方式 |
| --- | --- |
| 雙擊 Shift 切換英文／注音 | 兩次獨立短按切換直接英文，游標旁短暫顯示模式提示 |
| F 數字／符號層 | 開啟「長按 F 輸入數字／符號」並授予輸入監控，不依賴 Kanata；放開 F 退出 |
| 英文單字組字 | 開啟「Shift＋字母開始英文組字」，首字母後放開 Shift 繼續組單字；空白／Enter 送出後回注音，Esc 取消 |
| 連續大寫 | 持續按住 Shift，第二個新字母確認連續大寫；放開 Shift 回注音 |
| 小寫單位 | Shift＋M 長按字母 M 改成 `m`，再放開後輸入另一個 m；亦保留退格刪空後輸入 `mm` |
| 使用者與工程詞庫 | 同一份 SQLite 管理中文、工程詞與別名；離線匯入須預覽核准，可回復版本 |
| 整句 ASCII 組字 | 從選單進入，保留大小寫、數字與符號，Enter 送出 |
| 工程與自然科學詞庫 | 三字元前綴、兩字元完整吻合；可選 Unicode 及一般文字，中文只作提示 |
| 專業詞候選 | 匯入英文技術詞，以前綴比對補全；原文優先，不擅自替換 |
| 全形／半形標點 | 關閉「使用半形標點符號」後，Shift＋逗號為 `，`、Shift＋句點為 `。` |
| 本機文字協助 | 檢查目前未送出的中文／英文組字，或提供英文續字；由使用者明確接受 |

按住 F 期間的符號先在組字中編輯，可連續退格；放開 F 送出，若從英文組字進入則回到原英文組字。刪除範圍限目前組字，不跨入已送出的文件。

部分符號鍵位如下，完整表格見 [F 分層說明](docs/quick-symbols.md)：

| 按住 F，再按 | 輸出 |
| --- | --- |
| Y／U／I | 7／8／9 |
| H／J／K | 4／5／6 |
| N／M／逗號 | 1／2／3 |
| 空白／句點 | 0／小數點 |
| Q／W／E／R | 除號斜線／星號／減號／加號 |
| Esc | 反引號 |

所有映射鍵均需先讓 F 超過長按門檻。門檻內重疊視為正常打字；Shift＋F 優先英文大小寫。

## 安裝與設定

1. 從 [Releases](https://github.com/edwardhome/AI-Bopomofo/releases) 選定版本，下載 `.pkg`；`.zip` 是 app 的替代封裝。若頁面只有 Source code，表示尚未附上安裝包。
2. 依 [安裝說明](docs/installation.md)自行安裝並加入「AI注音輸入法」。套件包含 Apple Silicon（arm64）與 Intel（x86_64）。
3. 使用 F 分層時，在「系統設定 → 隱私權與安全性 → 輸入監控」允許目前安裝的 app，並開啟輸入法選單中的 F 功能。
4. 更新後若一般注音正常、F 分層卻失效，先檢查新版輸入監控授權及選單設定，參閱安裝文件，不必先重裝整套系統。
5. 英文組字、半形標點及長按時間可依個人習慣調整；既有詞庫與偏好不因新版預設重設。

目前套件使用 ad-hoc 簽章，沒有 Developer ID 簽署或 Apple 公證。基本輸入部署目標是 **macOS 13 以上**；Apple Foundation Models 文字協助另外需要 **macOS 26 以上**與可用的 Apple Intelligence 本機模型。尚未完成所有系統、應用程式與裝置的相容性驗收。

## 匯入專業詞彙

準備 UTF-8 純文字，每行一個英文技術詞，例如：

```text
SystemVerilog
PySide6
OpenOCD
STM32
```

從第一層選單選「匯入專業詞彙…」。檔案上限 1 MiB、5000 詞，每詞最多 64 個可列印 ASCII 字元，至少含一個英文字母且不含空白。候選用於英文／ASCII 組字，直接英文模式不顯示補全。中文詞彙使用原有「編輯使用者詞庫」。範例與備份流程見 [專業詞庫文件](docs/dictionary.md)。

## 本機 AI 與隱私

文字協助只讀取**目前尚未送出的組字**。原文保留第一候選，選取建議才套用；英文預測只能接續原字串，不能偷偷修改前綴。模型不可用時保留原文及可用的系統拼字建議。

例如 `我喝了500ML的水` 可建議 `我喝了500mL的水`，`我在去一次` 可建議 `我再去一次`。數字、技術詞、網址與程式碼受保護；模型仍可能漏判或誤判，不能當成自動改寫整份文件的工具。

不讀取整份文件、不保存逐句或逐鍵輸入歷史、不上傳文字。0.6.13 的可停用詞彙觀察另在本機保存可靠詞彙的彙總次數；匯出前請檢視敏感項目。F 只在手勢期間被動監聽 F 放開，立即略過非 F 鍵。選用的短期 Shift 診斷不記錄一般打字內容。詳見 [文字協助](docs/text-assistance.md) 與 [隱私說明](docs/privacy.md)。

## 開發與版本管理

- `main`：整合完成的主線；新工作從 `main` 建立 `fix/*`、`feature/*`、`research/*` 或 `release/*` 分支。
- `v0.6.x` 標籤：保存各版本的確切提交，不因主線更新而移動。
- Release：由擁有者手動建立並上傳安裝附件；推送或合併不會自動發布。
- 未合併的研究分支獨立保留，不會因整理主線而混入產品。

需要 Xcode 26 以上與 macOS 26 以上；內部 target／module 保留 `McBopomofo`，產品識別為 `org.aibopomofo.inputmethod.AIBopomofo`。使用無介面檢查，不啟動 hosted IME／GUI 測試：

```bash
python3 -m pip install -r research/lexicon-learning/requirements.txt
mkdir -p artifacts
scripts/test-headless.sh > artifacts/headless.log 2>&1
scripts/build.sh Release > artifacts/release.log 2>&1
```

打包前確認原始碼已提交，再選尚未使用的包名，例如：

```bash
scripts/package.sh 0.6.13-local.1 Release
scripts/verify-package.sh dist/0.6.13-local.1
```

版本前三段必須與 Info.plist 相同；打包不會自動修改 app 版本，也不會自動安裝。無介面測試與實鍵驗收分開記錄，整合測試僅編譯；實際 GitHub CI 狀態請看 [Actions](https://github.com/edwardhome/AI-Bopomofo/actions)。

[修改與編譯指南](docs/development.md) · [Mermaid 架構與依賴圖](docs/architecture.md) · [GitHub 命令列指南](docs/github-workflow.md) · [測試回報](docs/testing.md) · [專案規則](AGENTS.md)

Vim／Neovim／VSCodeVim 自動切換整合已移除，編輯器可使用自己的套件。本專案不自行變更 Kanata、已安裝的輸入法或私人詞庫。

## 上游作者與 MIT 授權

本專案衍生自 [OpenVanilla／McBopomofo（小麥注音輸入法）](https://github.com/openvanilla/McBopomofo)，保留上游原始碼歷史、作者署名及 MIT License。感謝小麥注音作者與貢獻者提供注音引擎、詞庫與 macOS 輸入法基礎。

Copyright (c) 2011–2026 Mengjuei Hsieh et al.

完整條款見 [LICENSE.txt](LICENSE.txt)，上游介紹見 [保留的上游 README](docs/README-upstream.markdown)。本分支新增程式碼亦以 MIT 授權提供，個別檔案著作權聲明保留。散布時須保留授權及著作權聲明；軟體依 MIT 條款按現狀提供，不附保證。

第三方元件依各自授權，見 [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md) 與 [licenses](licenses/)。安裝包包含授權文件；部分字型資料採 Apache License 2.0，並非所有第三方素材都改授權為 MIT。
