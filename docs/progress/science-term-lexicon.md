# 0.6.12 工程與自然科學候選詞庫

## 實作範圍

使用者確認英文／符號候選、預設開啟可關閉、Unicode 與一般文字輸出。三字元開始前綴補全；兩字元只完整比對。原文第一、明確選取才轉換；不提供中文注音詞庫或 LaTeX。

分支 `feature/science-term-lexicon` 從 `main` 的 `e32d0c23` 建立。產品版本 0.6.12／build 612，開發包名 0.6.12-dev.1。不安裝或重啟輸入法，不自動合併、建立標籤或發布 Release。

97 列來源報告已逐列整理為 103 個詞條、158 個輸出變體；31 列修正，66 列收錄。部分修正列只保留材料簡稱，暫緩不可靠的公式變體，並非宣稱整篇報告學術內容正確。詳細理由與來源適用範圍見 [審核紀錄](../science-terms-review.json) 與 [操作文件](../science-terms.md)。不封裝原始 HTML、私人對話網址或報告全文。

詞庫於套件資源一次載入並建索引，失敗回退既有詞庫。候選輸出和中文提示分開；Unicode 編輯以完整字元邊界處理，外部按鍵驗證不放寬。切換開關保留原文並清除選取／預測；詞庫修訂號與原有狀態、Secure Input、焦點檢查共同防止延遲預測覆蓋工程候選。F 等待與符號層包裝保留。

## 本機驗證

- `scripts/test-headless.sh`：249 項通過、2 項跳過。C++ 122 通過／2 跳過、MixedInputCore 72、CandidateRanking 32、既有 Python 18、詞庫審核 Python 5。
- Debug `build-for-testing`：成功；新增候選提示、工程預測仲裁、包裝狀態重建與偏好保存案例，只編譯，不執行 hosted IME。
- 通用 Release：成功，含 arm64 與 x86_64。
- app 身分、詞庫資源及嚴格簽章檢查通過；app 中工程詞庫與審核後 JSON 逐位元組一致。
- 原始報告 SHA-256 與整理前一致；未修改已安裝輸入法、偏好或私人詞庫，未啟動 GUI、合成按鍵、音效或模型推論。

日誌保存於忽略的 `artifacts/science-term-lexicon/`。實鍵驗收尚未執行，不能把無介面測試或編譯成功當成 iTerm2／MacBook Air 的實際輸入驗收；操作文件附具體驗收步驟。

## 交付核對

記錄時間：2026-11-03T23:32:44+08:00。功能分支已推送至個人 GitHub，主線仍為 `e32d0c23`，沒有合併或建立 Release。

安裝包來源提交：`99f86f6c26f5a18429d500fa47ec76a7bbec6473`；後續文件提交只補交付紀錄。pkg 與 app ZIP 已複製至 `/Users/defu/Documents/AI Bopomofo/0.6.12/`，兩檔 SHA-256 與打包原件一致；解開交付 ZIP 後 83 個 app 檔案一致，包含 103 詞的資源與嚴格簽章均通過。只確認本機同步資料夾內容，不聲稱 MacBook Air 已下載完成。

- `AI-Bopomofo-0.6.12-dev.1.pkg`：`0c857df6345157e89066baa8f9af9434a36ca191dd7579d9ea867c10db40d7fb`
- `AI-Bopomofo-0.6.12-dev.1.zip`：`b91a35ef02a388dc0833cd7e0f2ffc12b1448ec36725abb56b55a04fb5e74821`

實鍵驗收仍待使用者自行安裝後進行；GitHub 最新檢查狀態見功能分支的 Actions。
