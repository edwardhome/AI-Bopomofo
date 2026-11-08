# 新酷音與 AI-Bopomofo：共用詞庫操作與整合紀錄

更新時間：2026-11-08T20:18:24+08:00

本輪整合的是 `ai-bopomofo.lexicon / schema_version: 1.0.0`。Mac 使用 0.6.14 既有的擴充詞庫管理流程；新增的是固定跨平台回歸測試及操作文件，沒有變更輸入法執行程式、版本號或正式 Schema。Windows 使用 `chewing-kanata-lab` 的共用詞庫開發實作，不能以已發布的舊 1.1.0 代替。

後續發布：使用者另行授權正式發布後，Mac 以 0.6.15 重新建置封裝，Windows 對應 1.1.1。Mac 僅更新版本與發布文件，按鍵與詞庫處理邏輯仍相同；[0.6.15 發布說明](../releases/0.6.15.md) 記錄正式附件及驗證，下文保留先前整合階段的來源與開發包紀錄。

## 交換步驟

### Windows 匯出，Mac 匯入

1. 在含本功能的新酷音設定工具開啟「共用詞庫」。可匯出目前共用快照；如要匯出私人工程詞，先主動載入並選取要交換的項目。
2. 含中文別名的工程詞預設不能無損輸出為 1.0.0。只有使用者明確接受省略、看過逐項清單並確認後，才匯出基本輸入碼與文字；原始工程詞不變。
3. 將完整 JSON 放在自己選定的交換資料夾。Mac 建議 `/Users/defu/Documents/AI Bopomofo/SharedLexicon/`；可自行建立並透過已設定的同步工具或手動複製傳遞。本輪不替使用者開啟雲端同步，也不宣稱另一台已收到檔案。
4. Mac 開啟「AI 詞庫管理 → 匯入詞庫 JSON」，選取檔案，檢查差異與各筆讀音、文字、來源；選取要採用的項目，再按「核准選取項目」確認。
5. 新詞庫在安全組字邊界生效。中文共用詞為可選候選，工程符號須明確選取；既有原生組句和原文輸出保持既有行為。

### Mac 匯出，Windows 匯入

1. Mac 開啟「管理擴充詞庫」，選取要交換的已核准詞，使用「匯出選取項目」。待審資料也可由「匯出待整理資料」選取後匯出，但不等於已獲另一台的部署授權。
2. 另存新檔並傳至 Windows；兩台的本機路徑可以不同，不需把 SQLite 複製過去。
3. Windows「共用詞庫」匯入 JSON，檢查新增與衝突。相同身分的元資料衝突需決定是否採用匯入內容；同音不同詞與同字不同讀音均可共存。
4. 完成本機核准才部署；遇到正在組字的連線，等待其安全邊界切換。未明確核准的檔案不會因寫了 `approved` 就自行啟用。

兩端都需使用新的詞庫版本名稱表示變動內容。重新匯入相同資料不得重複新增；匯入檔缺少既有詞不表示刪除。第一版不做跨裝置自動刪除同步。

## 實際本機放置規則

| 用途 | Mac | Windows fork |
|---|---|---|
| 已核准擴充／共用詞庫 | `~/Library/Application Support/AI-Bopomofo/Learning/lexicons/` | `%APPDATA%\ChewingDev\SharedLexicon\` |
| 完整版本資料 | `<SHA-256>/lexicon.json`、`receipt.json` | `versions\<SHA-256>\lexicon.json`、`receipt.json` |
| 生效指標 | `active.json`，歷史指標與版本供回復 | `active.json` 內含 active、previous 與啟用狀態；`previous-active.json` 只是輔助紀錄 |
| 原有私人中文詞庫 | 預設 `~/Library/Application Support/AI-Bopomofo/data.txt`，可自訂 | `%APPDATA%\ChewingDev\chewing.dat` |
| 原有私人工程詞 | 依原有管理功能 | `%APPDATA%\ChewingDev\engineering-terms.user.json` |

兩平台的目錄與核准紀錄是各自的內部格式，**不能直接互拷整個 lexicons／SharedLexicon 目錄**。只交換管理工具輸出的 JSON。不要手動修改版本指標，不把核准憑證、私人 SQLite、原始詞庫或對話放進公開 GitHub。

上表從程式讀取路徑規則，沒有讀取使用者實際私人資料。Windows `store-id.json` 是本機儲存身分，亦不得當成共用檔案傳遞。

## 驗證範圍

本輪 Mac 新增 `SharedLexiconTests`，4 項無介面測試涵蓋：

- Windows 7 筆固定向量的身分、大小寫、精確 Unicode、音調查找及完整解析／匯出往返。
- Windows 提供的 8 組非法 JSON，均由 Mac 實際解析器拒絕。
- 不支援的 `zh_aliases` 明確拒絕，不改塞註解。
- 外部 approved 文件仍需本機核准；取消不部署、原有詞保留、重複匯入不多加、回復上一版，舊記憶體候選快照仍有效。

固定樣本來源、雜湊與重現命令見 [測試資料說明](../../research/lexicon-learning/shared-fixtures/README.md)。

Mac 本輪完整 `scripts/test-headless.sh`：292 項通過、2 項略過、0 失敗。包含 C++ 124 通過／2 略過、MixedInputCore 72、CandidateRanking 40、LexiconLearning 28、Python 28；詞庫資料檢查通過，hosted 測試目標僅 `build-for-testing` 編譯通過，未啟動。初次執行因系統 Python 缺少 jsonschema 中止；改用既有 `build/lexicon-schema-env/bin/python` 後完整重跑通過，未降低測試標準。

重現命令（在 repository 根目錄執行）：

```sh
AI_BOPOMOFO_SCHEMA_PYTHON="$PWD/build/lexicon-schema-env/bin/python" scripts/test-headless.sh
scripts/build.sh Release
```

`scripts/build.sh Release` 成功；`scripts/verify-bundle.py` 通過產品識別、103 筆工程詞、獨立 ModelService、未包含私人學習資料庫及 ad-hoc 簽章檢查。沒有執行安裝或啟動 app；不是 Apple 公證或實鍵相容性證據。

本機完整紀錄保留於忽略的 `artifacts/shared-lexicon/headless-missing-schema-env.log`、`headless.log`、`release.log`、`bundle-verification.log`；沒有將建置輸出或私人資料提交至原始碼。Mac 執行程式未變更，因此不重新封裝或覆蓋既有 0.6.14 安裝檔；原 pkg／app ZIP 仍在 `/Users/defu/Documents/AI Bopomofo/0.6.14/`。

Windows 已有的驗證紀錄位於 `chewing-kanata-lab/docs/verification/runs/RUN-20261108-SHARED-LEXICON.md`：270 項通過、1 項略過；Rust → Mac Swift → Rust 的 7 筆完整 JSON 欄位一致；原生與設定程式 Release 編譯及完整 nested patch 重播通過。這是 Windows 端提供的可核對紀錄，本文件不把它當成 Mac GUI 驗收。

## 主線與開發套件交付

使用者本輪明確要求整合。已以遠端 Git ref 核對：

- Mac `main` 已包含 `af141734`（跨平台回歸測試與文件）與 `b15beeb6`（設計交接）；後續本文件的交付補記只改文件。
- Windows `main` 已包含 `3d331c7e0890105ed8ce436db914c3a3346fe42c`。見 [Windows 整合驗證紀錄](https://github.com/edwardhome/chewing-kanata-lab/blob/3d331c7e0890105ed8ce436db914c3a3346fe42c/docs/verification/runs/RUN-20261108-SHARED-LEXICON.md)。
- Windows 開發套件為 `1.1.1-dev.shared.20261108`，位於 WorkstationX 的 `C:\Users\Defu\Documents\AI-Chewing\1.1.1-dev.shared.20261108`，未發布為 GitHub Release。
- Windows 最終版本測試維持 270 通過／1 略過；另有 23 項 package guard 通過。原生 31、設定程式 9 份 patch 完整重播；203 個追蹤來源檔與實際建置副本逐 byte 相同，前端輸出與公開字典雜湊亦通過比對。
- 初次封裝來源比對發現 Windows 換行差異，已保留失敗 clone，改用 `core.autocrlf=false` 的新 clone 重做並通過，未繞過套件檢查。

以上 Windows 套件與測試由負責該專案的 Codex 執行，Mac 整合端核對其提交、報告與遠端 main。兩邊都未執行安裝、重啟輸入法、建立標籤或發布 Release。

## 已知限制

- 中文別名尚未納入 1.0.0；兩端共同升級與 Mac 候選支援仍待後續工作。
- 傳統私人中文詞庫的自動匯出尚未完成。Mac 現有操作針對擴充詞／待審詞，不代表已自動擷取全部 `data.txt`。
- 交換資料的識別與 Unicode 無損；部署則重新核准。Mac 會清除匯入 usage 並改為本機 approved 狀態，不能用部署後統計欄位相同作為驗收標準。
- Windows 在 20,000 筆同碼合成資料的 debug 量測中，查找與候選快照約 18.9 ms，超過最初 10 ms 目標。這不是 Release 日常打字結果，但也不能宣稱大詞庫延遲已達標；需要後續效能量測與實機驗收。
- 匯入差異 UI、跨應用輸入、F／Shift 實鍵、Secure Input、兩個輸入連線同時組字及版本切換均尚未完成 GUI／實體按鍵驗收。
- 此次主線整合不等於發布新版；沒有安裝或重啟本機輸入法，不建立 Release 或標籤。
