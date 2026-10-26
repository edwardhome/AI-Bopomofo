# Apple Foundation Models 研究與非同步排序原型

更新時間：2026-10-26T16:15:04+08:00

## 結論與交付範圍

本機可用 Apple FM，CLI 與原生 Swift 均已完成真實推論。20 筆人工語料沒有呈現整體準確率優勢，且曾將正確技術名稱改選成另一個既有候選。**不建議預設啟用，也不應接入每次按鍵的等待路徑。** 此提交提供可替換排序介面、安全協調器、原生本機 adapter 及可重跑的小型實驗；尚未整合輸入法候選視窗，不能宣稱 v0.4.0-alpha 已完成。

一般注音、中英混打與打包工作不依賴本模組。Zing 的混打體驗應先由規則、明確的使用者意圖與詞庫達成，不能以這次實驗替代產品驗收。

## 本機證據

| 項目 | 實際結果 |
|---|---|
| 系統／架構 | macOS 27.0.1（26A434），arm64 |
| 開發工具 | Xcode 27.1（27A9275）、Swift 6.4 |
| CLI | `/usr/bin/fm`，提供 `available`、`respond`、`schema`、`license` 等子命令 |
| 模型狀態 | `fm available` 回傳 `System model available` |
| 使用條款 | `fm license --status` 顯示 FM1 1.0 已於 2026-10-26T14:59:00+08:00 接受；原始輸出只精確到分鐘。本次僅讀取狀態與條款，沒有執行同意操作 |
| 原生可用性 | `SystemLanguageModel.default.availability == .available` |
| 台灣繁體中文 locale | `supportsLocale(Locale(identifier: "zh-Hant-TW")) == true` |
| 執行路徑 | CLI 明確傳入 `--model system`；Swift 明確建立 `SystemLanguageModel.default` |

這些結果證明測試當下能取得可用模型，不代表所有裝置、地區、語言設定與後續系統版本都能使用。未進行封包擷取或斷網測試；本機性依官方 API 定義與明確的模型選擇確認，不能宣稱已做網路稽核。

## 官方介面、授權與限制

Apple 的 [Foundation Models 入口](https://developer.apple.com/foundation-models-framework/) 現在同時介紹本機、PCC 與第三方模型；因此僅「用了 Foundation Models」不足以保證離線。本專案限定 [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)，不建立 PCC model、第三方 provider、工具呼叫或 CLI server。

[官方 Python SDK](https://github.com/apple/python-apple-fm-sdk) 與[安裝文件](https://apple.github.io/python-apple-fm-sdk/getting_started.html) 已確認存在，套件名稱為 `apple-fm-sdk`，模組名稱為 `apple_fm_sdk`，需求為 macOS 26+、Xcode 26+、Python 3.10+ 及可使用 Apple Intelligence 的 Mac；SDK 採 Apache-2.0。適合離線評估，不必成為輸入法執行階段依賴。本次沒有安裝 Python SDK，使用標準 Python 啟動 CLI 做研究，再以原生 Swift 驗證正式介面。

CLI 的 `fm license --show` 要求遵循 macOS 軟體授權，且程式化存取須屬於明確允許範圍；框架另有 [Apple 可接受使用要求](https://developer.apple.com/support/terms/acceptable-use-requirements-for-the-foundation-models-framework/)。本專案只呼叫公開 SDK 與官方 CLI，不重新散布模型權重、不規避 guardrails、不自行接受條款。開源的專案程式碼不會改變 Apple 模型本身的授權條件。

[語言與 locale 官方文件](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models) 要求檢查支援狀態並處理不支援錯誤。原生 adapter 每次檢查模型與 zh-Hant-TW，可用性或語言檢查失敗即拋出可回退錯誤。SDK 型別與方法另外對照本機 Xcode 27.1 的公開 `.swiftinterface`，並實際編譯與執行。

## 小型人工 Benchmark

資料：`research/apple-fm/fixtures.json`，20 筆人工編寫，五類各 4 筆：一般中文、同音字、中英混合、工程術語、保留原文。沒有私人輸入資料，也沒有訓練或調整模型。

結果：`research/apple-fm/results.json`，執行時間 2026-10-26T16:13:27.491702+08:00。

| 指標 | 實測 |
|---|---:|
| 測試筆數 | 20 |
| Candidate Recall | 100%（資料建構時即放入正確答案，非引擎召回率） |
| 人工候選首位基準 Top-1 | 75%（15/20） |
| AI 有效輸出／失敗回退後 Top-1 | 75%（15/20） |
| 原本首位正確案例的有害重排率 | 33.3%（5/15） |
| 無效輸出率 | 0% |
| 10 秒研究逾時率 | 0% |
| 超過 150 ms 比率 | 100% |
| CLI P50／P95／P99 | 628.676／684.988／1846.947 ms |
| 第一筆全流程延遲 | 1846.947 ms |
| CLI process 最大 RSS | 15,384,576 bytes |

這是小型探索，不是 500 筆驗收資料，也不是實際 McBopomofo 引擎的候選集合或基準。部分答案反映台灣用詞偏好（如「訊號」）；人工標註仍須審閱，不能將所有差異都當成客觀錯字。沒有獨立保留測試集、沒有隔離背景負載、也未重複多輪。P99 採 nearest-rank，因此小樣本中等於最慢一筆。

「Cold Start」尚未量測：第一筆是程序第一筆，不保證系統模型未被預熱。RSS 只有 CLI 程序，**不包括系統模型服務與 GPU／統一記憶體**，不能據此宣稱模型只使用約 15 MB。模型總記憶體需另以 Instruments 等工具量測。

明確的不良重排包括 `qz_module7 → qzModule7`、`PySide6 → PySide`、`foo.bar → foobar`，均為選到候選清單中另一個 ID，說明限制輸出 ID 只能防止任意生成，不能保證選字正確。`JSON 檔案` 也被選為 `JSON 擋案`。

原生 Swift 的三筆 smoke test 儲存於 `native-results.json`：編譯選字 2372.362 ms、部署選字 733.406 ms、保留自訂變數 677.123 ms；前兩筆正確，第三筆仍把 `qz_module7` 改選為 `qzModule7`。因此延遲不只是 CLI 啟動成本。原生測試不是與 CLI 相同的完整統計，不能直接比較兩者 P95。

## 非同步介面與安全條件

`Packages/CandidateRanking` 是獨立 Swift package，基礎介面最低 macOS 13，Apple adapter 加上 macOS 26 availability guard。實際建置工具為 Xcode 27.1；尚未在其他 Xcode／macOS 組合驗證。

- `CandidateRankingRequest`：不可變版本、最小上下文、候選 ID 與文字。最多 32 候選，上下文最多 1024 UTF-8 bytes，每候選最多 256 bytes，空或重複 ID 請求直接拒絕。
- `CandidateRankingResult`：只包含版本與 selected ID；僅能把原始清單中的一個 ID 移到首位，其他候選順序、文字不變。
- `CandidateReranker`、`TraditionalReranker`、`AppleFoundationModelsReranker`：可替換介面與傳統 fallback。Apple adapter 建立獨立 session，不保留對話歷史，structured generation 最多 64 回應 tokens。
- `RankingCoordinator`：預設停用。`submit` 同步回傳傳統候選，推論在 detached utility task 執行，UI callback 在 MainActor 執行；預設 150 ms deadline，錯誤或逾時不更新。
- 每次送件先使舊請求失效，並使用獨立 UUID 避免同版本舊請求被誤套用。回覆必須通過 UUID、deadline、版本、候選 ID 與外部 `isStillCurrent` 檢查。
- 同一 coordinator 同時最多一筆真正進行中的推論。逾時會取消並使結果失效；若模型不合作取消，該 slot 保持占用直到其實際返回，後續請求保留傳統結果，不排隊、不堆積推論。
- 不以 task group 競速實作 timeout，避免結束 group 時被不合作取消的子 task 拖住。取消是最佳努力，不能保證 Apple 服務立即停止使用硬體資源。

本模組沒有取得周邊應用程式文字、全域監聽、讀取剪貼簿、寫入日誌或提交文字的能力。未將它加入 Xcode app 的相依套件，也未加入 AI 開關介面。

整合前必須由 `KeyHandler`／輸入狀態與 controller 遵守既有分工：編輯、游標移動、選字、提交、模式／應用程式切換、停用輸入法與 Secure Input 都要 invalidate；`isStillCurrent` 再比對尚未提交狀態、完整候選身分與使用者是否已操作選單。上下文限合法取得的未提交組字，不能從整個文件或輸入歷史擷取。已提交文字完全不在此 API 可修改範圍。候選視窗整合與以上生命週期驗證尚未完成。

## 可重現指令與測試

從專案根目錄執行：

```sh
fm license --status
fm available
swift test --package-path Packages/CandidateRanking
python3 research/apple-fm/benchmark.py --output /tmp/ai-bopomofo-fm-results.json
swift run --package-path research/apple-fm/NativeProbe NativeProbe
```

Benchmark 只接受已同意條款的狀態，不會自動同意；超時會終止本次 CLI 的程序群組，避免孤兒推論程序。CLI 結果可因系統模型更新與硬體負載不同而改變。

Swift Testing：11 個測試通過，0 失敗；涵蓋既有候選提升、錯誤版本／ID、非法請求、傳統回退、預設停用、目前狀態檢查、取消、停用、錯誤／不可用、timeout、非合作取消、重複請求。測試中的模型為 deterministic stub，不依賴 Apple Intelligence。另有 3 筆真實 native probe 與 20 筆 CLI 實驗，結果與單元測試分開記錄。

## 下一步

保留預設停用的原型，不將結果宣稱為日用 AI 功能。待傳統混打穩定後，擴增並審閱至少 500 筆人工／公開資料，接上實際引擎候選，明確處理術語／未知詞保護、使用者已選候選、觸發頻率及跨 controller 全域推論上限，再評估手動觸發或專用小模型。要達成 Phase 4 仍缺代表性品質提升、產品生命週期整合、模型總記憶體與完整延遲量測。
