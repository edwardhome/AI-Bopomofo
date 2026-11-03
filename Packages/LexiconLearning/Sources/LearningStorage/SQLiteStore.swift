// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import CSQLite
import LearningCore

private final class Connection: @unchecked Sendable {
    let db: OpaquePointer
    init(_ path: String, readOnly: Bool = false) throws {
        var pointer: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let code = sqlite3_open_v2(path, &pointer, flags | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK, let pointer else {
            if let pointer { sqlite3_close(pointer) }; throw LexiconError.invalid("無法開啟學習資料庫（\(code)）")
        }
        db = pointer; sqlite3_busy_timeout(db, 0)
    }
    deinit { sqlite3_close_v2(db) }
    func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }
    func error() -> LexiconError { .invalid("SQLite 錯誤 \(sqlite3_extended_errcode(db))；學習暫停") }
    func statement(_ sql: String, _ values: [String] = []) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw error() }
        for (i, value) in values.enumerated() {
            let code = value.withCString { sqlite3_bind_text(stmt, Int32(i + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            if code != SQLITE_OK { sqlite3_finalize(stmt); throw error() }
        }
        return stmt
    }
    func run(_ sql: String, _ values: [String] = []) throws {
        let stmt = try statement(sql, values); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }
    func rows(_ sql: String, _ values: [String] = []) throws -> [[String]] {
        let stmt = try statement(sql, values); defer { sqlite3_finalize(stmt) }
        var rows: [[String]] = []
        while true {
            let code = sqlite3_step(stmt)
            if code == SQLITE_DONE { return rows }
            guard code == SQLITE_ROW else { throw error() }
            rows.append((0..<sqlite3_column_count(stmt)).map { column in
                sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? ""
            })
        }
    }
}

/// 所有 SQLite 操作在 actor 上串行；建立此 actor 也必須由背景工作呼叫。
public actor SQLiteStore {
    private let connection: Connection
    private let beforeCommit: @Sendable () throws -> Void
    public let url: URL
    public init(url: URL, readOnly: Bool = false, beforeCommit: @escaping @Sendable () throws -> Void = {}) throws {
        self.url = url
        self.beforeCommit = beforeCommit
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        connection = try Connection(url.path, readOnly: readOnly)
        let check = try connection.rows("PRAGMA quick_check")
        guard check.first?.first == "ok" else { throw LexiconError.invalid("學習資料庫完整性檢查失敗") }
        let version = Int(try connection.rows("PRAGMA user_version").first?.first ?? "0") ?? -1
        guard version <= 1 else { throw LexiconError.invalid("學習資料庫版本較新，停止學習以免降版破壞資料") }
        if readOnly { return }
        try connection.execute("PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA journal_size_limit=1048576; PRAGMA max_page_count=16384;")
        if version == 0 {
            try connection.execute("""
            BEGIN IMMEDIATE;
            CREATE TABLE observed_terms(entry_key TEXT PRIMARY KEY, term_type TEXT NOT NULL, reading TEXT NOT NULL,
              text TEXT NOT NULL, payload TEXT NOT NULL, commit_count INTEGER NOT NULL DEFAULT 0 CHECK(commit_count>=0),
              manual_selection_count INTEGER NOT NULL DEFAULT 0, user_confirmed INTEGER NOT NULL DEFAULT 0,
              first_seen_at REAL NOT NULL, last_seen_at REAL NOT NULL, organized_count INTEGER NOT NULL DEFAULT -1,
              attempts INTEGER NOT NULL DEFAULT 0, retry_at REAL NOT NULL DEFAULT 0,
              UNIQUE(term_type,reading,text));
            CREATE INDEX observed_recent ON observed_terms(last_seen_at);
            CREATE TABLE model_suggestions(suggestion_id TEXT PRIMARY KEY, entry_key TEXT NOT NULL REFERENCES observed_terms(entry_key) ON DELETE CASCADE,
              payload TEXT NOT NULL, status TEXT NOT NULL, created_at REAL NOT NULL);
            CREATE TABLE review_records(review_id TEXT PRIMARY KEY, entry_key TEXT NOT NULL, action TEXT NOT NULL, reviewer TEXT NOT NULL, reviewed_at REAL NOT NULL);
            CREATE TABLE lexicon_versions(version_id TEXT PRIMARY KEY, schema_version TEXT NOT NULL, checksum TEXT NOT NULL, created_at REAL NOT NULL, activated_at REAL, status TEXT NOT NULL);
            CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE excluded_terms(entry_key TEXT PRIMARY KEY);
            CREATE TABLE processed_events(event_id TEXT PRIMARY KEY, processed_at REAL NOT NULL);
            PRAGMA user_version=1;
            COMMIT;
            """)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func ingest(_ events: [Observation], now: Date = Date()) throws {
        guard events.count <= 128 else { throw LexiconError.invalid("觀察批次過大") }
        try connection.execute("BEGIN IMMEDIATE")
        do {
            for event in events {
                guard (try? event.entry.validated()) != nil else { continue }
                let e = event.entry
                if event.kind == .explicitRemember { try connection.run("DELETE FROM excluded_terms WHERE entry_key=?", [e.entry_id]) }
                if !(try connection.rows("SELECT 1 FROM excluded_terms WHERE entry_key=?", [e.entry_id])).isEmpty { continue }
                try connection.run("INSERT OR IGNORE INTO processed_events VALUES(?,?)", [event.id.uuidString, String(now.timeIntervalSince1970)])
                guard sqlite3_changes(connection.db) == 1 else { continue }
                let payload = String(decoding: try JSONEncoder().encode(e), as: UTF8.self)
                let commit = event.kind == .explicitRemember ? 0 : 1
                let manual = event.kind == .manualSelected ? 1 : 0
                let confirmed = event.kind == .explicitRemember ? 1 : 0
                // 日級彙總不保留逐筆時間，不能用此表重播提交順序。
                let day = floor(event.at.timeIntervalSince1970 / 86400) * 86400
                try connection.run("""
                  INSERT INTO observed_terms(entry_key,term_type,reading,text,payload,commit_count,manual_selection_count,user_confirmed,first_seen_at,last_seen_at)
                  VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(entry_key) DO UPDATE SET
                  commit_count=min(commit_count+excluded.commit_count,2147483647),
                  manual_selection_count=min(manual_selection_count+excluded.manual_selection_count,2147483647),
                  user_confirmed=max(user_confirmed,excluded.user_confirmed),last_seen_at=max(last_seen_at,excluded.last_seen_at)
                  """, [e.entry_id,e.term_type.rawValue,e.reading,e.text,payload,String(commit),String(manual),String(confirmed),String(day),String(day)])
            }
            try prune(now)
            try beforeCommit()
            try connection.execute("COMMIT")
        } catch { try? connection.execute("ROLLBACK"); throw error }
        try connection.execute("PRAGMA wal_checkpoint(PASSIVE)")
    }
    private func prune(_ now: Date) throws {
        try connection.run("DELETE FROM observed_terms WHERE last_seen_at<? AND user_confirmed=0", [String(now.addingTimeInterval(-90*86400).timeIntervalSince1970)])
        try connection.execute("DELETE FROM observed_terms WHERE entry_key IN (SELECT entry_key FROM observed_terms ORDER BY user_confirmed DESC,last_seen_at DESC LIMIT -1 OFFSET 50000)")
        try connection.run("DELETE FROM model_suggestions WHERE created_at<?", [String(now.addingTimeInterval(-30*86400).timeIntervalSince1970)])
        try connection.execute("DELETE FROM model_suggestions WHERE suggestion_id IN (SELECT suggestion_id FROM model_suggestions ORDER BY created_at DESC LIMIT -1 OFFSET 5000)")
        try connection.execute("DELETE FROM processed_events WHERE event_id IN (SELECT event_id FROM processed_events ORDER BY processed_at DESC LIMIT -1 OFFSET 4096)")
    }
    public func entries(pendingOnly: Bool = false, limit: Int = 50_000) throws -> [LexiconEntry] {
        let filter = pendingOnly ? "WHERE organized_count<commit_count AND attempts<3 AND retry_at<\(Date().timeIntervalSince1970)" : ""
        return try connection.rows("SELECT payload,commit_count,manual_selection_count,user_confirmed FROM observed_terms \(filter) ORDER BY entry_key LIMIT \(min(50_000,max(0,limit)))").map { row in
            var e = try JSONDecoder().decode(LexiconEntry.self, from: Data(row[0].utf8))
            e.usage = Usage(commits: Int64(row[1]) ?? 0, manual: Int64(row[2]) ?? 0)
            e.review = Review(.observed, confirmed: row[3] == "1"); return e
        }
    }
    public func suggestions() throws -> [LexiconEntry] {
        try connection.rows("SELECT payload FROM model_suggestions WHERE status='proposed' ORDER BY suggestion_id LIMIT 5000").map {
            try JSONDecoder().decode(LexiconEntry.self, from: Data($0[0].utf8))
        }
    }
    public func finishBatch(_ originals: [LexiconEntry], suggestions: [LexiconEntry]) throws {
        let origins = Set(originals.map(\.entry_id))
        try connection.execute("BEGIN IMMEDIATE")
        do {
            for e in suggestions {
                try e.validated()
                guard e.review.status == .proposed, let s = e.model_suggestion, origins.contains(s.origin_entry_id) else { throw LexiconError.invalid("模型建議來源不符") }
                if !(try connection.rows("SELECT 1 FROM excluded_terms WHERE entry_key=?", [e.entry_id])).isEmpty { continue }
                try connection.run("INSERT OR IGNORE INTO model_suggestions VALUES(?,?,?,?,?)", [s.suggestion_id,s.origin_entry_id,String(decoding: try JSONEncoder().encode(e),as: UTF8.self),"proposed",String(Date().timeIntervalSince1970)])
            }
            for e in originals { try connection.run("UPDATE observed_terms SET organized_count=?,attempts=0,retry_at=0 WHERE entry_key=?", [String(e.usage?.commit_count ?? 0),e.entry_id]) }
            try prune(Date()); try connection.execute("COMMIT")
        } catch { try? connection.execute("ROLLBACK"); throw error }
    }
    public func failedBatch(_ entries: [LexiconEntry]) throws {
        for e in entries { try connection.run("UPDATE observed_terms SET attempts=attempts+1,retry_at=? WHERE entry_key=?", [String(Date().addingTimeInterval(300).timeIntervalSince1970),e.entry_id]) }
    }
    public func exclude(_ key: String) throws {
        try connection.execute("BEGIN IMMEDIATE")
        do {
            try connection.run("INSERT OR IGNORE INTO excluded_terms VALUES(?)", [key])
            for row in try connection.rows("SELECT suggestion_id,payload FROM model_suggestions") {
                let entry = try JSONDecoder().decode(LexiconEntry.self, from: Data(row[1].utf8))
                if entry.entry_id == key { try connection.run("DELETE FROM model_suggestions WHERE suggestion_id=?", [row[0]]) }
            }
            try connection.run("DELETE FROM observed_terms WHERE entry_key=?", [key]); try connection.execute("COMMIT")
        } catch { try? connection.execute("ROLLBACK"); throw error }
    }
    public func clear() throws { try connection.execute("BEGIN IMMEDIATE; DELETE FROM model_suggestions; DELETE FROM observed_terms; DELETE FROM processed_events; COMMIT; PRAGMA wal_checkpoint(TRUNCATE);") }
    public func retryPending() throws { try connection.execute("UPDATE observed_terms SET attempts=0,retry_at=0 WHERE attempts>0") }
    /// 核准檔案才是權威；此為可失敗的 SQLite 查閱鏡本，不參與版本切換交易。
    public func recordApproval(id: String, version: String, checksum: String, at: Date, entries: [LexiconEntry]) throws {
        try connection.execute("BEGIN IMMEDIATE")
        do {
            try connection.execute("UPDATE lexicon_versions SET status='archived' WHERE status='active'")
            try connection.run("INSERT INTO lexicon_versions VALUES(?,?,?,?,?,?) ON CONFLICT(version_id) DO UPDATE SET activated_at=excluded.activated_at,status='active'",
                [version,"1.0.0",checksum,String(at.timeIntervalSince1970),String(Date().timeIntervalSince1970),"active"])
            for entry in entries {
                try connection.run("INSERT OR IGNORE INTO review_records VALUES(?,?,?,?,?)", [id+":"+entry.entry_id,entry.entry_id,"approved","local_user",String(at.timeIntervalSince1970)])
                if let suggestion = entry.model_suggestion {
                    try connection.run("UPDATE model_suggestions SET status='approved' WHERE suggestion_id=?", [suggestion.suggestion_id])
                }
            }
            try connection.execute("DELETE FROM review_records WHERE review_id IN (SELECT review_id FROM review_records ORDER BY reviewed_at DESC LIMIT -1 OFFSET 60000)")
            try connection.execute("COMMIT")
        } catch { try? connection.execute("ROLLBACK"); throw error }
    }
    public func periodicBackup() throws {
        let previous = Double(try connection.rows("SELECT value FROM settings WHERE key='backup_at'").first?.first ?? "0") ?? 0
        guard Date().timeIntervalSince1970 - previous >= 86400 else { return }
        let folder = url.deletingLastPathComponent().appendingPathComponent("snapshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let name = "learning-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).sqlite"
        try backup(to: folder.appendingPathComponent(name))
        try connection.run("INSERT OR REPLACE INTO settings VALUES('backup_at',?)", [String(Date().timeIntervalSince1970)])
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("learning-") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for file in files.dropFirst(3) { try FileManager.default.removeItem(at: file) }
    }
    public func backup(to target: URL) throws {
        guard !FileManager.default.fileExists(atPath: target.path) else { throw LexiconError.invalid("備份檔已存在") }
        let destination = try Connection(target.path)
        guard let backup = sqlite3_backup_init(destination.db, "main", connection.db, "main") else { throw destination.error() }
        let code = sqlite3_backup_step(backup, -1), finish = sqlite3_backup_finish(backup)
        guard code == SQLITE_DONE && finish == SQLITE_OK else { throw destination.error() }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
    /// 僅在完整性檢查或 SQLITE_CORRUPT/NOTADB 確認後呼叫；保留 WAL 與 SHM。
    public static func quarantine(_ url: URL) throws -> URL {
        let folder = url.deletingLastPathComponent().appendingPathComponent("quarantine-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for suffix in ["", "-wal", "-shm"] {
            let original = URL(fileURLWithPath: url.path + suffix)
            if FileManager.default.fileExists(atPath: original.path) { try FileManager.default.moveItem(at: original, to: folder.appendingPathComponent(original.lastPathComponent)) }
        }
        return folder
    }
}
