# 中英、數字及半形符號輸入

在 AI-Bopomofo 中文模式，從輸入法選單選「英文／ASCII 組字」，或使用上游既有的 Control+反斜線功能選單，再選「英文／ASCII」。沒有新增系統快捷鍵。

此時出現 ASCII 提示，所有可列印 ASCII（含大小寫、數字、空白、Shift 符號）逐字保留；Enter 送出並回到中文，Esc 取消尚未送出的 ASCII。左右、Home/End、Backspace/Delete 編輯內容。最多 256 字元，達上限時保留內容、拒絕額外字元。Command/Option/Control 快捷鍵會先送出目前 ASCII 再交還應用處理。

從輸入法選單啟動時，若有尚未完成的注音音節，會拒絕切入並保留組字；請完成或取消音節。已完成中文會先依原有流程送出，再進入 ASCII。已送出的中文不會被 Esc 撤回。

重現範例：輸入「使用」→ 完成音節 → 開啟 ASCII → ` Python ` → Enter → 中文「建立」→ ASCII → ` Flask ` → Enter → 中文「服務」。不需要切換系統輸入來源，但此階段仍需要明確指定英文意圖，尚未達成 Zing 式無感混打。

中文模式的頂排數字維持注音功能；數字可用數字鍵盤（含 Kanata F 層）或 ASCII 組字。候選視窗仍遵從原本數字選字設定。中文模式 Shift 標點維持上游；明確進入 ASCII 後 Shift 符號才按字面保留。

Kanata 的 Unicode 可能直接抵達目標應用，不能保證經過 IMK。已驗證 KeyHandler 的 keypad 與 ASCII 合成輸入，尚未驗證真實 Kanata、各應用與睡眠喚醒。
