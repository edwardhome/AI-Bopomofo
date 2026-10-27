# 0.6.7 F 等待時間可調整

更新時間：2026-10-27T23:15:40+08:00

使用者回報 MacBook Air 上 100 毫秒太短，要求保留自行調整時間，並明確要求注音模式短按 F 應為「ㄑ」，不可送出字母 f。

新增偏好 FHoldDelayMilliseconds，初始 100、上下限 100～1000。既有偏好視窗的進階頁提供每格 50 毫秒的選擇。每次 idle → pending 時建立使用設定門檻的手勢物件，進行中的按住不受後續設定變動影響。原有 replayTap 路徑在非直接英文模式呼叫 KeyHandler；沒有新增以 f 取代注音的回退，也未變更鍵位、雙 Shift 或輸入監控範圍。

無介面測試 202 項通過、2 項上游案例跳過：C++ 122／2 跳過、MixedInputCore 34、CandidateRanking 28、Python 14＋4。新增測試涵蓋延長門檻時放開、接續注音鍵、不同門檻進入／退出及異常值邊界。偏好保存與 F 還原為「ㄑ」的兩個 IMK／KeyHandler 案例僅 build-for-testing 編譯，未執行 hosted 測試。

Debug 遇既有 PrecompiledHeaders 與 modulemap 過期問題，只清除該建置快取後重建成功；Release 通用建置成功。紀錄 artifacts/f-delay-headless.log、artifacts/f-delay-debug-retry.log、artifacts/f-delay-release.log。尚未實機重現使用者提及的字母 f，因此不宣稱另有已確認的模式錯誤修復。

本機候選包 dist/0.6.7-dev.1 已完成；pkg 解包後 77 個檔案與 app 一致，簽章、識別、安裝位置與 SHA-256 核對通過，包含 arm64／x86_64。另存 iCloud 文件 AI_Bopomofo-0.6.7，供 MacBook Air 安裝。原 0.6.6 發行版保留。Mac mini 已安裝並重啟 0.6.7，77 個檔案與套件一致，偏好與詞庫未變；輸入監控的舊簽章更新仍待系統驗證完成。使用者另行授權發布 0.6.7 至 GitHub，準備 release/0.6.7 分支與 v0.6.7 標籤。

ebbebd3ecd411cd5cb3718ae473f1f88c69656b1faa9f83093921399765b956f  ./AI-Bopomofo-0.6.7-dev.1.pkg
b6b890cd1307e030e14c0e50d9f2319640e0dd81a0371b567b2bafb917d72dc9  ./AI-Bopomofo-0.6.7-dev.1.zip

套件來源 commit：c557930。

發布準備更新時間：2026-10-27T23:31:08+08:00。標籤對應套件原始來源 c557930，後續僅補充發布文件。

發布完成時間：2026-10-27T23:35:52+08:00。公開開發測試版：[v0.6.7](https://github.com/edwardhome/AI-Bopomofo/releases/tag/v0.6.7)。六個附件已從公開下載連結取回，逐一核對 SHA-256 與發布檔案一致；保留 v0.6.6。預設分支已更新為 release/0.6.7，首頁顯示新版本與 F 等待時間說明。核對時間：2026-10-27T23:37:47+08:00。套件與標籤來源仍為 c557930，後續 commit 僅更新文件。
