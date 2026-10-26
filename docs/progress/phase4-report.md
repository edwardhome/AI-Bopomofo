# Phase 4 報告：研究完成，產品整合未達驗收

研究分支：research/apple-fm；主線匯入 Commit 717c745、277ad9b，原研究 Commit a353824、b4f2470。

已完成：fm／官方 Swift API／Python SDK 研究、原生 3 筆推論、20 筆初測、500 筆五類語料及完整評估、ID/版本驗證、非同步協調器、timeout／取消／預設停用／單一推論限制。所有模型使用 system 本機路徑，無 Ollama 或雲端依賴，沒有自動接受條款。

測試：`swift test --package-path Packages/CandidateRanking` 11 項通過；`python3 -m unittest discover -s research/apple-fm -p test_corpus.py` 14 項通過；0 失敗。資料與真實推論結果保存在 research/apple-fm；詳見 docs/research/apple-fm.md 與 apple-fm-corpus.md。

500 筆來自 100 組合成詞對×5模板，不是500筆獨立自然語料。人工輪換候選基準 52%，模型／回退後 91%；原本正確的 260 筆有37筆被改錯（14.23%），中英混合類有害重排40%。無效輸出2/500、10秒逾時0、P95 682.348ms，全部超過150ms。

結論：不符合安全日常自動排序要求。保留原型與實驗資料，未接入 app、沒有 AI 開關或 v0.4.0-alpha 套件。Candidate Recall 100% 是資料構造保證，不是引擎實測；cold start、模型總記憶體、真實候選對照、Secure Input／組字生命週期整合仍未完成。

下一步：代表性語料審閱與真正引擎候選基準；評估手動觸發或專用小模型。不得用這份合成語料改善率宣稱產品已優於上游。

更新時間：2026-10-26T16:50:00+08:00
