# 詞彙學習驗證紀錄

## Phase 0 基準

以 `main` 的 `e32d0c23` 建立 `feature/lexicon-learning-v1`，引入工程詞庫實作 `99f86f6c`（本分支提交 `c4347afc`）。原功能分支保留，未合併 main。

實作前 `scripts/test-headless.sh`：249 項通過、2 項跳過。兩個跳過案例為 ParselessLM sanity 與 ParselessPhraseDB stress。原 DerivedData 的 PCH 與模組映射不一致導致整合編譯失敗；獨立 `/tmp/aibopomofo-learning-baseline-deriveddata` 的 Debug build-for-testing 與 Release build 通過。原始輸出保留 `/tmp/aibopomofo-learning-baseline*.log`，這些暫存紀錄不是永久交付附件。

候選選取不一定送出文字；一般注音選取僅修改 reading grid。部分提交流程在建立 Committing 前清除 grid，不能在 insertText 後反查讀音。必須將可靠詞彙快照附在不可變組字狀態，並只對實際送出的對應範圍計數。無法證明對應的路徑略過。

本輪基準未測 GUI、實鍵、實際 FM、輸入事件 P95 或長時間跨應用穩定性。模組通過不代表這些項目已驗收。
