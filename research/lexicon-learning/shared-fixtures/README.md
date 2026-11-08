# Windows 共用詞庫契約樣本

這裡只有合成資料，沒有私人詞庫。來源是 `edwardhome/chewing-kanata-lab` 在提交 `2a8cb67` 的 `tests/shared-lexicon/fixtures/`。

- `windows-v1.json`：原 `valid-v1.json`，7 筆固定身分向量。由 Python hashlib 產生長度前綴 SHA-256，Windows Rust 與 Mac Swift 分別驗證。
- `windows-negative-cases.json`：原 `agy-negative-cases.json`，8 組非法 JSON。來源案例由 AGY 提出，Windows 測試與此 repository 的 `SharedLexiconTests` 使用實際解析器確認拒絕；模型提出案例不等於驗收通過。

原始 bytes SHA-256：

```text
07b43830e9b15c7cbcb37ad4ca98a6a2a12ecf04a1c2824bf141a737dd34ac47  windows-v1.json
46a0339d99609f2328d0c653857b07f7be543eed9cf14ad480b52e46ab6c3f6d  windows-negative-cases.json
```

Mac 測試入口：`swift test --package-path Packages/LexiconLearning --filter SharedLexiconTests`，亦包含於 `scripts/test-headless.sh`。測試對外來 approved 文件先預覽／取消、再次核准、重複匯入及回復，全部在獨立暫存目錄執行。

更新格式時，兩邊需重新核對固定向量、語意欄位與失敗案例；不得只修改期望值讓測試通過。部署會重新產生本機核准資訊，Mac 不將外來 usage 計數寫入本機學習資料；「格式無損往返」不表示跨機部署後核准狀態與統計皆不變。

資料來源：AI Chewing contributors；沿用專案授權，保留來源可追溯性。
