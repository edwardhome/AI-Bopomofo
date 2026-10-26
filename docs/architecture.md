# 專案架構

保留 McBopomofo 的 IMK controller → KeyHandler Objective-C++ bridge → Mandarin/ReadingGrid C++引擎。中文組字與候選仍使用上游詞庫、覆寫模型及狀態機，未以AI取代。

英文明確入口透過 KeyHandler 進入不可變 InputState.ASCII（Inputting子類），由 MixedInputCore 計算可列印ASCII／度數符號、游標、原文與候選選擇。MixedInputHandler只轉接事件及回報新狀態，UI顯示與提交仍由原controller處理。

自訂英文詞使用 LanguageModelManager 的既有 data.txt。AppDelegate在詞庫重載時建立 bounded記憶體快取，按鍵不讀取磁碟、不呼叫模型或子程序。

CandidateRanking為獨立研究package，未連結至app。其結果只能重新排列原有ID，不能產生提交文字。未來整合必須先完成生命週期與品質驗收。

產品識別／預設資料目錄分離，內部target/module保留McBopomofo名稱以利上游同步。原始資料格式標頭、著作權與上游README不修改。

更新時間：2026-10-26T16:50:00+08:00
