# 實際狀態機

觀察、整理、核准詞庫是獨立控制軸；觀察關閉仍可整理已保存資料。

```mermaid
stateDiagram-v2
    [*] --> Disabled
    Disabled --> Collecting: 啟用觀察
    Collecting --> Disabled: 停用觀察
    Collecting --> Unavailable: SQLite 失敗
    Collecting --> Collecting: 有界批次彙總
    Disabled --> Disabled: 正常輸入繼續
```

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Running: 已啟用且閒置 有待整理資料
    Running --> Cancelling: 新輸入 停用 Secure Input 逾時
    Cancelling --> Idle: 同一請求結束 或服務中斷
    Running --> Idle: 回覆完成
    Running --> Deferred: 模型或資料驗證失敗
    Deferred --> Running: 五分鐘後 且未達三次
    Deferred --> Idle: 使用者重新啟用整理
```

ModelRequestLease 的 idle/running/cancelling 確保延遲舊回覆不釋放新請求名額。取消結果不能寫入 SQLite；XPC 服務超過 30 秒仍未結束時由自身 watchdog 結束程序。

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Validating: 使用者選擇檔案
    Validating --> Rejected: 格式 身分 版本限制失敗
    Validating --> Preview: 產生差異及逐詞檢視
    Preview --> Idle: 取消或關閉
    Preview --> Approved: 明確核准選取項目
    Approved --> Staging: 合併不可變版本
    Staging --> Verified: 回讀及雜湊驗證
    Verified --> Active: 原子切換指標
    Staging --> Failed: 寫入失敗
    Verified --> Failed: 指標切換失敗
    Failed --> Idle: 原版本保持有效
    Active --> Active: 新組字取得快照
    Active --> Previous: 使用者回復 或目前版本損毀
    Rejected --> Idle
```

版本切換不取消組字、不重啟輸入法。停用擴充同樣於安全邊界生效。

更新時間：2026-11-04T02:48:30+08:00
