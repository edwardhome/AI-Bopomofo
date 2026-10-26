# 0.6.6 公開發布進度

更新時間：2026-10-27T01:34:50+08:00

公開儲存庫：https://github.com/edwardhome/AI-Bopomofo

預設分支 `release/0.6.6` 已上傳，完整保留上游歷史。`v0.6.6` 標籤及套件來源為 `8e957581269097f0ef1eed1e3df598e20081fe14`；之後分支只補文件，沒有重寫標籤。

GitHub 已確認首頁使用 README.md，包含特色、MIT 歸屬與專業詞匯入。原上游 README 原文移至 docs/README-upstream.markdown，保留 Git 歷史。當前安裝包尚未上傳，公開 Release 數量為零，不宣稱下載發布完成。

本機公開測試套件位於 dist/0.6.6-dev.1。77 個 app 檔案與已實機驗收的 0.6.6-alpha 完全相同；pkg 解包驗證、固定安裝位置及 SHA-256 核對通過。另附 25 個通過實際 TechnicalLexicon.isValid 驗證的公開技術詞範例。未重跑只有文件變更所不需要的全套測試；原程式驗證結果為 198 通過、2 跳過。

- pkg SHA-256：32fe71b107c719d27b52ae8036efd43a216c9b7a92febdc44ad3371130d199ff
- zip SHA-256：8eefd88055bc791ce89acd2bdbe4f830395e0ca93d02e6fab0d9b619ccdcdfa2

後續：將安裝包、校驗檔、詞彙範例、安裝說明與來源 commit 附至 v0.6.6 的 Pre-release；確認可公開下載並核對雜湊後，移除 README 的待上傳提示。安裝包不含個人偏好、詞庫或診斷資料。
