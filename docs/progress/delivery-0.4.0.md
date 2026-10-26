# AI注音輸入法 0.4.0 交付

本次在 feature/ai-name-symbol-layer 分支完成：統一產品顯示名稱、獨立 F 數字／符號層、Markdown 半形預設與直接反引號、簡化主選單、修正 asdfghjkl 下拉選取的儲存時序。原有詞庫與功能保留，詳細操作與限制見 [F 分層說明](../quick-symbols.md)。

F 分層不依賴 Kanata；44 個鍵位來源為使用者提供的配置。只在輸入法內運作，短按回放注音、約 200 毫秒長按進入、放開退出。未完成音節與英文組字期間不攔截 F，跨應用的按鍵放開事件仍須人工驗收。原始 ji3 顯示與 Vim 專用英文介面暫緩。

檢查結果：C++ 122 通過、2 上游案例跳過；MixedInputCore 15 項通過；CandidateRanking 11 項通過；Python 14 項通過；詞庫檢查成功。Debug build-for-testing 與 arm64/x86_64 Release 建置成功。新增 4 項 IMK／KeyHandler 整合案例僅編譯，沒有執行 hosted／GUI 測試或音效。獨立識別碼、兩種輸入模式、名稱、詞庫資源與簽章驗證通過。

本機候選產物為 dist/0.4.0-alpha/；app 使用 ad-hoc 簽章、pkg 未簽署且未公證。沒有建立公開遠端、推送或正式發行 tag。Apple FM 仍為研究模組，不參與輸入；不需要 Ollama。

使用者已在本對話授權本機安裝與重啟。舊版 0.3.1 與偏好設定已備份於忽略追蹤的 artifacts/install-0.4.0/，保留現有使用者詞庫。系統安裝完成，已驗證版本 0.4.0／build 400，77 個已安裝檔案與候選包逐一一致，簽章驗證成功。新版程序已啟動，TIS 啟用／選取回傳 0，當下輸入來源確認為 AI注音輸入法。

Kanata 設定未修改，SHA-256 為 f60746ca8dfb10316e213d98ef6925df2963f14b03a11030f54ec6d592320455。先前應使用者要求停止 Kanata；本次不恢復它，以便驗證獨立分層。

本機套用設定：長按 F 開啟、半形標點開啟、反引號標點清單關閉、選字鍵 asdfghjkl、錯誤提示音關閉。Kanata 程序與系統服務均未執行；沒有修改 Kanata 設定。沒有執行真實按鍵測試，需由使用者確認長按／放開 F 與各應用的輸入結果。

系統實際的輸入來源 ID 為 org.aibopomofo.inputmethod.AIBopomofo.AIBopomofo.Bopomofo，輸入模式 ID 為 org.aibopomofo.inputmethod.AIBopomofo.Bopomofo；兩者用途不同。依實際列舉結果啟用及選取，沒有更改產品識別碼。

來源 Commit：1fc9303。pkg SHA-256：35d5b061569880eaa8ccaec548656a3e275e1455873025feb200caeb76a23dde；zip SHA-256：e5790bb5cb08b55043d24a51ca15914d7322edbf798759df04d9158b3362e85b。包裝工具曾輸出 write: Permission denied 提示，但正常完成；後續解包與已安裝檔案各 77 檔比對、簽章驗證均通過。

若需回復，先切換其他輸入來源，再停止本專案程序，由管理員將 artifacts/install-0.4.0/AI-Bopomofo-0.3.1.app 還原到 /Library/Input Methods/AI-Bopomofo.app；偏好設定備份為同目錄的 preferences-before.plist。不要還原或覆寫使用者詞庫。本次尚未執行回復。

驗證時間：2026-10-26T17:40:50+08:00
