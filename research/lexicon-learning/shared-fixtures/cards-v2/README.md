# 詞彙卡 v2 公開合成測試資料

synthetic.json 由新酷音窗口建立，包含 bank 多義、行的多音、水的共享名稱／讀音、Unicode 及來源。沒有私人詞庫。

- independent.sqlite：以 Python sqlite3 執行本專案固定 DDL，再依 synthetic.json 插入；獨立於 Swift codec。
- swift.sqlite：本專案真實 Swift codec 產生。
- rust.sqlite、rust-boundary.sqlite：新酷音 Rust codec 產生；Mac 自動測試實際解碼並比對全部值及陣列順序。
- utf16-definition-boundary.json：256 UTF-16 units 的補充平面字元定義，完整保存原義，候選註解按完整字元邊界取最多 80 UTF-16 units。

重現 Swift 輸出：

```sh
AI_BOPOMOFO_CARDS_FIXTURE_OUTPUT=/tmp/cards-swift.sqlite swift test --package-path Packages/LexiconLearning --filter CardFixtureTests
```

新酷音來源位於其獨立 feature/lexicon-cards-v2 分支；Windows 完成 codec 測試不代表其 UI、候選投影或部署已完成。
