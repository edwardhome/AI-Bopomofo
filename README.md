# AI-Bopomofo

以 [McBopomofo](https://github.com/openvanilla/McBopomofo) 為上游的獨立 macOS 注音輸入法專案，目標為繁體中文、中英文、數字與程式符號混打，以及可選的本機候選排序。以 Zing 的混打與智慧選字體驗為產品參考。

目前已保存 `dist/0.3.0-alpha/` 的 app、pkg、zip，並保留 0.1／0.2 產物。最新 Release 含 arm64/x86_64，但實際 GUI 尚待驗收。

已實作明確 ASCII／英文組字、技術詞候選與本機詞庫匯入／匯出；尚未達到任意小寫無感混打或可用 AI 排序。

目前為本地 alpha 開發階段。沒有遠端發行；不得將研究模組的存在視為已完成 AI 輸入法整合。原版小麥注音使用獨立識別碼與資料夾，可並存。

- 建置：`scripts/build.sh Debug`
- 安裝：[安裝與解除安裝](docs/installation.md)
- 進度：[階段報告](docs/progress/)
- 研究：[上游](docs/research/upstream.md)、[架構](docs/research/architecture.md)、[混打](docs/research/mixed-input.md)
- 上游 README 保存在 `README.markdown`，授權原文在 `LICENSE.txt`。

使用者詞庫、輸入內容與 Kanata 設定不納入 Git。不擷取螢幕或其他應用的歷史內容、不上傳輸入文字、不使用雲端模型。

更新時間：2026-10-26T16:51:18+08:00

整體交付狀態見 [交付報告](docs/DELIVERY.md)，驗收清單見 [人工矩陣](docs/manual-validation.md)。
