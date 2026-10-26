# Phase 0 報告

目標：取得上游、確認授權、環境與輸入路徑。

已完成：固定上游 SHA e65f2763d03ea381c0f40fa132df32412e8b33b9，讀取根目錄及 Source/Data 的 AGENTS.md、README、LICENSE、ACKNOWLEDGEMENTS。建立 main/develop 基準及 feature/research 隔離分支；封鎖 upstream push。唯讀分析 Kanata keypad 與 Unicode 兩種輸出。

變更：docs/research/{upstream,architecture,build,license,mixed-input}.md、AGENTS.md；FM 文件由 research/apple-fm 分支提供。

實作 Commit：2ad2c480cac3514d09218df4851120e532185eaf。

環境／測試指令見 docs/research/build.md；環境檢查成功，沒有變更 Xcode 授權或安裝系統依賴。研究階段不虛列功能測試數。

限制：Zing 僅參考公開說明；Kanata 真實 Unicode 事件路徑尚未實機驗證；尚未建立遠端公開倉庫。

下一步：先保存獨立可安裝 bundle，再加入混合輸入。

更新時間：2026-10-26T16:20:00+08:00
