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

/// 只包含已通過驗證的獨立建議；拒絕項只保留項次與固定原因，不傳遞非法模型內容。
public struct CardProposalRejection: Codable, Sendable, Equatable {
    public enum Reason: String, Codable, Sendable { case reading, reference, fields }
    public var index: Int
    public var reason: Reason
    public init(index: Int, reason: Reason) { self.index = index; self.reason = reason }
}
public struct CardOrganizationResponse: Codable, Sendable {
    public var changes: [CardChange]
    public var rejected: [CardProposalRejection]
    public init(changes: [CardChange], rejected: [CardProposalRejection]) { self.changes = changes; self.rejected = rejected }
}
extension CardOrganizationRequest {
    public func validateServiceResponse(_ data: Data) throws -> CardOrganizationResponse {
        guard data.count <= 65_536 else { throw LexiconError.invalid("模型回應超過上限") }
        try JSONPreflight.validate(data)
        let response = try JSONDecoder().decode(CardOrganizationResponse.self, from: data)
        let total = response.changes.count + response.rejected.count
        guard total <= 4, Set(response.rejected.map(\.index)).count == response.rejected.count,
              response.rejected.allSatisfy({ (1...max(1,total)).contains($0.index) }) else { throw LexiconError.invalid("模型回應項次不合法") }
        _ = try validateResponse(JSONEncoder().encode(response.changes))
        return response
    }
}
