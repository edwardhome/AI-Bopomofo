# Lexicon JSON Schema 1.0.0

正式機器格式位於 ../../schemas/lexicon-v1.schema.json；公開範例位於 ../../examples/lexicon-review-example.json。使用 JSON Schema Draft 2020-12。App 額外執行結構預掃描及語意驗證：重複 JSON 欄位、深度、雜湊身分、讀音字數對應與核准能力檢查不能只靠一般 JSON 解碼器。

format 固定 ai-bopomofo.lexicon；schema_version 固定 1.0.0。document_type 為 review 或 approved；兩者從外部匯入均需本機重新核准。本版只接受 1.0.0，其他版本明確拒絕；不能把未知 major 當成相同格式。未來 migration 必須新增顯式轉換與測試。

term_type：zh_phrase、english_term、technical_alias、unicode_mapping。中文以標準注音加聲調，音節用 ASCII 減號連接，最多八個音節且逐字對應漢字；英文及技術碼為 2–64 個無空白可列印 ASCII。輸出最多 128 個 UTF-16 code units，不允許控制字元、換行與格式控制字元。不轉小寫、不作 NFKC；查詢可忽略 ASCII 大小寫，識別仍區分大小寫及精確 Unicode。

entry_id 計算：依序取 term_type、reading、text 的 UTF-8；每段前面加八位元組無號 big-endian 長度，再串接，取 SHA-256 小寫十六進位。讀音或輸出變更是新身分，不使用模型生成的任意 ID。

usage 是來源提供的統計，匯入不加進本機計數。review.user_confirmed 表示明確記住，與部署授權不同。model_suggestion 保存 origin_entry_id、原因、模型識別與可選的推測提示／分類；無法取得模型版本時不填。相同輸出身分的建議與觀察合併匯出時，原始觀察欄位保留，推測保存在 model_suggestion。

單檔最多 8 MiB、20,000 個 entries、深度 12。拒絕未知欄位、矛盾重複身分及 prefer。policy 可省略或為 candidate_only。JSON Schema 的 Unicode maxLength 為碼點，App 的 UTF-16 上限可能更嚴格；以 App 語意驗證為最終部署門檻。

內建工程詞可展開為每組輸入碼／輸出一筆交換詞條；測試核對 103 個原詞條的輸出集合完全保留，不把這些測試資料寫入私人資料庫或標為使用者核准。

更新時間：2026-11-04T02:48:30+08:00
