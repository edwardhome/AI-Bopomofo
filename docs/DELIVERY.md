# AI注音輸入法 0.5.0 候選版交付

在 feature/apple-ai-correction 分支新增 Apple 本機文字協助：手動中英文錯字檢查，以及英文組字上下文預測。預測使用候選視窗提示，Tab 接受、Esc 隱藏，接受後仍留在組字。原文固定保留，不自動改寫文件；只使用尚未送出的文字。

操作與跨應用驗收清單見 [文字協助](text-assistance.md)，完整結果見 [評估報告](research/text-assistance.md)。保留原有 Shift 英文、F 分層、Markdown 半形符號與詞庫功能，無需 Ollama。

200 筆合成糾錯評估中，中文首項建議符合參考 31／50，英文 50／50；50 筆受保護內容沒有修改建議，但 50 筆正確句子有 6 筆收到多餘建議。20 筆英文續字只檢查輸出格式及可用性，未評定語意品質。原文優先與明確確認仍是必要設計。

自動檢查：C++ 122 通過、2 上游案例跳過；MixedInputCore 15 項通過；CandidateRanking 28 項通過；既有 Python 14 項與新增語料 4 項通過；詞庫檢查成功。8 項新增 IMK／KeyHandler 整合案例僅編譯，沒有執行 hosted／GUI 測試、音效或操作音量。真實跨應用輸入仍待人工驗收。

新版本沒有自動安裝、沒有變更 Kanata、沒有推送遠端。目前系統的 0.4.0 安裝及備份記錄保存在 [先前交付報告](progress/delivery-0.4.0.md)。0.5.0 app 使用 ad-hoc 簽章，pkg 未簽署且未公證，僅供本機測試。

Debug build-for-testing 與 arm64／x86_64 Release 建置成功。Bundle 識別碼、輸入模式、詞庫資源與簽章驗證通過；FoundationModels 採弱連結，以保留舊系統回退路徑。舊系統實機相容性仍待驗證。
