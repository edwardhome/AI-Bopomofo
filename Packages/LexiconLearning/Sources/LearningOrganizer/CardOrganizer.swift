// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import LearningCore

public struct CardOrganizationRequest: Codable, Sendable {
    public var base_revision: String
    public var graph: CardGraph
    public init(revision: String, graph: CardGraph) { base_revision = revision; self.graph = graph }
    public func encoded() throws -> Data {
        try graph.validated()
        guard (1...16).contains(graph.concepts.count) else { throw LexiconError.invalid("每次請選取一至十六張詞彙卡") }
        let data = try JSONEncoder().encode(self)
        guard data.count <= 65_536 else { throw LexiconError.invalid("模型整理資料超過上限，請減少選取") }; return data
    }
    public func validateResponse(_ data: Data) throws -> CardProposalBatch {
        guard data.count <= 65_536 else { throw LexiconError.invalid("模型回應超過上限") }
        try JSONPreflight.validate(data)
        let changes = try JSONDecoder().decode([CardChange].self, from: data)
        guard changes.count <= 8, Set(changes.map(\.id)).count == changes.count else { throw LexiconError.invalid("模型提議過多或重複") }
        // 每個提議必須可獨立核准，不允許依賴前一個模型提議產生的識別碼。
        for change in changes { _ = try change.applying(to: graph) }
        return CardProposalBatch(base: base_revision, changes: changes)
    }
}
