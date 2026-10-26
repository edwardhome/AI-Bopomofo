# CandidateRanking

AI-Bopomofo 的獨立排序研究模組，預設停用，尚未整合輸入法 UI。只提升既有候選，不生成或提交文字。

```sh
swift test --package-path Packages/CandidateRanking
```

`RankingCoordinator.submit` 立即傳回傳統順序，選擇性稍後回呼更新候選。呼叫端必須在組字、候選或焦點狀態變動時呼叫 `invalidate()`，並在 `isStillCurrent` 內重新驗證未提交狀態與完整候選身分。未經品質與生命週期驗證，請勿接上正式輸入法。

詳見 [`docs/research/apple-fm.md`](../../docs/research/apple-fm.md)，包括實測不良重排、非合作取消的資源限制，以及尚未完成的產品驗收。
