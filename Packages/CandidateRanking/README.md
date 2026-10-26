# CandidateRanking

AI-Bopomofo 的獨立排序研究模組，預設停用，尚未整合輸入法 UI。只提升既有候選，不生成或提交文字。

```sh
swift test --package-path Packages/CandidateRanking
```

`RankingCoordinator.submit` 立即傳回傳統順序，選擇性稍後回呼更新候選。呼叫端必須在組字、候選或焦點狀態變動時呼叫 `invalidate()`，並在 `isStillCurrent` 內重新驗證未提交狀態與完整候選身分。未經品質與生命週期驗證，請勿接上正式輸入法。

詳見 [`docs/research/apple-fm.md`](../../docs/research/apple-fm.md)，包括實測不良重排、非合作取消的資源限制，以及尚未完成的產品驗收。

## 0.5.0 手動糾錯與英文預測

同一套件新增獨立的 `CorrectionProvider`、`CorrectionRequest`、`AssistanceCoordinator` 與 `AppleTextAssistance`；app 現在連結套件並使用這套新介面。上面的舊 `RankingCoordinator` 仍是未啟用的排序研究原型，沒有改成自動重新排列中文候選。

新介面可以產生糾錯字串或英文續字，但所有外部結果都必須先經 `CorrectionRequest.validated`。UI 保留原文第一，只有使用者明確選取／接受後才使用建議。`SystemSpelling` 使用背景 API 與獨立限流，作為英文回退。實際行為、限制與人工驗收見 `docs/text-assistance.md`，測試資料見 `research/text-assistance/`。
