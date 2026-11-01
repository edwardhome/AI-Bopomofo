# AI注音程式架構與相互依賴

這份導覽從「按下一個鍵」開始，連到對應原始碼與修改入口。產品名稱是 AI注音輸入法，內部 Xcode target 仍叫 McBopomofo。小麥注音原作者與 MIT 授權保留在 [LICENSE.txt](../LICENSE.txt)。

## 先看全貌

箭頭表示呼叫或使用，不表示所有程式都在同一執行緒。

```mermaid
flowchart TD
    App[AppDelegate 啟動與選單] --> Controller[InputMethodController 接收系統事件]
    Preferences[Preferences 偏好設定] --> Controller
    Controller --> Gesture[MixedInputCore F 與 Shift 手勢]
    Controller --> Bridge[KeyHandler Objective-C++ 橋接]
    Bridge --> Mixed[MixedInput.swift 英文與符號處理]
    Mixed --> Core[MixedInputCore 英文編輯與技術詞]
    Bridge --> Engine[C++ Mandarin 與 gramambular2]
    Engine --> LM[McBopomofoLM 傳統詞頻模型]
    Manager[LanguageModelManager 詞庫載入橋接] --> LM
    Data[Source/Data 與使用者詞庫] --> Manager
    Bridge --> State[InputState 不可變狀態]
    Mixed --> State
    State --> Controller
    Controller --> UI[候選視窗與游標提示]
    Controller --> Client[IMKTextInput 組字或送出文字]
    Controller --> Assistance[TextAssistance.swift 非同步文字協助]
    Assistance --> Ranking[CandidateRanking 檢查與模型協調]
    Ranking --> Apple[Apple Foundation Models 本機模型]
    Ranking --> Spell[NSSpellChecker 系統拼字]
    Assistance --> State
```

自訂英文技術詞沿用 LanguageModelManager 的使用者詞庫格式；AppDelegate 重載詞庫時建立有限大小的記憶體快取，普通按鍵不讀取磁碟或呼叫模型。產品識別與預設資料目錄和上游分開，內部 target 名稱保留以利同步。

傳統詞頻模型負責注音選字；Foundation Models 負責另外請求的文字建議。即使 Apple 模型不可用，注音、F 分層和英文組字仍可工作。

## 一個按鍵如何變成文字

```mermaid
flowchart LR
    Event[NSEvent] --> Mod[更新 Shift 放開狀態]
    Mod --> F[FHoldGesture 判斷 F 手勢]
    F --> Own[SymbolKeyOwnership 記錄分層按鍵]
    Own --> Handler[KeyHandler 分派目前狀態]
    Handler --> Next[產生新的 InputState]
    Next --> Render[InputMethodController 更新畫面]
    Render --> Mark[setMarkedText 尚未送出]
    Render --> Commit[insertText 已送出]
```

F 組合鍵必須先讓手勢進入符號層，再記錄該鍵屬於符號層，最後處理同一事件一次。若先記錄按鍵，首鍵可能還被當成普通輸入，放開 F 後的重複事件也會判錯。

主要閱讀順序：

1. [InputMethodController.swift](../Source/InputMethodController.swift)：事件入口、F 計時器、監聽生命週期與狀態呈現。
2. [KeyHandler.mm](../Source/KeyHandler.mm)：先分派英文／符號／文字協助，再進入傳統注音流程。
3. [InputState.swift](../Source/InputState.swift) 與 [MixedInput.swift](../Source/MixedInput.swift)：狀態帶著組字、游標與候選；狀態變化以新物件表示。
4. [McBopomofoLM.cpp](../Source/Engine/McBopomofoLM.cpp) 與 `Source/Engine/gramambular2/`：查詞、詞頻及組句路徑。

## F 分層與監聽生命週期

```mermaid
stateDiagram-v2
    [*] --> idle
    idle --> pending: 合格的 F 按下
    pending --> held: 映射鍵按下或達到長按門檻
    pending --> idle: F 放開／重播原始短按
    pending --> idle: 非映射鍵／重播後正常處理該鍵
    held --> idle: F 放開／結束分層
    pending --> idle: 失焦或取消
    held --> idle: 失焦或取消
```

- `pending` 時保存原 F 事件並啟動 `FReleaseMonitor`；標記文字讓 iTerm2 知道這個鍵由輸入法處理。
- `pending → held` 提前啟動只產生 `beginLayer`，不可產生 `invalidate`。F 尚未放開，監聽與健康檢查仍需要存在。
- 監聽器只在 F 手勢期間被動觀察 F key-up，其餘鍵碼立即丟棄。它不記錄打字內容，也不取代 macOS 授權。
- `SymbolKeyOwnership` 保留已處理映射鍵的歸屬，避免放開 F 後殘留的 key repeat 變成一般字母。
- 短按 F 回原注音／英文處理；F 與映射鍵實際重疊就視為組合鍵。因此快速打字須先放開 F 再按下一鍵，無法從相同事件序列推測不同意圖。

修改入口：[QuickSymbolLayer.swift](../Packages/MixedInputCore/Sources/MixedInputCore/QuickSymbolLayer.swift)、[控制器內的 FReleaseMonitor](../Source/InputMethodController.swift)、[F 操作說明](quick-symbols.md)。

## Shift 的兩種英文方式

```mermaid
stateDiagram-v2
    [*] --> Chinese
    Chinese --> Initial: Shift 加首字母
    Initial --> Word: 放開 Shift
    Initial --> Uppercase: 仍按 Shift 並按另一個新字母
    Word --> Word: 編輯或刪至空白
    Word --> Chinese: 空白或 Enter 送出／Esc 取消
    Uppercase --> Uppercase: 按字母直接送出大寫
    Uppercase --> Chinese: 放開 Shift
```

`ShiftLetterSession` 是純 Swift 決策；`InputState.ShiftASCII` 記住入口與模式。選單啟動的 `ASCII` 可輸入整句，雙擊 Shift 的直接英文模式交由應用程式接鍵，兩者都不套用上圖的單字退出規則。

F 暫存／符號狀態會包住原英文狀態。Shift 放開時必須更新內部狀態，但保留外層 F 手勢，直到 F 真正放開。所有預測與編輯都透過 `ASCII.replacing` 複製，避免遺失 Shift 啟動方式。

修改入口：[ShiftLetterSession.swift](../Packages/MixedInputCore/Sources/MixedInputCore/ShiftLetterSession.swift)、[Shift 使用說明](vim-input.md)。

## 本機文字協助與失效規則

```mermaid
flowchart TD
    Composition[目前未送出的組字] --> Request[CorrectionRequest 版本與文字快照]
    Request --> Coordinator[AssistanceCoordinator 一次一筆]
    Coordinator --> Providers[本機模型與系統拼字]
    Providers --> Validate[驗證長度、受保護文字、數字與前綴]
    Validate --> Current{版本與焦點仍有效}
    Current -->|是| Candidates[原文第一項加建議]
    Current -->|否| Discard[丟棄結果]
    Candidates --> Accept[使用者明確選取才送出]
    Edit[編輯、選取、失焦、切換模式或 Secure Input] --> Discard
```

不讀取游標前後已送出的文件，不保存私人輸入歷史。中文校正限定等量漢字替換，避免刪去「再」或擴寫。容量語境的 `ML → mL` 是驗證例外，並非自動替換文字；其餘數值和技術名稱仍受保護。預測只能接在原字串後面。

NSSpellChecker 回呼可能在任意佇列執行：背景回呼使用 `nonisolated Sendable`，更新畫面前切回 `MainActor`。取消、逾時和過期結果都不能修改新組字。

修改入口：[文字協助說明](text-assistance.md)、[CandidateRanking](../Packages/CandidateRanking/Sources/CandidateRanking)、[Source/TextAssistance.swift](../Source/TextAssistance.swift)。

## 套件與資料依賴

```mermaid
flowchart LR
    Main[McBopomofo 主程式] --> Local[本機 Swift 套件]
    Local --> OpenCC[OpenCCBridge]
    OpenCC --> ExternalCC[SwiftyOpenCC]
    Local --> Char[SystemCharacterInfo]
    Char --> SQLite[SQLite.swift]
    SQLite --> Toolchain[swift-toolchain-sqlite]
    Main --> Bridge[Objective-C++ 橋接]
    Bridge --> CPP[C++ 引擎]
    Data[Source/Data 建置工具] --> Resources[打包詞庫資源]
    Resources --> CPP
```

| 本機套件 | 用途 |
| --- | --- |
| MixedInputCore | F 手勢、符號映射、Shift 模式、英文編輯、技術詞比對 |
| CandidateRanking | 文字協助請求、模型供應器、保護驗證與非同步生命週期 |
| CandidateUI | 選字與建議視窗 |
| TooltipUI、NotifierUI | 短暫提示與通知介面 |
| InputSourceHelper | macOS 輸入來源工具 |
| FSEventStreamHelper | 監看詞庫檔案變化 |
| NSStringUtils | 字串與橋接工具 |
| BopomofoBraille | 注音轉臺灣點字 |
| ChineseNumbers、RomanNumbers | 中文數字與羅馬數字轉換 |
| OpenCCBridge | 中文字形轉換橋接 |
| SystemCharacterInfo | 字元資訊資料查詢 |
| InfoCollector | 系統資訊收集工具；不是打字內容日誌 |

套件目錄存在不表示每個 target 都使用它；實際連結以 `McBopomofo.xcodeproj/project.pbxproj` 和各 `Package.swift` 為準。外部版本以儲存庫的 `Package.resolved` 固定，不隨意更新。

## 文件與修改路線

```mermaid
flowchart TD
    Readme[README 功能與入口] --> Install[installation 安裝]
    Readme --> Usage[quick-symbols 與 vim-input 操作]
    Readme --> Dictionary[dictionary 詞彙匯入]
    Readme --> Assistance[text-assistance 文字協助]
    Readme --> Dev[development 自行修改與編譯]
    Dev --> Architecture[本文件 架構與依賴]
    Architecture --> Algorithm[algorithm.md 傳統引擎細節]
    Dev --> Tests[test-headless.sh 檢查]
    Tests --> Build[build.sh Release]
    Build --> Package[package.sh 封裝]
    Package --> Verify[verify-package.sh 驗證]
    Verify --> Manual[由使用者安裝與實鍵驗收]
```

小修改先找對應純 Swift 套件與測試。只有注音演算法問題才進 C++ 引擎；詞庫內容修改另讀 [Source/Data/AGENTS.md](../Source/Data/AGENTS.md)。編譯、封裝與推送原始碼都不等於安裝；`build-for-testing` 只編譯整合測試，不能宣稱已完成實鍵驗收。
