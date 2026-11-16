# 詞彙卡 v2 開發驗收報告

更新時間：2026-11-16T23:48:44+08:00。

版本：2.0.0-dev.1；分支：feature/lexicon-cards-v2。未合併、未建立標籤、未發布、未安裝或重啟輸入法。

## 自動檢查

最終 scripts/test-headless.sh 成功：**356 項通過、2 項原有略過、0 失敗**。

| 類別 | 通過 | 略過 |
|---|---:|---:|
| C++ engine | 125 | 2 |
| MixedInputCore | 108 | 0 |
| CandidateRanking | 40 | 0 |
| LexiconLearning | 55 | 0 |
| Python corpus/schema | 28 | 0 |

詞庫資料 make check 成功。hosted IME 測試目標只執行 build-for-testing，TEST BUILD SUCCEEDED，沒有啟動。Release universal 編譯成功；verify-bundle.py 確認 103 筆內建工程詞、獨立模型服務、產品身分、資源、ad-hoc 簽章及未封入私人資料庫。這不是 Apple 公證。

新增涵蓋：多義詞共享名稱、copy-on-write 名稱編輯、同一詞義多讀音、Unicode 往返、v1 不推論同義的遷移、來源網址、模型逐項核准、草稿及版本過期、非法模型 JSON、合併及拆分、惡意額外 SQLite 物件、孤兒、版本錯誤、截斷檔案、啟用故障注入、取消預覽、SQL 損毀後復原 JSON、回復 v1，以及七次更新後仍可回復釘選原始版本。

三種語系的新增介面字串已補齊；沒有以刪測試或放寬驗證取得通過。

## 跨平台

新酷音窗口的獨立 feature/lexicon-cards-v2 以 main c0e23d1 為基底；WorkstationX 核心測試回報 **206 通過、0 失敗**，含 16 項新增 v2 測試。該測試數來自新酷音端報告，不與 Mac 計數混算。

Mac 已實際讀取 Rust 產出的 synthetic 與 UTF-16 邊界 SQLite，與原始公開合成 JSON 的所有欄位及陣列順序相同。固定 DDL SHA-256：677b32bae9b9c2a5f4de480ed8a296e420ff8c07010ddf5003f5a78dca1c6d4b。Rust synthetic SQLite：7edbccbb0aba4f283b85ee8bdaf14b0ea0bc8ead88553a5e9c4c4e6021595b21。

資料及重現方式：[合成 fixture](../../research/lexicon-learning/shared-fixtures/cards-v2/README.md)。Windows 尚未接上詞彙卡 UI、候選投影或部署，不能宣稱兩端已能經介面實際共用。

## 量測與失敗紀錄

Debug 合成 2,000 張卡片建立候選投影與索引約 254.94 ms；1,000 次查詢的 P95 約 0.0141 ms。建立索引在背景，不在按鍵路徑。這僅是本機模組量測，**不代表 IMK 按鍵 P95、跨 App 延遲或 GUI 流暢度已達標**。

多次重用 Xcode 衍生資料時遇到既有 GeneratedModuleMaps 與預編譯 header 的快取時間戳不一致。Release 改用獨立 build/CardReleaseDerived 成功；最終 headless 清除該測試衍生資料的 PrecompiledHeaders 後完整重跑成功。未修改編譯器驗證、未略過測試，保留失敗 log。詳細紀錄在忽略的 artifacts/lexicon-cards-v2/。

新酷音交叉檢查發現 256 UTF-16 詞義在衍生 80 UTF-16 註解時可能被錯誤拒絕；已修正為按完整字元邊界縮短候選註解，原始詞義不截斷，加入雙向邊界 fixture。

## 尚未驗證與限制

- 詞彙卡視窗布局、選單焦點、跨 App 實鍵、真正 FM 回應品質及可用性，尚未做 GUI／實機驗收。
- 真正磁碟滿、電源中斷或輸入中硬體故障未實測；部署回復及錯誤輸出以模組故障注入覆蓋。
- 中文投影維持既有一至八字，九字原生詞不被改寫；匯入顯示跳過項目。
- 新卡片整理由使用者主動觸發；原有背景觀察整理仍保留，不自動合併正式卡片。
- 沒有新增通用英文詞典、近似拼字引擎或直接英文的新組字模式。
- v2 維持版本化核准詞庫；私人觀察 SQLite、原生文字詞庫、內建資源仍各保留責任，不把未核准觀察一起分享。

操作步驟與實鍵驗收見 [使用指南](lexicon-cards-v2-user-guide.md)。
