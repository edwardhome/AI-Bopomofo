# 架構研究

`Source/InputMethodController.swift` 接收 IMK 事件，交給 `KeyHandlerInput` 與 `KeyHandler.mm`。`InputState.swift` 不可變狀態控制 marked text、提交與候選視窗。`LanguageModelManager.mm` 管理 C++ 語言模型及使用者詞庫。

`Source/Engine/Mandarin` 將鍵序列組為注音音節；`gramambular2` ReadingGrid 按語言模型分數尋找組詞路徑。`UserOverrideModel` 學習手動選字。候選保有 reading/value 對應，AI 僅可對既有 ID 提出建議。

`KeyHandler.mm` 的數字鍵盤處理早於一般注音；候選選擇優先權受 selectCandidateWithNumericKeypad 影響。標準注音頂排數字本來是聲母、韻母與聲調鍵，不能全面改成數字。

Shift 標點查 `_punctuation_`（或使用者啟用的 `_half_punctuation_`）及鍵盤配置特定映射。新 ASCII 組字應採明確意圖入口，不能改寫一般 Shift 標點。

更新時間：2026-10-26T16:13:42+08:00
