// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import LearningCore

public struct OrganizerProposal: Codable, Sendable {
    public let origin: String
    public let type: TermType
    public let reading: String
    public let text: String
    public let annotation: String
    public let category: String
    public let reason: String
    public init(origin: String, type: TermType, reading: String, text: String, annotation: String, category: String, reason: String) {
        self.origin = origin; self.type = type; self.reading = reading; self.text = text
        self.annotation = annotation; self.category = category; self.reason = reason
    }
}
public enum SuggestionValidator {
    public static func validate(_ data: Data, originals: [LexiconEntry]) throws -> [LexiconEntry] {
        guard data.count <= 65536, originals.count <= 16 else { throw LexiconError.invalid("整理批次超過限制") }
        let proposals = try JSONDecoder().decode([OrganizerProposal].self, from: data)
        guard proposals.count <= 32 else { throw LexiconError.invalid("模型建議過多") }
        let origins = Set(originals.map(\.entry_id)); var seen = Set<String>(); var result: [LexiconEntry] = []
        for p in proposals {
            guard origins.contains(p.origin) else { throw LexiconError.invalid("模型引用不存在的觀察資料") }
            var e = LexiconEntry(type: p.type, reading: p.reading, text: p.text, source: "apple_fm",
                                 review: Review(.proposed), annotation: p.annotation)
            e.category = p.category
            e.model_suggestion = ModelSuggestion(origin: p.origin, reason: p.reason, model: "apple.foundationmodels.ondevice")
            try e.validated()
            if seen.insert(e.entry_id).inserted { result.append(e) }
        }
        return result
    }
}

/// 共享協調器使用的整理世代；取消後的延遲結果即使有效也不能寫入資料庫。
public struct OrganizerGate: Sendable {
    public private(set) var generation: UInt64 = 0
    public private(set) var running = false
    public private(set) var lastStarted: Date = .distantPast
    public init() {}
    public mutating func begin(now: Date, idleSeconds: Double, secure: Bool, enabled: Bool,
                               suitable: Bool, pending: Bool) -> UInt64? {
        guard !running, enabled, suitable, pending, !secure, idleSeconds >= 30,
              now.timeIntervalSince(lastStarted) >= 60 else { return nil }
        generation &+= 1; running = true; lastStarted = now; return generation
    }
    public mutating func cancel() { generation &+= 1 }
    public mutating func finish(_ id: UInt64) -> Bool { running = false; return id == generation }
}
