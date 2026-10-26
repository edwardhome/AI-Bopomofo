# AI注音輸入法（AI-Bopomofo）

以 [McBopomofo](https://github.com/openvanilla/McBopomofo) 為上游的獨立 macOS 注音輸入法專案，目標為繁體中文、中英文、數字與程式符號混打，以及可選的本機候選排序。以 Zing 的混打與智慧選字體驗為產品參考。

本次開發版本為 0.5.0-alpha，新增[本機錯字檢查與英文上下文預測](docs/text-assistance.md)。已安裝的 0.4.0 保持不變；新版本須先完成人工驗收。

以 Markdown 半形輸入為優先，新增不依賴 Kanata 的 [F 數字／符號分層](docs/quick-symbols.md)。

已實作明確 ASCII／英文組字、技術詞候選與本機詞庫匯入／匯出；尚未達到任意小寫無感混打或可用 AI 排序。

目前為本地 alpha 開發階段。Apple 本機模型已接入手動糾錯與英文續字；舊版中文候選重排序仍屬研究。沒有遠端發行。原版小麥注音使用獨立識別碼與資料夾，可並存。

- 建置：`scripts/build.sh Debug`
- 安裝：[安裝與解除安裝](docs/installation.md)
- 進度：[階段報告](docs/progress/)
- 研究：[上游](docs/research/upstream.md)、[架構](docs/research/architecture.md)、[混打](docs/research/mixed-input.md)
- 上游 README 保存在 `README.markdown`，授權原文在 `LICENSE.txt`。

使用者詞庫、輸入內容與 Kanata 設定不納入 Git。不擷取螢幕或其他應用的歷史內容、不上傳輸入文字、不使用雲端模型。

更新時間：2026-10-26T16:56:38+08:00

整體交付狀態見 [交付報告](docs/DELIVERY.md)，驗收清單見 [人工矩陣](docs/manual-validation.md)。
