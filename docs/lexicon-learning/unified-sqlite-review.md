# 統一 SQLite 規劃委派與人工審查

更新時間：2026-11-09T00:30:51+08:00

本紀錄僅涵蓋規劃文件與隔離工作副本。產品程式、SQLite migration、雲端傳輸及實鍵測試均未執行。

## GIS 實際派工

使用既有 OpenCode wrapper `python3 -B src/delegate.py run <spec.json>`，節點 `gis/GIS-AI-MODEL`、Thinking off、序列工作、零 wrapper 重試。輸入只有 Codex 審核的 brief、兩個公開 Swift 型別檔及來源雜湊；未提供私人詞庫或聊天紀錄。每次工作只允許變更 proposal.md、cases.json，驗收器不可修改。

| 工作 | Run ID | 控制器結果 | 人工結論 |
|---|---|---|---|
| 基本修復 smoke | 20261109T002154-7f1eabfa | PASSED，11.94 秒，5 個合成測試 | 接受其工具路徑可用，不外推產品能力 |
| 快照方案與八類案例 | 20261109T002248-3019b24d | PASSED，30.54 秒，報告結構檢查通過 | 不接受直接採用，存在實質錯誤 |
| 固定檔名與十二類案例修訂 | 20261109T002614-1263ec00 | PASSED，33.19 秒，報告結構檢查通過 | 部分概念可參考，案例不得直接採用；最終規則由 Codex 修訂 |

兩輪控制器均記錄 execution exit 0、reason null、event_errors 空、scope violations 空、source_unchanged true。這只驗證工作範圍與輸出結構，不能算八／十二個同步案例已測試通過。

證據保留在 OpenCode 專案的 `runs/<Run ID>/`：result.json、changes.diff、verify-0.log、before.json、after.json、workspace。任務規格為 `examples/lexicon-snapshot-plan-20261109-01.json` 與 `-02.json`。未量測本次 Codex token 節省率。

## 人工發現與修正

第一輪案例錯將 SQLite 快照按 JSON 驗證、用 mtime 決定版本、要求 WAL 必須先關閉、允許組字超時切換，且有不可靠注音範例與簡體字。沒有將這份草稿直接套用到產品或正式規格。

第二輪修正了 Backup API 與固定檔名概念，但仍有以下問題：

- 未知 SQL schema 被建議忽略欄位後接受，缺乏共同相容契約。
- 將一般組字提交算成詞庫 dirty，混淆正常打字、觀察與核准詞彙管理。
- idle_no_publish 案例沒有真正覆蓋 dirty=false 的閒置情況。
- 對衝突副本不存在與最終一致性作過度保證。
- 仍有簡體字；不符合 repository 文件規則。
- 產生時的本機優先策略，已被使用者後續「雲端 SHA 與基準不同時放棄本機修改」及「每週一次」決策取代。

不再以同一任務無限制重跑。Codex 接管修訂，最終以 [統一 SQLite 規劃](unified-sqlite-plan.md) 為準：每週一次、固定檔名、base SHA 判斷、雲端變更時下載且放棄本機未發布修改、下載不回傳；使用者另有獨立強制上傳入口。

## 新酷音協作

已向既有「新酷音」Codex 對話交付相同規格並要求 AGY 配合 Windows API 盤點與合成矩陣。Windows 端負責自己的隔離分支與原生 API 審查；Mac 端不修改 Windows 程式。本文件不將「已發送要求」當成 AGY 全部規劃完成或 Windows 實作驗收。

## 本輪驗證界線

只驗證 Markdown 差異、連結與最終規則一致性。未執行 app 編譯、產品測試、GUI、實體按鍵、雲端同步、私人詞庫遷移或系統安裝。沒有新增套件、模型、服務或排程；沒有合併 main、建立 tag 或發布 Release。
