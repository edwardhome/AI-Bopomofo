# Phase 2 報告

目標：明確、可取消的 ASCII 組字，保留原版 Shift 標點。

實作 Commit：311644f。變更：Source/MixedInput.swift、KeyHandler、InputState、輸入法選單、語系字串、Xcode 工程、MixedInputTests。

已完成：英文／ASCII 功能入口、數字與所有可列印 ASCII、游標編輯、256 字元上限、Enter 提交、Esc 取消、快捷鍵交還應用、未完成音節保護。上游 keypad 與標點邏輯保留。

測試指令同 Phase 1。XCTest 130 通過、Swift Testing 97 通過（含新增 10 項測試，literal 測試另外涵蓋 12 組參數），0 失敗。已測中文→英文→中文、數字鍵盤、Shift 標點、刪除及快速輸入。沒有重新跑未修改的 C++。

使用者回報突然發聲後，停止所有會啟動輸入法的測試。加入測試專用 InputFeedback 靜音保護與 scheme 環境變數後，只重新編譯成功，未重新啟動 hosted tests。已找到上游 NSSound.beep 呼叫，但不能證實是該次聲音來源。未調整系統音量、未播放媒體。

套件：dist/0.2.0-alpha/，保留 0.1.0-alpha 不覆寫。已產生 pkg/zip/app/checksums。仍是未經公證本地候選版。

限制：不把普通頂排數字全部變為數字，因為它們屬於注音鍵位；目前須明確進入 ASCII。Kanata keypad 在引擎層測試通過，真實 Unicode／跨應用路徑未驗證。GUI 測試尚未執行，因此不建立正式 tag，也不宣稱完整 Phase 2 現場驗收通過。

下一步：技術詞庫候選與明確 Shift 字母意圖；使用不啟動 app、不播放聲音的純邏輯測試。
