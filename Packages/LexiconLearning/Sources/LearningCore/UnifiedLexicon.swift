// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

/// 中文名稱和工程輸出的關聯；注音候選仍提交中文，不自動轉成符號。
public struct LexiconRelation: Codable, Hashable, Sendable {
    public var source_id: String
    public var target_id: String
    public var kind: String
    public init(source: String, target: String) {
        source_id = source; target_id = target; kind = "equivalent"
    }
}

/// SQLite 與本機復原快照共用的值資料；原 JSON 1.0 契約維持不變。
public struct UnifiedLexicon: Codable, Sendable, Equatable {
    public var document: LexiconDocument
    public var relations: [LexiconRelation]
    public init(document: LexiconDocument, relations: [LexiconRelation] = []) {
        self.document = document; self.relations = relations
    }
    public func validated() throws {
        _ = try document.exchangeData()
        let entries = Dictionary(document.entries.map { ($0.entry_id, $0) }, uniquingKeysWith: { first, _ in first })
        guard entries.count == document.entries.count, relations.count <= 40_000,
              Set(relations).count == relations.count else { throw LexiconError.invalid("詞條或關聯重複／超過上限") }
        for relation in relations {
            guard relation.kind == "equivalent", entries[relation.source_id]?.term_type == .zhPhrase,
                  let target = entries[relation.target_id], target.term_type != .zhPhrase else {
                throw LexiconError.invalid("中文別名關聯缺少有效端點")
            }
        }
    }
    public func encoded() throws -> Data {
        try validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var canonical = self
        canonical.relations.sort { ($0.source_id, $0.target_id, $0.kind) < ($1.source_id, $1.target_id, $1.kind) }
        return try encoder.encode(canonical)
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 16 * 1024 * 1024 else { throw LexiconError.invalid("詞庫超過 16 MiB") }
        try JSONPreflight.validate(data)
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validated(); return value
    }
    /// 選取匯出攜帶關聯端點，避免中文別名與工程輸出分離。
    public func selecting(_ ids: Set<String>) -> Self {
        var adjacency: [String: [String]] = [:]
        for r in relations {
            adjacency[r.source_id, default: []].append(r.target_id)
            adjacency[r.target_id, default: []].append(r.source_id)
        }
        var included = ids, pending = Array(ids), cursor = 0
        while cursor < pending.count {
            let key = pending[cursor]; cursor += 1
            for neighbor in adjacency[key] ?? [] where included.insert(neighbor).inserted {
                pending.append(neighbor)
            }
        }
        var doc = document; doc.entries = document.entries.filter { included.contains($0.entry_id) }
        return Self(document: doc, relations: relations.filter { included.contains($0.source_id) && included.contains($0.target_id) })
    }
}
