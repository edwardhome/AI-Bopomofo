// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

/// 詞義、名稱、讀音及實際輸入規則分開；同字不代表同義。
public struct LexiconConcept: Codable, Equatable, Sendable {
    public var id: String, definition: String, domain: String
    public init(id: String = CardGraph.newID(), definition: String, domain: String = "") { self.id = id; self.definition = definition; self.domain = domain }
}
public struct LexiconForm: Codable, Equatable, Sendable {
    public var id: String, text: String, kind: String
    public init(id: String = CardGraph.newID(), text: String, kind: String) { self.id = id; self.text = text; self.kind = kind }
}
public struct ConceptForm: Codable, Equatable, Sendable {
    public var id: String, concept_id: String, form_id: String, source: String
    public init(id: String = CardGraph.newID(), concept: String, form: String, source: String = "user") { self.id = id; concept_id = concept; form_id = form; self.source = source }
}
public struct CardReading: Codable, Equatable, Sendable {
    public var id: String, value: String
    public init(id: String = CardGraph.newID(), value: String) { self.id = id; self.value = value }
}
public struct FormReading: Codable, Equatable, Sendable {
    public var id: String, name_id: String, reading_id: String, source: String
    public init(id: String = CardGraph.newID(), name: String, reading: String, source: String = "user") { self.id = id; name_id = name; reading_id = reading; self.source = source }
}
public struct CardBinding: Codable, Equatable, Sendable {
    public var id: String, name_id: String, reading_id: String, code: String, term_type: TermType, source: String
    public init(id: String = CardGraph.newID(), name: String, reading: String = "", code: String, type: TermType, source: String = "user") {
        self.id = id; name_id = name; reading_id = reading; self.code = code; term_type = type; self.source = source
    }
}
public struct ConceptRelation: Codable, Equatable, Sendable {
    public var id: String, source_id: String, target_id: String, kind: String, source: String
    public init(id: String = CardGraph.newID(), from: String, to: String, kind: String, source: String = "user") {
        self.id = id; source_id = from; target_id = to; self.kind = kind; self.source = source
    }
}
/// 舊 equivalent 僅保存為舊關聯，不推論成同一詞義。
public struct LegacyCardLink: Codable, Equatable, Sendable {
    public var source_id: String, target_id: String
    public init(from: String, to: String) { source_id = from; target_id = to }
}
public struct CardOrigin: Codable, Equatable, Sendable {
    public var id: String, subject_id: String, source: String, reference: String
    public init(id: String = CardGraph.newID(), subject: String, source: String, reference: String = "") {
        self.id = id; subject_id = subject; self.source = source; self.reference = reference
    }
}
public struct CardGraph: Codable, Equatable, Sendable {
    public var origins: [CardOrigin] = []
    public var concepts: [LexiconConcept] = []
    public var forms: [LexiconForm] = []
    public var names: [ConceptForm] = []
    public var readings: [CardReading] = []
    public var pronunciations: [FormReading] = []
    public var bindings: [CardBinding] = []
    public var relations: [ConceptRelation] = []
    public var legacy_links: [LegacyCardLink] = []
    public init() {}
    public static func annotation(_ text: String) -> String {
        var result = "", length = 0
        for character in text { let count = String(character).utf16.count; if length + count > 80 { break }; result.append(character); length += count }
        // 單一極長組合字元無法放進舊註解欄時使用中性提示，原始 definition 不變。
        return result.isEmpty && !text.isEmpty ? "詞彙" : result
    }
    public static func newID() -> String { LexiconEntry.digest(Data(UUID().uuidString.utf8)) }
    public static func stableID(_ namespace: String, _ value: String) -> String { LexiconEntry.digest(Data((namespace + ":" + value).utf8)) }
    public static func validID(_ value: String) -> Bool { value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    public func validated() throws {
        func check(_ ids: [String], limit: Int = 20_000) throws {
            guard ids.count <= limit, Set(ids).count == ids.count, ids.allSatisfy(Self.validID) else { throw LexiconError.invalid("詞彙卡識別碼重複、不合法或超過上限") }
        }
        try check(concepts.map(\.id)); try check(forms.map(\.id)); try check(names.map(\.id), limit: 40_000)
        try check(readings.map(\.id)); try check(pronunciations.map(\.id), limit: 40_000)
        try check(bindings.map(\.id)); try check(relations.map(\.id), limit: 40_000)
        try check(origins.map(\.id), limit: 40_000)
        let allIDs = concepts.map(\.id) + forms.map(\.id) + names.map(\.id) + readings.map(\.id) + pronunciations.map(\.id) + bindings.map(\.id) + relations.map(\.id)
        let subjects = Set(allIDs)
        guard subjects.count == allIDs.count, origins.allSatisfy({ subjects.contains($0.subject_id) && LexiconEntry.safe($0.source, max: 512) && ($0.reference.isEmpty || LexiconEntry.safe($0.reference, max: 512)) }) else { throw LexiconError.invalid("來源紀錄缺少有效對象") }
        let cs = Set(concepts.map(\.id)), fs = Dictionary(uniqueKeysWithValues: forms.map { ($0.id, $0) })
        let ns = Dictionary(uniqueKeysWithValues: names.map { ($0.id, $0) }), rs = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, $0.value) })
        func safe(_ s: String, _ max: Int, empty: Bool = false) -> Bool { (empty && s.isEmpty) || LexiconEntry.safe(s, max: max) }
        guard concepts.allSatisfy({ safe($0.definition, 256) && safe($0.domain, 80, empty: true) }),
              forms.allSatisfy({ ["zh", "en", "abbreviation", "symbol"].contains($0.kind) && safe($0.text, 128) }),
              names.allSatisfy({ cs.contains($0.concept_id) && fs[$0.form_id] != nil && safe($0.source, 512) }),
              Set(names.map { $0.concept_id + ":" + $0.form_id }).count == names.count,
              readings.allSatisfy({ !$0.value.isEmpty && $0.value.count <= 128 && $0.value.split(separator: "-", omittingEmptySubsequences: false).allSatisfy { LexiconEntry.validSyllable(String($0)) } }),
              pronunciations.allSatisfy({ ns[$0.name_id].flatMap { fs[$0.form_id] }?.kind == "zh" && rs[$0.reading_id] != nil && safe($0.source, 512) }),
              Set(pronunciations.map { $0.name_id + ":" + $0.reading_id }).count == pronunciations.count,
              relations.allSatisfy({ cs.contains($0.source_id) && cs.contains($0.target_id) && $0.source_id != $0.target_id && ["broader", "related"].contains($0.kind) && safe($0.source, 512) }),
              Set(relations.map { $0.source_id + ":" + $0.target_id + ":" + $0.kind }).count == relations.count,
              legacy_links.count <= 40_000,
              legacy_links.allSatisfy({ cs.contains($0.source_id) && cs.contains($0.target_id) }),
              Set(legacy_links.map { $0.source_id + ":" + $0.target_id }).count == legacy_links.count else { throw LexiconError.invalid("詞彙卡包含不合法欄位、孤兒或重複關聯") }
        for p in pronunciations {
            guard let n = ns[p.name_id], let f = fs[n.form_id], let reading = rs[p.reading_id] else { throw LexiconError.invalid("讀音端點不存在") }
            try LexiconEntry(type: .zhPhrase, reading: reading, text: f.text).validated()
        }
        var identities = Set<String>()
        let pairs = Set(pronunciations.map { $0.name_id + ":" + $0.reading_id })
        for b in bindings {
            guard let n = ns[b.name_id], let f = fs[n.form_id], safe(b.source, 512), identities.insert(b.name_id + ":" + b.term_type.rawValue + ":" + b.code).inserted else { throw LexiconError.invalid("輸入規則缺少名稱或重複") }
            if b.term_type == .zhPhrase {
                guard f.kind == "zh", rs[b.reading_id] == b.code,
                      pairs.contains(n.id + ":" + b.reading_id) else { throw LexiconError.invalid("中文輸入規則須連到此詞義的已確認讀音") }
            } else {
                guard b.reading_id.isEmpty, f.kind != "zh" else { throw LexiconError.invalid("英文規則與中文讀音不可混用") }
                guard b.term_type != .english || f.kind == "en" else { throw LexiconError.invalid("英文類型與名稱不一致") }
            }
            try LexiconEntry(type: b.term_type, reading: b.code, text: f.text).validated()
        }
    }
    /// 引擎使用既有詞條介面；卡片保留身分與詞義，重複輸出不重複灌入引擎。
    public func projectedEntries() throws -> [LexiconEntry] {
        try validated()
        let ns = Dictionary(uniqueKeysWithValues: names.map { ($0.id, $0) }), fs = Dictionary(uniqueKeysWithValues: forms.map { ($0.id, $0.text) }), cs = Dictionary(uniqueKeysWithValues: concepts.map { ($0.id, $0) })
        var seen = Set<String>(), result: [LexiconEntry] = []
        for b in bindings {
            guard let n = ns[b.name_id], let text = fs[n.form_id], let c = cs[n.concept_id] else { continue }
            var e = LexiconEntry(type: b.term_type, reading: b.code, text: text, source: "lexicon_card", annotation: Self.annotation(c.definition))
            e.category = Self.annotation(c.domain); if e.category == "" { e.category = nil }
            if seen.insert(e.entry_id).inserted { result.append(e) }
        }
        return result
    }
    public static func migrating(_ value: UnifiedLexicon) throws -> Self {
        if let cards = value.cards { try cards.validated(); return cards }
        var g = Self()
        for e in value.document.entries {
            let c = stableID("concept", e.entry_id), f = stableID("form", e.entry_id), n = stableID("name", e.entry_id)
            g.concepts.append(.init(id: c, definition: e.annotation ?? e.text, domain: e.category ?? ""))
            g.forms.append(.init(id: f, text: e.text, kind: e.term_type == .zhPhrase ? "zh" : e.term_type == .english ? "en" : e.term_type == .unicode ? "symbol" : "abbreviation"))
            g.names.append(.init(id: n, concept: c, form: f, source: e.source))
            for (index, reference) in (e.sources ?? []).enumerated() {
                g.origins.append(.init(id: stableID("origin-\(index)", e.entry_id), subject: n, source: e.source, reference: reference))
            }
            if let suggestion = e.model_suggestion {
                g.origins.append(.init(id: stableID("model-origin", e.entry_id), subject: n, source: suggestion.model_id, reference: suggestion.reason))
            }
            var r = ""
            if e.term_type == .zhPhrase {
                r = stableID("reading", e.entry_id); g.readings.append(.init(id: r, value: e.reading))
                g.pronunciations.append(.init(id: stableID("pronunciation", e.entry_id), name: n, reading: r, source: e.source))
            }
            g.bindings.append(.init(id: stableID("binding", e.entry_id), name: n, reading: r, code: e.reading, type: e.term_type, source: e.source))
        }
        g.legacy_links = value.relations.map { .init(from: stableID("concept", $0.source_id), to: stableID("concept", $0.target_id)) }
        try g.validated(); return g
    }
    /// 匯入只按穩定 ID 合併；不同 ID 的同字詞保留，交給人工判斷。
    public func merging(_ incoming: Self) throws -> Self {
        func merge<T>(_ a: [T], _ b: [T], _ key: (T) -> String) -> [T] { var r = a; var indices = Dictionary(uniqueKeysWithValues: a.enumerated().map { (key($0.element), $0.offset) }); for x in b { if let i = indices[key(x)] { r[i] = x } else { indices[key(x)] = r.count; r.append(x) } }; return r }
        try validated(); try incoming.validated(); var g = self
        g.concepts = merge(concepts, incoming.concepts, { $0.id }); g.forms = merge(forms, incoming.forms, { $0.id }); g.names = merge(names, incoming.names, { $0.id })
        g.readings = merge(readings, incoming.readings, { $0.id }); g.pronunciations = merge(pronunciations, incoming.pronunciations, { $0.id }); g.bindings = merge(bindings, incoming.bindings, { $0.id }); g.relations = merge(relations, incoming.relations, { $0.id }); g.legacy_links = merge(legacy_links, incoming.legacy_links, { $0.source_id + ":" + $0.target_id })
        g.origins = merge(origins, incoming.origins, { $0.id })
        try g.validated(); return g
    }
    public func selecting(_ ids: Set<String>) -> Self {
        var g = self; g.concepts.removeAll { !ids.contains($0.id) }; g.names.removeAll { !ids.contains($0.concept_id) }
        let ns = Set(g.names.map(\.id)), fs = Set(g.names.map(\.form_id))
        g.forms.removeAll { !fs.contains($0.id) }; g.pronunciations.removeAll { !ns.contains($0.name_id) }; g.bindings.removeAll { !ns.contains($0.name_id) }
        let rs = Set(g.pronunciations.map(\.reading_id)); g.readings.removeAll { !rs.contains($0.id) }
        g.relations.removeAll { !ids.contains($0.source_id) || !ids.contains($0.target_id) }; g.legacy_links.removeAll { !ids.contains($0.source_id) || !ids.contains($0.target_id) }; g.pruneOrigins(); return g
    }
    public mutating func pruneOrigins() {
        let ids = Set(concepts.map(\.id) + forms.map(\.id) + names.map(\.id) + readings.map(\.id) + pronunciations.map(\.id) + bindings.map(\.id) + relations.map(\.id))
        origins.removeAll { !ids.contains($0.subject_id) }
    }
    public func exchange(version: String = "cards-" + UUID().uuidString) throws -> UnifiedLexicon {
        UnifiedLexicon(document: LexiconDocument(version: version, entries: try projectedEntries()), cards: self)
    }
}
