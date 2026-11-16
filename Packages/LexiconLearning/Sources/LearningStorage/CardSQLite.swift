// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import LearningCore

/// 共用 v2 容器：固定表結構、嚴格值驗證，絕不執行外來 SQL。
public enum CardSQLite {
    public static let tables: [String: String] = [
        "metadata": "CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
        "origins": "CREATE TABLE origins (id TEXT PRIMARY KEY, subject_id TEXT NOT NULL, source TEXT NOT NULL, reference TEXT NOT NULL)",
        "concepts": "CREATE TABLE concepts (id TEXT PRIMARY KEY, definition TEXT NOT NULL, domain TEXT NOT NULL)",
        "forms": "CREATE TABLE forms (id TEXT PRIMARY KEY, text TEXT NOT NULL, kind TEXT NOT NULL)",
        "names": "CREATE TABLE names (id TEXT PRIMARY KEY, concept_id TEXT NOT NULL, form_id TEXT NOT NULL, source TEXT NOT NULL)",
        "readings": "CREATE TABLE readings (id TEXT PRIMARY KEY, value TEXT NOT NULL)",
        "pronunciations": "CREATE TABLE pronunciations (id TEXT PRIMARY KEY, name_id TEXT NOT NULL, reading_id TEXT NOT NULL, source TEXT NOT NULL)",
        "bindings": "CREATE TABLE bindings (id TEXT PRIMARY KEY, name_id TEXT NOT NULL, reading_id TEXT NOT NULL, code TEXT NOT NULL, term_type TEXT NOT NULL, source TEXT NOT NULL)",
        "relations": "CREATE TABLE relations (id TEXT PRIMARY KEY, source_id TEXT NOT NULL, target_id TEXT NOT NULL, kind TEXT NOT NULL, source TEXT NOT NULL)",
        "legacy_links": "CREATE TABLE legacy_links (source_id TEXT NOT NULL, target_id TEXT NOT NULL, PRIMARY KEY (source_id, target_id))",
    ]
    public static func encode(_ value: UnifiedLexicon) throws -> Data {
        try value.validated()
        guard let graph = value.cards else { throw LexiconError.invalid("缺少詞彙卡") }
        return try UnifiedSQLite.temporary { url in
            do {
                let db = try Database(url, writable: true)
                try db.run("PRAGMA application_id=1095320140"); try db.run("PRAGMA user_version=2")
                try db.run("BEGIN IMMEDIATE")
                for key in tables.keys.sorted() { try db.run(tables[key]!) }
                let meta = ["format": "ai-bopomofo.sqlite", "schema_version": "2.0.0", "document_type": value.document.document_type, "dictionary_version": value.document.dictionary_version]
                for key in meta.keys.sorted() { try db.run("INSERT INTO metadata VALUES (?, ?)", [key, meta[key]!]) }
                for r in graph.origins { try db.run("INSERT INTO origins VALUES (?, ?, ?, ?)", [r.id, r.subject_id, r.source, r.reference]) }
                for r in graph.concepts { try db.run("INSERT INTO concepts VALUES (?, ?, ?)", [r.id, r.definition, r.domain]) }
                for r in graph.forms { try db.run("INSERT INTO forms VALUES (?, ?, ?)", [r.id, r.text, r.kind]) }
                for r in graph.names { try db.run("INSERT INTO names VALUES (?, ?, ?, ?)", [r.id, r.concept_id, r.form_id, r.source]) }
                for r in graph.readings { try db.run("INSERT INTO readings VALUES (?, ?)", [r.id, r.value]) }
                for r in graph.pronunciations { try db.run("INSERT INTO pronunciations VALUES (?, ?, ?, ?)", [r.id, r.name_id, r.reading_id, r.source]) }
                for r in graph.bindings { try db.run("INSERT INTO bindings VALUES (?, ?, ?, ?, ?, ?)", [r.id, r.name_id, r.reading_id, r.code, r.term_type.rawValue, r.source]) }
                for r in graph.relations { try db.run("INSERT INTO relations VALUES (?, ?, ?, ?, ?)", [r.id, r.source_id, r.target_id, r.kind, r.source]) }
                for r in graph.legacy_links { try db.run("INSERT INTO legacy_links VALUES (?, ?)", [r.source_id, r.target_id]) }
                try db.run("COMMIT")
            }
            let bytes = try Data(contentsOf: url)
            guard bytes.count <= UnifiedSQLite.maximumBytes else { throw LexiconError.invalid("詞彙卡超過 16 MiB") }; return bytes
        }
    }
    static func decode(_ db: Database) throws -> UnifiedLexicon {
        let schema = try db.rows("SELECT type,name,sql FROM sqlite_schema WHERE sql IS NOT NULL ORDER BY name", limit: tables.count + 1)
        func normalized(_ s: String) -> String { s.filter { !$0.isWhitespace }.lowercased() }
        guard schema.count == tables.count else { throw LexiconError.invalid("詞彙卡含未知資料表") }
        for row in schema {
            guard row[0] == "table", let sql = tables[row[1]], normalized(sql) == normalized(row[2]) else { throw LexiconError.invalid("詞彙卡結構不相容") }
        }
        guard try db.rows("PRAGMA quick_check(1)") == [["ok"]] else { throw LexiconError.invalid("詞彙卡完整性檢查失敗") }
        let rows = try db.rows("SELECT key,value FROM metadata", limit: 5)
        let meta = Dictionary(uniqueKeysWithValues: rows.map { ($0[0], $0[1]) })
        guard Set(meta.keys) == ["format", "schema_version", "document_type", "dictionary_version"], meta["format"] == "ai-bopomofo.sqlite", meta["schema_version"] == "2.0.0", ["review", "approved"].contains(meta["document_type"] ?? "") else { throw LexiconError.invalid("詞彙卡版本不支援") }
        var graph = CardGraph()
        graph.origins = try db.rows("SELECT id,subject_id,source,reference FROM origins ORDER BY rowid", limit: 40_001).map { row in
            let object: [String: String] = ["id": row[0], "subject_id": row[1], "source": row[2], "reference": row[3]]
            return try JSONDecoder().decode(CardOrigin.self, from: JSONSerialization.data(withJSONObject: object))
        }
        graph.concepts = try db.rows("SELECT id,definition,domain FROM concepts ORDER BY rowid", limit: 40_001).map { row in
            let object: [String: String] = ["id": row[0], "definition": row[1], "domain": row[2]]
            return try JSONDecoder().decode(LexiconConcept.self, from: JSONSerialization.data(withJSONObject: object))
        }
        graph.forms = try db.rows("SELECT id,text,kind FROM forms ORDER BY rowid", limit: 40_001).map { row in
            let object: [String: String] = ["id": row[0], "text": row[1], "kind": row[2]]
            return try JSONDecoder().decode(LexiconForm.self, from: JSONSerialization.data(withJSONObject: object))
        }
        graph.names = try db.rows("SELECT id,concept_id,form_id,source FROM names ORDER BY rowid", limit: 40_001).map { row in
            let object: [String: String] = ["id": row[0], "concept_id": row[1], "form_id": row[2], "source": row[3]]
            return try JSONDecoder().decode(ConceptForm.self, from: JSONSerialization.data(withJSONObject: object))
        }
        graph.readings = try db.rows("SELECT id,value FROM readings ORDER BY rowid", limit: 40_001).map { row in
            let object: [String: String] = ["id": row[0], "value": row[1]]
            return try JSONDecoder().decode(CardReading.self, from: JSONSerialization.data(withJSONObject: object))
        }
        graph.pronunciations = try db.rows("SELECT id,name_id,reading_id,source FROM pronunciations ORDER BY rowid", limit: 40_001).map { row in
            let object: [String: String] = ["id": row[0], "name_id": row[1], "reading_id": row[2], "source": row[3]]
            return try JSONDecoder().decode(FormReading.self, from: JSONSerialization.data(withJSONObject: object))
        }
        graph.bindings = try db.rows("SELECT id,name_id,reading_id,code,term_type,source FROM bindings ORDER BY rowid", limit: 40_001).map { row in
            let object: [String: String] = ["id": row[0], "name_id": row[1], "reading_id": row[2], "code": row[3], "term_type": row[4], "source": row[5]]
            return try JSONDecoder().decode(CardBinding.self, from: JSONSerialization.data(withJSONObject: object))
        }
        graph.relations = try db.rows("SELECT id,source_id,target_id,kind,source FROM relations ORDER BY rowid", limit: 40_001).map { row in
            let object: [String: String] = ["id": row[0], "source_id": row[1], "target_id": row[2], "kind": row[3], "source": row[4]]
            return try JSONDecoder().decode(ConceptRelation.self, from: JSONSerialization.data(withJSONObject: object))
        }
        graph.legacy_links = try db.rows("SELECT source_id,target_id FROM legacy_links ORDER BY rowid", limit: 40_001).map { row in
            let object: [String: String] = ["source_id": row[0], "target_id": row[1]]
            return try JSONDecoder().decode(LegacyCardLink.self, from: JSONSerialization.data(withJSONObject: object))
        }
        var value = try graph.exchange(version: meta["dictionary_version"]!)
        value.document.document_type = meta["document_type"]!
        if value.document.document_type == "approved" {
            for i in value.document.entries.indices { value.document.entries[i].review.status = .approved }
        }
        try value.validated(); return value
    }
}
