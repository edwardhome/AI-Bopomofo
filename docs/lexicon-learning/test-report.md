# 詞彙學習驗證與交付紀錄

本報告區分自動化證據與實機驗收。功能已進入開發交付階段，尚不宣稱完整 P0 或所有 macOS 應用相容性驗收完成。

## Phase 0 基準

以 `main` 的 `e32d0c23` 建立 `feature/lexicon-learning-v1`，引入工程詞庫實作 `99f86f6c`（本分支提交 `c4347afc`）。原工程詞庫分支 `a6b7da8b` 保留，未合併 main。

實作前 `scripts/test-headless.sh`：249 項通過、2 項跳過。兩個跳過案例為 ParselessLM sanity 與 ParselessPhraseDB stress。原 DerivedData 的 PCH 與模組映射不一致導致整合編譯失敗；改用獨立 `/tmp/aibopomofo-learning-baseline-deriveddata` 後，Debug build-for-testing 與 Release build 通過。沒有刪除測試或降低測試門檻。最終回歸時再現 Release 後切回 Debug 的同類 PCH 快取錯誤，改以 Debug／Release 分離的 DerivedData 完成驗證；保留失敗紀錄。

盤點發現候選選取不一定送出文字；一般注音選取僅修改 reading grid。部分路徑在建立 Committing 前清除 grid，因此實作將可靠詞彙快照附在不可變組字狀態，僅對實際送出的對應範圍計數。無法證明對應的路徑略過。

## 實作範圍

| 階段 | 本輪結果 |
| --- | --- |
| Phase 0 | 基準、分支隔離、提交事件與風險盤點完成 |
| Phase 1 | 有界觀察佇列、SQLite migration、彙總、事件去重、排除、備份及降級已實作 |
| Phase 2 | 獨立 XPC 模型服務、單一推論名額、取消、逾時、輸出驗證與重試上限已實作；真實 FM 未執行 |
| Phase 3 | JSON Schema、範例、匯出驗證、匯入差異、逐詞檢視及本機核准介面已實作 |
| Phase 4 | candidate_only Adapter、不可變版本、核准 receipt、原子指標、回復及組字快照已實作 |
| Phase 5 | 下列無介面測試、故障注入、整合編譯及微型效能量測完成；實鍵、管理 GUI、長時間與完整按鍵 P95 尚待驗收 |

`LearningCore`、`LearningStorage`、`LearningOrganizer`、`LexiconDeployment` 分開；正式詞庫載入不依賴 SQLite。觀察不寫入 UserOverrideModel、內建資料或私人 data.txt。第一版拒絕 prefer；沒有模型自動核准或自動上傳。

## 自動化結果

執行環境：macOS 27.0.1（26A434）、Xcode 27.2（27B52）。建置部署目標仍為 macOS 13；FM 僅於支援的 macOS 26 以上系統啟用。macOS 13 的實際啟動尚未測試。

| 檢查 | 通過 | 跳過 | 證據範圍 |
| --- | ---: | ---: | --- |
| C++ 引擎 | 124 | 2 | 包括明確選取擴充詞、清除、改選、編輯及原候選不變 |
| MixedInputCore | 72 | 0 | F 手勢、英文組字、Unicode、工程候選等既有回歸 |
| CandidateRanking | 34 | 0 | Mock 非合作模型逾時／取消及新增推論名額狀態機 |
| LexiconLearning | 24 | 0 | 儲存、交換、核准、回復及故障注入；含參數化部署失敗檢查 |
| Python | 28 | 0 | 原有語料與工程詞庫檢查、正式 JSON Schema 五項測試 |
| **合計** | **282** | **2** | 不包含只編譯的 hosted IME 測試 |

`make -C Source/Data check` 通過；Debug 整合測試 `build-for-testing` 成功，未執行 hosted IME、GUI、音效或模擬打字。Release 編譯與最終套件結果見下方交付補記。

## 故障與契約證據

- SQLite：唯讀寫入失敗、損毀開啟及隔離、較新 migration 拒絕降版、一致性備份還原、批次中途故障後計數與去重標記一起回滾。
- 空間不足以 before-COMMIT 注入錯誤模擬；沒有填滿使用者磁碟，也沒有以真實磁碟滿載驗證所有 macOS 行為。
- 觀察：滿佇列直接拒收、FIFO、重複事件不重算、部分提交／變更文字／取消不學習；明確記住與一般次數分開。排除後的自動提交略過，明確重新記住可撤回排除。
- 模型：以測試替身驗證不回應／延遲取消、世代隔離；非法輸出、無來源建議拒絕。模型提示不覆寫原始觀察欄位。尚未啟動真實 XPC 或 FM 進行端到端測試。
- JSON：重複鍵、未知欄位、截斷、過深巢狀、版本、控制字元、身分雜湊與優先度驗證；匯出也通過相同交換限制。機器 Schema 與 Swift 語意檢查分工見 schema.md。
- 部署：staged、verified、activating 三個故障位置保留原版本；舊預覽、同版本不同內容、重複匯入、損毀版本回退、無 SQLite 時核准與回復。
- 工程 Adapter：103 個既有詞條的輸出集合經共用格式往返保持一致；預載來源不標記成使用者核准或 FM 生成。
- 正在組字時延後取得新版快照的控制器路徑已編譯；GUI 實際組字不被打斷仍須實鍵驗收。

## 效能量測與限制

Release 模式 `LearningBenchmark`，各 100,000 次樣本，單位毫秒：

| 路徑 | P50 | P95 | P99 |
| --- | ---: | ---: | ---: |
| ObservationQueue 生產者，定期消費 | 0.000167 | 0.000167 | 0.000208 |
| 滿佇列，消費者停滯 | 0.000042 | 0.000083 | 0.000084 |

這只量測 offer 的佇列成本，**沒有量測完整 IMK 事件、詞彙快照及身分雜湊成本，也不能證明按鍵 P95 小於 10 ms**。未執行長時間跨應用打字、真實 FM 記憶體尖峰或取消後實際資源釋放量測。容量、批次、模型名額及 token 上限是已實作的限制，不是完整程序記憶體上限的證據。

## 重現方式

從儲存庫根目錄執行，以下指令不安裝或啟動輸入法：

```sh
python3 -m venv build/lexicon-schema-env
build/lexicon-schema-env/bin/pip install -r research/lexicon-learning/requirements.txt
export AI_BOPOMOFO_PACKAGE_CACHE="$PWD/build/DerivedData/SourcePackages"
export AI_BOPOMOFO_SCHEMA_PYTHON="$PWD/build/lexicon-schema-env/bin/python"
AI_BOPOMOFO_DERIVED_DATA=/tmp/aibopomofo-learning-debug scripts/test-headless.sh
export AI_BOPOMOFO_DERIVED_DATA=/tmp/aibopomofo-learning-release
scripts/build.sh Release
swift run -c release --package-path Packages/LexiconLearning LearningBenchmark
scripts/package.sh 0.6.13-dev.1 Release
scripts/verify-package.sh dist/0.6.13-dev.1
```

若相同版本的 dist 目錄已存在，打包工具會拒絕覆寫，請換新的開發版本號。本機原始紀錄保存於忽略版控的 `artifacts/lexicon-learning/`，不包含私人詞彙。這些紀錄不會推送到 GitHub。

## 尚未驗證與已知限制

1. 尚未安裝、重啟本機 IME，未操作管理 GUI、真實 FM 或 Secure Input 實鍵測試；完整操作步驟在 user-guide.md。
2. 未證明所有提交路徑皆能取得可靠詞彙；保守略過的情況見 spec.md，因此統計不是完整打字歷史。
3. 本機存放未額外加密，短詞仍可能敏感；匯出前須逐項檢視。無自動雲端傳輸。
4. 模型不可用只顯示合併的可用性／失敗狀態，不猜測模型版本。手動協助遇到尚未結束的背景推論時使用既有降級路徑。
5. 系統或 SQLite 錯誤的動態細節可能維持原訊息語言；主要選單、操作及提示已補齊三種語系，版面尚未 GUI 驗收。
6. 實際斷電、檔案系統毀損、長時間輸入、完整 IMK 延遲與跨應用相容性未測；故障注入不能代替這些證據。

未進行 main 合併、正式標籤、Release、私人詞庫修改或系統安裝。這些操作不屬本次交付；由使用者另行決定。

## Release 與提交紀錄

最終 Release 編譯成功。主程式與 ModelService.xpc 均包含 arm64、x86_64；verify-bundle.py 通過產品識別、103 個工程詞條、內嵌 XPC、無私人學習資料庫及 ad-hoc 簽章檢查。這是開發簽章，並非 Apple 公證發行。

- `b8203556`：Phase 0 基準與模組邊界。
- `0a1bca2b`：Phase 1 觀察、SQLite 與獨立儲存基礎。
- `2980bf31`：Phase 2–4 交換驗證、模型建議契約、故障與版本回復測試。
- `e5fc032f`：Phase 1–4 輸入提交介接、XPC 模型隔離、核准管理介面與候選快照。
- Phase 5 文件及建置驗證另以 conventional commit 保存；上述提交均在功能分支，沒有改動 main。

開發包為 `0.6.13-dev.1`，封裝來源提交 `d27d102d`；之後的提交只補交付文件。pkg、ZIP 校驗通過，pkg 解開後 86 個檔案逐一相符，ZIP 另行解開並核對全部 86 檔及簽章。打包期間有四行 `write: Permission denied` 診斷，但工具成功結束；後續獨立 staging 複製未再現，兩種封裝均未發現缺檔或內容差異，沒有隱藏該紀錄。

僅將以下兩檔複製至 `/Users/defu/Documents/AI Bopomofo/0.6.13-dev.1/`，與來源 SHA-256 一致；不宣稱 iCloud 雲端同步或另一台電腦下載已完成：

| 檔案 | SHA-256 |
| --- | --- |
| AI-Bopomofo-0.6.13-dev.1.pkg | aa5b738e98339ac7e022aa792fbe57bb07951e632c6715ca7e241c3529f1b0c6 |
| AI-Bopomofo-0.6.13-dev.1.zip | 8d9b56534943c64593cdfa8d058da34262473860c12b45bc154cc93ffe951843 |

GitHub 交付目標是 `edwardhome/AI-Bopomofo` 的 `feature/lexicon-learning-v1`，不是 main。未建立 Release 或標籤。

更新時間：2026-11-04T02:49:54+08:00
