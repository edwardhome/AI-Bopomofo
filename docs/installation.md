# 本地開發版安裝

目前為未經 Developer ID 簽署／公證的本地開發版；app 使用 ad-hoc 簽章，pkg 未簽署。不要關閉整體 Gatekeeper 或 SIP。一般開發不自動安裝；本次對話已明確授權在驗證與備份後更新並重啟本機輸入法。

建議先用使用者層安裝：在專案目錄執行 `scripts/install-debug.sh dist/0.4.0-alpha/AI-Bopomofo.app`（換成欲測版本路徑）。安裝到 `~/Library/Input Methods/AI-Bopomofo.app`，不需管理員權限；既有版本存在時拒絕覆寫。

另一選項為開啟 dist 內的 pkg，由使用者自行授權，安裝到 `/Library/Input Methods/AI-Bopomofo.app`。這兩種方式擇一，不能同時安裝兩份。若系統因未公證而拒絕 pkg，使用本機自行建置的 bundle 與上述腳本。

登出再登入，進入「系統設定 → 鍵盤 → 文字輸入 → 編輯 → 加入輸入方式」，尋找「AI注音輸入法」。確認原版小麥注音仍可選擇。尚需人工驗證設定辨識、組字、選字、標點與各應用相容性。

使用者層解除安裝：先切換為其他輸入法並從設定移除 AI-Bopomofo，再執行 `scripts/uninstall-debug.sh`；腳本把 bundle 移到備份資料夾，不刪除詞庫。登出再登入。

系統層解除安裝：從鍵盤設定移除後，由 Finder 前往 `/Library/Input Methods`，僅將 `AI-Bopomofo.app` 移至垃圾桶並依系統提示授權。不要移除 McBopomofo.app。保留 `~/Library/Application Support/AI-Bopomofo` 與偏好設定即可保留使用者資料。

校驗：在版本目錄執行 `shasum -a 256 -c checksums.txt`。`scripts/verify-bundle.py <app路徑>` 檢查識別碼、詞庫、連線及簽章，不等於實際輸入操作驗證。

更新時間：2026-10-26T16:56:38+08:00
