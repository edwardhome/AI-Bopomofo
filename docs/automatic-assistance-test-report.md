# 0.6.14-dev.1 自動建議驗證

基礎為 main `e10bafcb`，獨立開發分支 `feature/automatic-composition-assistance`。本輪新增停頓後自動建議與技術排版驗證；未改 FHoldGesture、FReleaseMonitor、原始詞庫或 SQLite 觀察範圍。控制器新增自動提示恢復原文的事件分派。

## 自動化與編譯

| 檢查 | 結果 |
| --- | --- |
| C++ 引擎 | 124 通過、2 個既有案例跳過 |
| MixedInputCore | 72 通過 |
| CandidateRanking | 40 通過，新增 6 項自動建議規則測試 |
| LexiconLearning | 24 通過 |
| Python 語料與 Schema | 28 通過 |
| 合計 | **288 通過、2 跳過** |
| Debug hosted IME 整合測試 | 只編譯成功，沒有執行 |
| Release | 編譯成功，主程式與 XPC 服務均有 arm64／x86_64 |
| Bundle | 產品識別、工程詞庫 103 詞、內嵌模型服務、簽章及無私人資料庫檢查通過 |

新增測試涵蓋完整組字／游標末尾／既有候選優先、同內容不重試及節流、普通鍵不選字、Enter 原文、Tab 明確選取、Esc、數值及公式身分、希臘字母、私人保護詞與中文等長換字。既有 coordinator 測試仍覆蓋延後回覆、取消、逾時、無回應供應器與輸入改變。

新增三項 hosted 整合案例（普通字元／F／退格、明確選取、Esc 原狀還原）只編譯，不列入上面通過數。實際控制器、事件監聽與跨應用相容性仍須人工驗收。

初次新增單元測試因 Testing 巨集對 mutating 呼叫的展開方式編譯失敗，改為先執行再斷言。公式測試指出上標 ² 的字元範圍及 Unicode 減號正規化缺口，修正後通過；沒有刪除該測試。整合編譯另遇沿用舊目錄的 PCH/modulemap 時戳失效，僅清除本次 `/tmp` 建置目錄內的 PrecompiledHeaders 後重新通過，未修改已安裝輸入法。

## 真實 FM 探測

使用四個公開合成案例，沒有私人文件、輸入紀錄或真實密碼。直接模型及 XPC 探測均為獨立 CLI；後者在臨時測試 bundle 內啟動同一個 ModelService.xpc，沒有啟動 IME、操作 GUI、模擬打字或播放音效。

| 案例 | 預期 | 直接模型 | XPC，同時編譯 | XPC，建置完成後 |
| --- | --- | --- | --- | --- |
| 我在去一次 | 我再去一次 | 符合，2.04 秒 | 符合，3.14 秒 | 符合，3.06 秒 |
| 我再德國 | 我在德國 | 符合，2.95 秒 | 符合，2.02 秒 | 符合，0.86 秒 |
| al2o3 | Al₂O₃ | 符合，1.12 秒 | 逾時、無建議，5.21 秒 | 符合，0.90 秒 |
| 我跑得快 | 不提出改字 | 符合，1.26 秒 | 逾時、無建議，5.32 秒 | 符合，0.86 秒 |

直接模型 4/4、建置完成後 XPC 4/4 符合這四例預期；同時編譯時 XPC 只有 2/4 正常完成，兩個逾時不能算成模型正確判斷。負載與模型時間可能相關，但本輪未控制其他變因，不能據此斷言唯一原因。

時間為 coordinator 請求時間，**不包含停頓等待、IMK 與候選渲染**。四例是針對性煙霧測試，不代表一般校正準確率或效能分位數。模型無建議或逾時時原文保持不變；本輪未延長五秒預算以掩蓋逾時。

原始合成結果：

- `research/text-assistance/automatic-direct-results-0.6.14.json`
- `research/text-assistance/automatic-xpc-loaded-results-0.6.14.json`
- `research/text-assistance/automatic-xpc-results-0.6.14.json`

## 重現

```sh
export AI_BOPOMOFO_PACKAGE_CACHE="$PWD/build/DerivedData/SourcePackages"
export AI_BOPOMOFO_SCHEMA_PYTHON="$PWD/build/lexicon-schema-env/bin/python"
AI_BOPOMOFO_DERIVED_DATA=/tmp/aibopomofo-learning-debug scripts/test-headless.sh
AI_BOPOMOFO_DERIVED_DATA=/tmp/aibopomofo-auto-release scripts/build.sh Release
```

以下會明確執行本機模型；不是一般 headless 腳本的一部分：

```sh
swift run -c release --package-path research/text-assistance/Probe Probe \
  research/text-assistance/automatic-4.json /tmp/automatic-direct.json
python3 research/text-assistance/run-xpc-probe.py \
  /tmp/aibopomofo-auto-release/Build/Products/Release/AI-Bopomofo.app \
  /tmp/automatic-xpc.json
```

## 未驗證與交付邊界

- 未在使用者已安裝的 IME 上驗證自動候選位置、焦點、鍵盤交互、Secure Input、F 與 Shift 實鍵或長時間打字。操作清單見 automatic-assistance.md。
- 沒有測量完整按鍵 P95、模型長時間記憶體消耗或跨應用穩定性。這些不能由單元測試或 CLI 模型探測替代。
- 提示預設原文，普通鍵仍輸入原文；模型可能慢、無建議或判斷錯誤。技術公式的字面身分相同不代表學術語意已被查證。
- 已送出文字記憶只寫了提案，沒有新增保存、文件擷取或上下文外傳。
- 不安裝、不重啟、不合併 main、不建立標籤或 GitHub Release。套件與遠端交付結果如下。

## 開發交付

- 安裝包來源提交：`e72cfc9e`。後續提交只補充交付紀錄。
- `scripts/verify-package.sh` 通過，pkg 解開後 86 檔與保存 app 一致；ZIP 另行解開核對 86 檔並通過嚴格簽章驗證。
- 打包過程仍出現 `write: Permission denied` 診斷，工具最終成功，兩種封裝均未發現內容缺漏；原始紀錄保留於忽略版控的 `artifacts/automatic-assistance/package.log`。
- 僅將 pkg 與 app ZIP 複製到 `/Users/defu/Documents/AI Bopomofo/0.6.14-dev.1/`，來源與目的 SHA-256 相同。iCloud 雲端與 MacBook Air 同步狀態未驗證。
- 已推送 `edwardhome/AI-Bopomofo` 的 `feature/automatic-composition-assistance`，沒有合併 main 或建立 Release。

| 附件 | SHA-256 |
| --- | --- |
| AI-Bopomofo-0.6.14-dev.1.pkg | 41148dbd3855fdae95b458f988c6b9270b30479005189953fc86921b21daba7b |
| AI-Bopomofo-0.6.14-dev.1.zip | 5ea644a999df105ae79a6188ab35d6a2300ea76d29d4e4747270e81636199665 |

更新時間：2026-11-05T00:05:01+08:00
