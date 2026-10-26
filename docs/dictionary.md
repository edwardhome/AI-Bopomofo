# 專業詞庫

內建 FPGA、Vivado、SystemVerilog、Verilog、VHDL、Python、Flask、PySide6、GitHub、Git、Codex、McBopomofo、InputMethodKit、CoreML、Swift、Xcode、MacBook、Apple、RTX，另含 branch、module。

不另外建立使用者詞庫資料庫。選單「編輯使用者詞庫」開啟既有 data.txt，可新增例如 `MyFPGA _english_myfpga`。`_english_` 是英文候選專用 reading 命名空間；不影響注音讀音。保留詞彙大小寫。詞庫監視器重載時更新記憶體快取，按鍵路徑不讀取檔案。

匯入：選「匯入專業詞彙」，UTF-8 純文字每行一詞，最多 1 MiB／5000 詞，每詞最多 64 ASCII 字元且至少包含英文字母，不含空白；以 # 開頭視為註解。匯入前備份現有 data.txt 到同資料夾的 data.txt.backup-UUID，經 LanguageModelManager 逐項新增，既有詞彙略過。若中途失敗，可能部分新增，重試不重複寫入；備份不自動覆蓋回原檔。

匯出：選「匯出專業詞彙」，只匯出 `_english_` 自訂詞，每行一詞；不匯出私人中文詞庫。可用既有編輯使用者詞庫功能刪除／修改條目。預設目錄由 Preferences 決定，為 ~/Library/Application Support/AI-Bopomofo；也尊重使用者自訂位置。

載入上限為 5000 個自訂詞與 4 MiB 詞庫檔案，候選最多原文加 8 個補全。超過檔案上限僅用內建英文詞；中文引擎仍依上游規則處理。候選排序是決定性前綴比對，不是 AI。

檔案只保存在本機，真實詞庫與其備份不得納入 Git。本次未讀取或匯入任何私人詞彙。
