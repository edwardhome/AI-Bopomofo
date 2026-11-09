// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import CSQLite
import LearningCore

/// 可攜 SQLite 詞庫。外部檔案先複製到私有暫存區，唯讀且只執行固定查詢。
/// 不執行檔案提供的 SQL，不接受 view、trigger 或額外 schema 物件。
public enum UnifiedSQLite {
    public static let maximumBytes = 16 * 1024 * 1024
    public static let applicationID = 0x4149424c
    public static let tables = [
        "metadata": "CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
        "entries": "CREATE TABLE entries (entry_id TEXT PRIMARY KEY, position INTEGER NOT NULL UNIQUE, term_type TEXT NOT NULL, reading TEXT NOT NULL, text TEXT NOT NULL, payload TEXT NOT NULL)",
        "relations": "CREATE TABLE relations (source_id TEXT NOT NULL, target_id TEXT NOT NULL, kind TEXT NOT NULL, PRIMARY KEY (source_id, target_id, kind))"
    ]
    public static func isSQLite(_ data: Data) -> Bool { data.starts(with: Data("SQLite format 3\0".utf8)) }

    private static func temporary<T>(_ body: (URL) throws -> T) throws -> T {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ai-lexicon-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        return try body(folder.appendingPathComponent("lexicon.sqlite"))
    }
    public static func encode(_ value: UnifiedLexicon) throws -> Data {
        try value.validated()
        return try temporary { url in
            do {
                let db = try Database(url, writable: true)
                try db.run("PRAGMA application_id=\(applicationID)")
                try db.run("PRAGMA user_version=1")
                try db.run("BEGIN IMMEDIATE")
                for key in tables.keys.sorted() { try db.run(tables[key]!) }
                let metadata = ["format": "ai-bopomofo.sqlite", "schema_version": "1.0.0",
                    "document_type": value.document.document_type, "dictionary_version": value.document.dictionary_version]
                for key in metadata.keys.sorted() { try db.run("INSERT INTO metadata VALUES (?, ?)", [key, metadata[key]!]) }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                for (position, entry) in value.document.entries.enumerated() {
                    let payload = String(decoding: try encoder.encode(entry), as: UTF8.self)
                    try db.run("INSERT INTO entries VALUES (?, ?, ?, ?, ?, ?)",
                        [entry.entry_id, String(position), entry.term_type.rawValue, entry.reading, entry.text, payload])
                }
                for r in value.relations { try db.run("INSERT INTO relations VALUES (?, ?, ?)", [r.source_id, r.target_id, r.kind]) }
                try db.run("COMMIT")
            } // 關閉完整的獨立資料庫後才輸出；沒有運作中的 WAL／SHM 依賴。
            let bytes = try Data(contentsOf: url)
            guard bytes.count <= maximumBytes else { throw LexiconError.invalid("SQLite 超過 16 MiB") }
            return bytes
        }
    }
    public static func decode(_ data: Data) throws -> UnifiedLexicon {
        guard data.count <= maximumBytes, isSQLite(data) else { throw LexiconError.invalid("不是支援的 SQLite 詞庫") }
        return try temporary { url in
            try data.write(to: url, options: .atomic)
            let db = try Database(url, writable: false)
            guard try db.rows("PRAGMA application_id") == [[String(applicationID)]],
                  try db.rows("PRAGMA user_version") == [["1"]] else { throw LexiconError.invalid("不支援的 SQLite 詞庫版本") }
            let schema = try db.rows("SELECT type, name, sql FROM sqlite_schema WHERE sql IS NOT NULL ORDER BY name", limit: 4)
            guard schema.count == tables.count else { throw LexiconError.invalid("SQLite 含未知結構") }
            func normalized(_ s: String) -> String { s.filter { !$0.isWhitespace }.lowercased() }
            for row in schema {
                guard row.count == 3, row[0] == "table", let expected = tables[row[1]],
                      normalized(row[2]) == normalized(expected) else { throw LexiconError.invalid("SQLite 結構不相容") }
            }
            guard try db.rows("PRAGMA quick_check(1)") == [["ok"]] else { throw LexiconError.invalid("SQLite 完整性檢查失敗") }
            let metaRows = try db.rows("SELECT key,value FROM metadata", limit: 5)
            guard metaRows.count == 4 else { throw LexiconError.invalid("SQLite metadata 不完整") }
            let meta = Dictionary(metaRows.map { ($0[0], $0[1]) }, uniquingKeysWith: { first, _ in first })
            guard Set(meta.keys) == ["format", "schema_version", "document_type", "dictionary_version"],
                  meta["format"] == "ai-bopomofo.sqlite", meta["schema_version"] == "1.0.0" else { throw LexiconError.invalid("SQLite metadata 不相容") }
            var entries: [LexiconEntry] = []
            for row in try db.rows("SELECT entry_id,position,term_type,reading,text,payload FROM entries ORDER BY position", limit: 20_001) {
                guard entries.count < 20_000, row[1] == String(entries.count) else { throw LexiconError.invalid("SQLite 詞條順序／數量不合法") }
                // 經原有嚴格 JSON entry 驗證，拒絕未知欄位及重複鍵。
                try JSONPreflight.validate(Data(row[5].utf8))
                let object = try JSONSerialization.jsonObject(with: Data(row[5].utf8))
                let envelope: [String: Any] = ["format": "ai-bopomofo.lexicon", "schema_version": "1.0.0",
                    "document_type": meta["document_type"]!, "dictionary_version": meta["dictionary_version"]!, "entries": [object]]
                let entry = try LexiconDocument.decode(JSONSerialization.data(withJSONObject: envelope)).entries[0]
                guard row[0] == entry.entry_id, row[2] == entry.term_type.rawValue,
                      row[3] == entry.reading, row[4] == entry.text else { throw LexiconError.invalid("SQLite 詞條欄位與 payload 不一致") }
                entries.append(entry)
            }
            var relations: [LexiconRelation] = []
            for row in try db.rows("SELECT source_id,target_id,kind FROM relations ORDER BY source_id,target_id,kind", limit: 40_001) {
                guard row[2] == "equivalent" else { throw LexiconError.invalid("不支援的詞條關聯") }
                relations.append(.init(source: row[0], target: row[1]))
            }
            let value = UnifiedLexicon(document: LexiconDocument(type: meta["document_type"]!, version: meta["dictionary_version"]!, entries: entries), relations: relations)
            try value.validated(); return value
        }
    }
}

private final class Database {
    private let db: OpaquePointer
    init(_ url: URL, writable: Bool) throws {
        var pointer: OpaquePointer?
        let flags = writable ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(url.path, &pointer, flags | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let pointer else {
            if let pointer { sqlite3_close(pointer) }; throw LexiconError.invalid("無法開啟 SQLite 詞庫")
        }
        db = pointer
        sqlite3_busy_timeout(db, 0)
        sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 1_048_576)
        sqlite3_limit(db, SQLITE_LIMIT_SQL_LENGTH, 8192)
        sqlite3_limit(db, SQLITE_LIMIT_COLUMN, 32)
        do {
            try run("PRAGMA trusted_schema=OFF")
            if !writable { try run("PRAGMA query_only=ON") }
        } catch { sqlite3_close(db); throw error }
    }
    deinit { sqlite3_close(db) }
    func rows(_ sql: String, _ values: [String] = [], limit: Int = 10) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw LexiconError.invalid("SQLite 查詢失敗") }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let result = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard result == SQLITE_OK else { throw LexiconError.invalid("SQLite 參數綁定失敗") }
        }
        var result: [[String]] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW, result.count < limit else { throw LexiconError.invalid("SQLite 讀寫失敗或超過上限") }
            var row: [String] = []
            for column in 0..<sqlite3_column_count(statement) {
                guard let text = sqlite3_column_text(statement, column) else { throw LexiconError.invalid("SQLite 不允許 NULL") }
                let count = Int(sqlite3_column_bytes(statement, column))
                guard let value = String(bytes: UnsafeBufferPointer(start: text, count: count), encoding: .utf8), !value.contains("\0") else { throw LexiconError.invalid("SQLite 文字不合法") }
                row.append(value)
            }
            result.append(row)
        }
    }
    func run(_ sql: String, _ values: [String] = []) throws { _ = try rows(sql, values) }
}
