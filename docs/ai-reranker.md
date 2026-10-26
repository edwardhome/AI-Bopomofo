# 本機排序研究

AI未整合至輸入法，也沒有預設啟用。可用程式介面位於Packages/CandidateRanking，完整證據見research/apple-fm及docs/research/apple-fm-corpus.md。

TraditionalReranker立即保留首位；Apple adapter限SystemLanguageModel.default。RankingCoordinator預設停用、150ms截止、每個coordinator最多一個真正執行中的推論，不排隊。取消不合作的模型可能繼續運算，但所有逾時／失效回應丟棄。

整合前必須在每次編輯、游標、手動選字、提交、模式／應用切換、停用與Secure Input失效；外層再比對版本與完整候選身分。跨controller的全域資源上限尚待實作。已提交文字永遠不屬於模型可修改範圍。

研究CLI：`python3 research/apple-fm/benchmark_corpus.py --output /tmp/ai-bopomofo-new-results.json`。只使用合成語料，不接受Apple條款、不設定PCC、雲端、Ollama或付費服務。此命令會執行500筆推論，不能當成輕量單元測試。

更新時間：2026-10-26T16:50:00+08:00
