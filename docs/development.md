# 開發與重現

本次使用macOS27.0.1、Xcode27.1、Swift6.4、arm64。app部署目標為macOS13；尚未在舊版系統或Intel執行驗證。外部依賴固定於工程內的Package.resolved：SQLite.swift0.17.0、SwiftyOpenCC2.0.0-beta，與上游AGENTS中的舊版本描述不同。

建置：`scripts/build.sh Debug`或`scripts/build.sh Release`，只用ad-hoc簽章，不執行app。

純邏輯驗證：`scripts/test-headless.sh`。此腳本執行C++、純Swift與Python測試、詞庫檢查，再編譯hosted tests但不啟動輸入法，不呼叫FM或安裝任何軟體。整合腳本已提供，個別步驟有實測紀錄；新GitHub Actions尚未遠端執行。

效能：`swift run --package-path Packages/MixedInputCore -c release MixedInputBenchmark`。模型研究為獨立明確操作，見docs/ai-reranker.md，不能放入一般鍵盤事件。

打包前先完成一般build，避免攜帶hosted test產物；執行`scripts/package.sh 0.3.0-alpha Release`及`scripts/verify-package.sh dist/0.3.0-alpha`。既有版本資料夾存在時拒絕覆寫，改用新的本地候選版本並同步Info.plist。使用者安裝需另外執行安裝腳本或開啟pkg。

目前以feature/technical-terms作整合分支，main/develop保留上游基準。所有變更先測試、Conventional Commit、本地保存。upstream push URL已停用；不要自行建立或推送遠端。

使用者已回報突發聲音，後續預設不執行會啟動app的xcodebuild test；雖已加上測試靜音保護，仍須另行確認後才恢復GUI／hosted測試。

更新時間：2026-10-26T16:50:00+08:00
