# 自己修改、編譯與打包 AI注音

這份文件讓你從現有專案修改一個小功能，完成檢查，再產生可安裝的 pkg。編譯不會更換正在使用的輸入法；執行安裝才會更新系統。請先保留一份能正常使用的安裝包。

更新時間：2026-10-29T00:29:23+08:00

## 先選擇是否需要改程式

| 想修改的項目 | 修改位置 | 是否需要重新編譯 |
| --- | --- | --- |
| F 長按等待時間 | 輸入法選單 → 偏好設定 → 進階 | 不需要；下次新按住 F 生效 |
| 中文／半形標點、Shift 英文組詞 | 輸入法選單對應選項 | 不需要 |
| 加入英文專業詞彙 | 選單的匯入專業詞彙；格式見 [詞彙文件](dictionary.md) | 不需要 |
| F＋R 等符號對照 | `Packages/MixedInputCore/Sources/MixedInputCore/QuickSymbolLayer.swift` | 需要 |
| 偏好預設值 | `Source/Preferences.swift`；F 時間常數位於 `QuickSymbolLayer.swift` | 需要；已存偏好不會被新預設值覆蓋 |
| 偏好視窗選項 | `Source/PreferencesUI/PreferencesView.swift`、`PreferencesModel.swift` | 需要 |
| 選單、雙 Shift、F 按鍵轉送 | `Source/InputMethodController.swift` | 需要；先了解組字與事件生命週期 |
| 英文組詞與符號狀態 | `Source/MixedInput.swift` | 需要 |
| 注音處理 | `Source/KeyHandler.mm`、`Source/Engine/` | 需要；先讀 [架構說明](../algorithm.md) |
| 顯示文字翻譯 | `Source/Base.lproj/Localizable.strings`、`en.lproj`、`zh-Hant.lproj` | 需要；三份一起維護 |

0.6.8 起未儲存過的 F 長按等待時間預設為 150 毫秒；已有個人設定保留。100～150 毫秒的緩衝區若放開，仍輸出原鍵，不吃字；完整說明見 [F 符號分層](quick-symbols.md)。

## 1. 準備工具與工作副本

開發需要完整 Xcode 26 以上、macOS 26 以上，以及 Git、Python 3、CMake。執行中的輸入法部署目標為 macOS 13；部署目標不等於每個舊版系統都已實機驗證。

第一次使用 Xcode，先手動開啟一次，完成它要求的元件下載與授權。到 Xcode → Settings → Locations 選好 Command Line Tools，然後在終端確認：

```bash
xcodebuild -version
xcrun swift --version
python3 --version
cmake --version
git --version
```

若 `cmake` 不存在，而你已安裝 Homebrew，可執行 `brew install cmake`。沒有 Homebrew 時可從 CMake 官方取得安裝程式。不要為了建置關閉系統安全性功能。

Mac mini 的現有專案：

```bash
cd /Volumes/DATA/DATA/AI_Bopomofo
git status --short --branch
```

MacBook Air 建議把 iCloud 文件裡的完整專案複製到本機工作目錄，再進行編譯，避免兩台機器同時修改 iCloud 的 `.git` 與建置快取。也可以從個人 GitHub 取得已發布版本：

```bash
mkdir -p ~/Developer
cd ~/Developer
git clone https://github.com/edwardhome/AI-Bopomofo.git
cd AI-Bopomofo
```

只執行適用於你電腦的其中一組。GitHub 副本是公開版本，尚未推送的本機修正不會自動包含在內。

## 2. 建立自己的分支

先看 `git status`。如果有別人或前一次的未提交修改，先保留並確認用途，不要重設它們。工作目錄乾淨後：

```bash
git switch -c feature/my-symbols
```

分支名稱可換成 `feature/你的功能名稱` 或 `fix/問題名稱`。若同名分支已存在，改用其他名稱，不要強制覆寫。

用 Xcode 開啟專案根目錄的 `McBopomofo.xcodeproj`。內部 target 與 scheme 叫 `McBopomofo`，輸出的 app 叫 `AI-Bopomofo.app`，這是刻意保留的設計。不要選 Installer scheme 執行，除非你確實準備安裝。

## 3. 範例：把 F＋R 的輸出從 + 改成其他符號

在 `QuickSymbolLayer.swift` 找到這一列：

```swift
.init(keyCode: 15, label: "R", output: "+"),
```

只修改 `output` 的字串。例如改為 `"="`，表示 F＋R 輸出等號。`keyCode` 是實體鍵位置，不是 ASCII 字碼；單改 `label` 只會改說明，不會改按鍵。

接著到 `Packages/MixedInputCore/Tests/MixedInputCoreTests/QuickSymbolTests.swift`，更新 `suppliedKeyboardRows` 對 R 的預期輸出。若 `McBopomofoTests/MixedInputTests.swift` 也有對 F＋R 結果的斷言，必須一併更新。既有案例不是單純障礙：先判斷失敗是否是你有意改變的行為，不能為了全綠直接刪掉測試。

若字串包含雙引號或反斜線，在 Swift 要寫為 `"\""` 或 `"\\"`。一般小調整先不要修改大詞庫或產品識別碼。

## 4. 設定這次的版本號

修改 `Source/McBopomofo-Info.plist` 的兩個值：

- `CFBundleShortVersionString`：例如 `0.6.9`。
- `CFBundleVersion`：例如 `609`，使用比上一版高的整數。

本文以 **0.6.9-local.1** 作為自己的範例包名，不代表這個版本已正式發布。你實際使用其他版本時，請連同下面的打包指令一起替換。打包腳本不會替你改 app 版本；`0.6.9-local.1` 必須搭配 app 的 `0.6.9`。

## 5. 執行不啟動輸入法的檢查

從專案根目錄執行：

```bash
mkdir -p artifacts
scripts/test-headless.sh > artifacts/my-headless.log 2>&1
```

第一次 clone 若還沒有 `artifacts` 目錄，先執行 `mkdir -p artifacts`。檢查是否成功：

```bash
tail -n 30 artifacts/my-headless.log
```

腳本包含 C++、純 Swift、Python 測試、詞庫檢查，最後編譯 IMK 整合測試，但**不執行 hosted／GUI 測試**。任何一步失敗就先修正，不要繼續裝到日常使用的系統。

只改符號或時間判斷時，可先跑較快的純 Swift 測試：

```bash
swift test --package-path Packages/MixedInputCore
```

它不能取代最後完整檢查，也不能證明 iTerm2 或其他 App 的實際輸入正常。不要把 `build-for-testing` 成功寫成「整合測試已通過」，也不要在輸入法專案直接按 Xcode 的測試執行快捷鍵來替代上述流程。

## 6. 編譯可以安裝的版本

```bash
scripts/build.sh Release > artifacts/my-release.log 2>&1
```

成功時日誌結尾有 `BUILD SUCCEEDED`，app 位於：

```text
build/DerivedData/Build/Products/Release/AI-Bopomofo.app
```

檢查識別碼、資源與版本：

```bash
python3 scripts/verify-bundle.py build/DerivedData/Build/Products/Release/AI-Bopomofo.app
lipo -archs build/DerivedData/Build/Products/Release/AI-Bopomofo.app/Contents/MacOS/AI-Bopomofo
```

目前 Release 設定產生 arm64 與 x86_64 通用執行檔。先跑一般 Release build 再打包，避免把測試建置產物當成發行包。

## 7. 提交原始碼，產生 pkg／zip

先檢查差異，確認沒有私人詞庫、密碼、權杖或本機備份：

```bash
git diff --check
git diff
git status --short
```

只把自己有意修改的檔案加入提交。以下為符號範例，依實際修改增減：

```bash
git add Packages/MixedInputCore/Sources/MixedInputCore/QuickSymbolLayer.swift
git add Packages/MixedInputCore/Tests/MixedInputCoreTests/QuickSymbolTests.swift
git add Source/McBopomofo-Info.plist
git commit -m 'feat(symbols): customize F layer output'
```

再次確認 `git status --short` 沒有未提交的原始碼改動，再打包；`SOURCE-COMMIT.txt` 記錄目前提交，乾淨狀態才方便日後重現：

```bash
scripts/package.sh 0.6.9-local.1 Release
scripts/verify-package.sh dist/0.6.9-local.1
```

輸出資料夾內有：

- `AI-Bopomofo-0.6.9-local.1.pkg`：一般安裝使用。
- `AI-Bopomofo-0.6.9-local.1.zip`：app 的替代封裝。
- `AI-Bopomofo.app`、授權聲明、說明文件、校驗檔與來源提交紀錄。

既有同名資料夾不會覆寫。如果要重新打包，用 `0.6.9-local.2`；保留舊包供回退。打包附帶的發布說明是儲存庫現有文件，你自己的行為改動也應補進 `docs/release-notes.md` 後再提交、打包。

這些操作只保存在本機，不會自動推送 GitHub。

## 8. 備份、安裝與手動驗收

先保存正在編輯的文字，切換到 ABC／US。用 Finder 複製目前 `/Library/Input Methods/AI-Bopomofo.app` 到獨立的備份資料夾，並備份 `~/Library/Application Support/AI-Bopomofo`。如果在偏好設定指定了其他詞庫目錄，也要備份那個目錄。

偏好可以另存成本機 plist，備份路徑必須存在：

```bash
mkdir -p artifacts/manual-backup
defaults export org.aibopomofo.inputmethod.AIBopomofo artifacts/manual-backup/preferences.plist
```

每次更新應使用新的備份資料夾名稱，避免覆蓋上一次備份。這些私人檔案不可加入 Git。日常詞庫匯出與編輯方式見 [詞彙文件](dictionary.md)。

在 Finder 打開剛產生的 pkg，依系統視窗自行核准。pkg 安裝到 `/Library/Input Methods/AI-Bopomofo.app`。如果你目前使用的是 `~/Library/Input Methods/AI-Bopomofo.app`，先看 [安裝說明](installation.md)，不要建立系統與個人目錄兩份同名輸入來源。`scripts/install-debug.sh` 會拒絕既有系統安裝，不適合用來覆蓋日常的系統層版本。

每次程式重新編譯，ad-hoc 簽章可能改變。F 分層若失效，到「系統設定 → 隱私權與安全性 → 輸入監控」移除舊 AI-Bopomofo，再加入目前安裝的 app，完成系統驗證並選「結束並重新打開」。不要直接修改 macOS 權限資料庫。重啟後切至 ABC／US 再切回 AI注音；仍無法組字時，保存工作後登出再登入。

在一般文字欄位與 iTerm2 分別測試：

1. 注音模式短按 F，只出現「ㄑ」，沒有多餘的 `f`。
2. 雙擊 Shift 進英文，短按 F 只出現一次 `f`；Shift＋F 是 `F`。
3. F 按超過設定時間，不應先提交 `f`；接著按 R 輸出設定的符號，放開 F 後恢復一般輸入。
4. 快速連打 F 後接其他字母，順序沒有顛倒或漏字；連續長按、放開也不會卡住。
5. 原本的選字、中文標點、Shift 英文組詞與雙 Shift 切換正常。

不要在有重要命令的終端列直接測試。可先打開空白文字編輯器；終端測試使用自己的空白提示列，不按 Enter 執行測試文字。Kanata 與既有編輯器外掛的設定不會因編譯而變更。

## 9. 常見錯誤與回退

| 狀況 | 處理 |
| --- | --- |
| `xcodebuild` 指向 CommandLineTools | 在完整 Xcode 的 Locations 選好 Command Line Tools，重新檢查 `xcodebuild -version` |
| 缺少套件或下載失敗 | 確認網路，重跑原指令；保留 `Package.resolved`，不要隨意升級依賴 |
| modulemap 比預編譯標頭新 | 先停止建置，把 `build/DerivedData/Build/Intermediates.noindex/PrecompiledHeaders` 移到暫存備份，再重跑；不要刪原始碼或詞庫 |
| Package and bundle versions differ | 確認 Info.plist 與包名的前三段版本一致，重新 Release build |
| Refusing to overwrite preserved artifact | 使用新的 `-local.2` 等包名，不覆寫已保留的包 |
| 編譯成功但 F 失效 | 確認選單開啟 F 功能、等待時間及新版輸入監控授權，再實際試鍵 |
| 重啟後無法組字 | 切出再切回輸入來源；仍失敗則保存工作後登出再登入 |

回退時先切到 ABC／US，再安裝保留的舊 pkg，或透過 Finder 將備份 app 放回原本位置並完成系統驗證。重新啟動、更新該版本的輸入監控，切回 AI注音。不要同時回復整份舊詞庫，除非詞庫本身也出了問題，否則會丟失更新後新增的詞彙。

## 分享給朋友

先完成檢查與手動驗收，保留小麥注音作者署名、MIT 授權與第三方授權。把 pkg、校驗檔與說明一起交付即可；原始碼／發布到 GitHub 是另一個明確步驟。此專案產物使用 ad-hoc 簽章，沒有 Developer ID 簽署或 Apple 公證，不能宣稱已通過 Apple 公證。
