// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

extension CardGraph {
    /// 編輯共享名稱時採用 copy-on-write，不修改其他詞義的名稱或讀音。
    public mutating func editName(concept: String, nameID: String? = nil, text: String, kind: String,
                                  codes: [String], readings values: [String], source: String = "user") throws {
        guard concepts.contains(where: { $0.id == concept }) else { throw LexiconError.invalid("詞義不存在") }
        var next = self
        let old = nameID.flatMap { id in names.first { $0.id == id && $0.concept_id == concept } }
        if nameID != nil && old == nil { throw LexiconError.invalid("名稱已變更") }
        let nID = old?.id ?? Self.newID()
        let oldBindings = bindings.filter { $0.name_id == nID }, oldPronunciations = pronunciations.filter { $0.name_id == nID }
        let formID: String
        if let old, names.filter({ $0.form_id == old.form_id }).count == 1 { formID = old.form_id; next.forms.removeAll { $0.id == formID } }
        else { formID = Self.newID() }
        next.forms.append(.init(id: formID, text: text, kind: kind))
        next.names.removeAll { $0.id == nID }; next.names.append(.init(id: nID, concept: concept, form: formID, source: source))
        next.bindings.removeAll { $0.name_id == nID }; next.pronunciations.removeAll { $0.name_id == nID }
        if kind == "zh" {
            guard codes.isEmpty else { throw LexiconError.invalid("中文請使用注音讀音，不設定英文輸入碼") }
            for value in values {
                let r = next.readings.first { $0.value == value } ?? CardReading(value: value)
                if !next.readings.contains(where: { $0.id == r.id }) { next.readings.append(r) }
                next.pronunciations.append(.init(id: oldPronunciations.first { $0.reading_id == r.id }?.id ?? Self.newID(), name: nID, reading: r.id, source: source))
                next.bindings.append(.init(id: oldBindings.first { $0.code == value }?.id ?? Self.newID(), name: nID, reading: r.id, code: value, type: .zhPhrase, source: source))
            }
        } else {
            guard values.isEmpty else { throw LexiconError.invalid("注音只屬於中文名稱") }
            let type: TermType = kind == "en" ? .english : kind == "symbol" ? .unicode : .technical
            for code in codes { next.bindings.append(.init(id: oldBindings.first { $0.code == code }?.id ?? Self.newID(), name: nID, code: code, type: type, source: source)) }
        }
        next.pruneUnused(); try next.validated(); self = next
    }
    public mutating func removeName(_ id: String) throws {
        var next = self; next.names.removeAll { $0.id == id }; next.bindings.removeAll { $0.name_id == id }; next.pronunciations.removeAll { $0.name_id == id }
        next.pruneUnused(); try next.validated(); self = next
    }
    private mutating func pruneUnused() {
        let fs = Set(names.map(\.form_id)), rs = Set(pronunciations.map(\.reading_id))
        forms.removeAll { !fs.contains($0.id) }; readings.removeAll { !rs.contains($0.id) }; pruneOrigins()
    }
    public mutating func mergeConcept(_ from: String, into to: String) throws {
        guard from != to, concepts.contains(where: { $0.id == from }), concepts.contains(where: { $0.id == to }) else { throw LexiconError.invalid("合併詞義不存在") }
        var next = self
        // 同一 form 已屬於目標詞義時，合併 membership 並重接讀音、輸入碼與來源。
        for name in names where name.concept_id == from {
            if let target = next.names.first(where: { $0.concept_id == to && $0.form_id == name.form_id }) {
                for i in next.bindings.indices where next.bindings[i].name_id == name.id { next.bindings[i].name_id = target.id }
                for i in next.pronunciations.indices where next.pronunciations[i].name_id == name.id { next.pronunciations[i].name_id = target.id }
                for i in next.origins.indices where next.origins[i].subject_id == name.id { next.origins[i].subject_id = target.id }
                next.names.removeAll { $0.id == name.id }
            } else if let i = next.names.firstIndex(where: { $0.id == name.id }) { next.names[i].concept_id = to }
        }
        var pronunciationKeys = Set<String>(), bindingKeys = Set<String>()
        next.pronunciations.removeAll { !pronunciationKeys.insert($0.name_id + ":" + $0.reading_id).inserted }
        next.bindings.removeAll { !bindingKeys.insert($0.name_id + ":" + $0.term_type.rawValue + ":" + $0.code).inserted }
        for i in next.origins.indices where next.origins[i].subject_id == from { next.origins[i].subject_id = to }
        next.concepts.removeAll { $0.id == from }
        for i in next.relations.indices { if next.relations[i].source_id == from { next.relations[i].source_id = to }; if next.relations[i].target_id == from { next.relations[i].target_id = to } }
        next.relations.removeAll { $0.source_id == $0.target_id }
        var seen = Set<String>(); next.relations.removeAll { !seen.insert($0.source_id + ":" + $0.target_id + ":" + $0.kind).inserted }
        // 已確認合併後不再保留指向消失詞義的舊關聯；核准前預覽完整差異。
        next.legacy_links.removeAll { $0.source_id == from || $0.target_id == from }
        next.pruneOrigins(); try next.validated(); self = next
    }
}

/// 一次提議一項語意操作。新增名稱的讀音與輸入規則屬同一項，避免核准孤兒資料。
public struct CardChange: Codable, Equatable, Sendable {
    public var id: String, operation: String, concept_id: String, target_id: String
    public var text: String, kind: String, reading: String, code: String, reason: String
    public init(operation: String, concept: String, target: String = "", text: String = "", kind: String = "", reading: String = "", code: String = "", reason: String) {
        id = CardGraph.newID(); self.operation = operation; concept_id = concept; target_id = target
        self.text = text; self.kind = kind; self.reading = reading; self.code = code; self.reason = reason
    }
    public func applying(to graph: CardGraph, source: String = "apple_fm") throws -> CardGraph {
        guard CardGraph.validID(id), graph.concepts.contains(where: { $0.id == concept_id }), LexiconEntry.safe(reason, max: 512),
              [target_id, text, kind, reading, code].allSatisfy({ $0.isEmpty || LexiconEntry.safe($0, max: 512) }) else { throw LexiconError.invalid("提議欄位或目標不合法") }
        var next = graph
        switch operation {
        case "set_definition":
            guard let i = next.concepts.firstIndex(where: { $0.id == concept_id }) else { throw LexiconError.invalid("詞義不存在") }; next.concepts[i].definition = text
        case "add_name":
            try next.editName(concept: concept_id, text: text, kind: kind, codes: code.isEmpty ? [] : [code], readings: reading.isEmpty ? [] : [reading], source: source)
        case "link":
            next.relations.append(.init(id: id, from: concept_id, to: target_id, kind: kind, source: source))
        case "merge": try next.mergeConcept(concept_id, into: target_id)
        case "split_name":
            guard let i = next.names.firstIndex(where: { $0.id == target_id && $0.concept_id == concept_id }) else { throw LexiconError.invalid("拆分名稱不存在") }
            let c = LexiconConcept(id: id, definition: text); next.concepts.append(c); next.names[i].concept_id = c.id
        default: throw LexiconError.invalid("不支援的詞彙卡操作")
        }
        // 接受模型提議後仍保留推測來源與理由，不冒充查證資料。
        let subject = operation == "merge" ? target_id : operation == "split_name" ? id : concept_id
        next.origins.append(.init(id: id == subject ? CardGraph.stableID("origin", id) : id, subject: subject, source: source, reference: reason))
        next.pruneOrigins(); try next.validated(); return next
    }
}
public struct CardProposalBatch: Codable, Sendable {
    public var graph_digest: String?
    public var base_revision: String
    public var changes: [CardChange]
    public init(base: String, changes: [CardChange]) { graph_digest = nil; base_revision = base; self.changes = changes }
    public func applying(selected: Set<String>, to graph: CardGraph, revision: String) throws -> CardGraph {
        guard revision == base_revision, changes.count <= 32, Set(changes.map(\.id)).count == changes.count,
              selected.isSubset(of: Set(changes.map(\.id))) else { throw LexiconError.invalid("提議已過期或選取不合法") }
        if let graph_digest, graph_digest != (try graph.digest()) { throw LexiconError.invalid("詞彙卡草稿已變更，請重新整理") }
        var next = graph
        for change in changes where selected.contains(change.id) { next = try change.applying(to: next) }
        return next
    }
}

public struct CardReviewSession: Codable, Sendable {
    public var graph: CardGraph
    public var proposal: CardProposalBatch
    public init(graph: CardGraph, proposal: CardProposalBatch) { self.graph = graph; self.proposal = proposal }
}
extension CardGraph {
    public func digest() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return LexiconEntry.digest(try encoder.encode(self))
    }
}
