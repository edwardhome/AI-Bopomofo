# 0.6.7 F 等待時間可調整

更新時間：2026-10-27T23:15:40+08:00

使用者回報 MacBook Air 上 100 毫秒太短，要求保留自行調整時間，並明確要求注音模式短按 F 應為「ㄑ」，不可送出字母 f。

新增偏好 FHoldDelayMilliseconds，初始 100、上下限 100～1000。既有偏好視窗的進階頁提供每格 50 毫秒的選擇。每次 idle → pending 時建立使用設定門檻的手勢物件，進行中的按住不受後續設定變動影響。原有 replayTap 路徑在非直接英文模式呼叫 KeyHandler；沒有新增以 f 取代注音的回退，也未變更鍵位、雙 Shift 或輸入監控範圍。

無介面測試 202 項通過、2 項上游案例跳過：C++ 122／2 跳過、MixedInputCore 34、CandidateRanking 28、Python 14＋4。新增測試涵蓋延長門檻時放開、接續注音鍵、不同門檻進入／退出及異常值邊界。偏好保存與 F 還原為「ㄑ」的兩個 IMK／KeyHandler 案例僅 build-for-testing 編譯，未執行 hosted 測試。

Debug 遇既有 PrecompiledHeaders 與 modulemap 過期問題，只清除該建置快取後重建成功；Release 通用建置成功。紀錄 artifacts/f-delay-headless.log、artifacts/f-delay-debug-retry.log、artifacts/f-delay-release.log。尚未實機重現使用者提及的字母 f，因此不宣稱另有已確認的模式錯誤修復。

本機候選版待包裝與核對，預計放到 iCloud 文件供 MacBook Air 安裝。沒有覆蓋已發布的 0.6.6、沒有推送本功能分支、沒有安裝或重啟目前電腦。
