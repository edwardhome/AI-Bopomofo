# Phase 1 報告

目標：保留上游功能並建立可並存的獨立輸入法。

已完成：AI-Bopomofo.app、獨立 Bundle/模式 ID、AIBopomofo_1_Connection、獨立預設詞庫目錄、停用上游更新端點、本地安裝／備份解除安裝腳本、pkg/zip 與 SHA-256 校驗。

實作 Commit：2ad2c480cac3514d09218df4851120e532185eaf。主要變更：Xcode 專案、Info.plist、各語系 InfoPlist.strings、Preferences、main、KeyHandler 模式常數、AppDelegate、Installer 目標路徑、Data 舊部署指令封鎖、scripts。

建置：`scripts/build.sh Debug`，Xcode 27.1／macOS 27.0.1／arm64，成功。

測試：`xcodebuild -project McBopomofo.xcodeproj -scheme McBopomofo -configuration Debug -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test`。

- C++ ctest：124 項中 122 通過、2 跳過、0 失敗。上游 SanityCheckTest 與 StressTest 自行跳過。
- XCTest：130 通過、0 失敗。
- Swift Testing：87 通過、0 失敗（包含參數化案例，與 XCTest 分開計數）。
- bundle 結構、詞庫、獨立識別碼、簽章檢查通過。
- pkg 解包後同一組 bundle 檢查通過，PackageInfo 安裝位置為 /Library/Input Methods，禁止 relocation。

第一次 Swift 測試發現停用更新端點後 callback 未回呼，造成 continuation 等待；修正無端點時回報 ignored，完整重跑通過。沒有刪除或跳過該測試。打包時工具輸出四次 write: Permission denied，但退出碼為 0；已解包檢查全部必要資源與簽章成功，並保留原始日誌供追蹤。

套件：`dist/0.1.0-alpha/AI-Bopomofo-0.1.0-alpha.pkg`、同目錄 zip/app、checksums.txt、安裝／版本說明。日誌位於 artifacts/phase1-*，不納入 Git。

可用狀態：可建置、可打包的本地候選版；尚未安裝或執行 GUI 驗收。不能宣稱 TextEdit／瀏覽器等實際輸入已通過。尚無 AI／新混打功能，未簽 Developer ID、未公證，故暫不建立正式版本 tag。

下一階段：數字、ASCII 明確組字入口、取消／刪除與 Shift 標點回歸。

更新時間：2026-10-26T16:20:00+08:00
