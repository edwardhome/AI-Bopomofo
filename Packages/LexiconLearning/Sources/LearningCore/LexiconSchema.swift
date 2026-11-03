// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import CryptoKit

public enum LexiconError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let s) = self { return s }; return nil }
}
public enum TermType: String, Codable, Sendable { case zhPhrase = "zh_phrase", english = "english_term", technical = "technical_alias", unicode = "unicode_mapping" }
public enum ReviewStatus: String, Codable, Sendable { case observed, proposed, approved, rejected }
public struct Usage: Codable, Sendable, Equatable {
    public var commit_count: Int64
    public var manual_selection_count: Int64
    public init(commits: Int64 = 0, manual: Int64 = 0) { commit_count = commits; manual_selection_count = manual }
}
public struct Review: Codable, Sendable, Equatable {
    public var status: ReviewStatus
    public var user_confirmed: Bool
    public init(_ status: ReviewStatus = .observed, confirmed: Bool = false) { self.status = status; user_confirmed = confirmed }
}
public struct ModelSuggestion: Codable, Sendable, Equatable {
    public var suggestion_id: String
    public var origin_entry_id: String
    public var reason: String
    public var model_id: String
    public var model_version: String?
    public var suggested_annotation: String?
    public var suggested_category: String?
    public init(origin: String, reason: String, model: String, version: String? = nil) {
        suggestion_id = UUID().uuidString; origin_entry_id = origin; self.reason = reason
        model_id = model; model_version = version
    }
}
public struct LexiconEntry: Codable, Sendable, Equatable {
    public var entry_id: String
    public var term_type: TermType
    public var reading: String
    public var text: String
    public var source: String
    public var usage: Usage?
    public var review: Review
    public var model_suggestion: ModelSuggestion?
    public var category: String?
    public var annotation: String?
    public var sources: [String]?
    public var policy: String?
    public init(type: TermType, reading: String, text: String, source: String = "user_observation",
                review: Review = Review(), annotation: String? = nil) {
        term_type = type; self.reading = reading; self.text = text; self.source = source
        self.review = review; self.annotation = annotation
        entry_id = Self.key(type: type, reading: reading, text: text)
    }
    /// 長度前綴避免分隔符碰撞；輸出 UTF-8 位元組及大小寫不做相容性正規化。
    public static func key(type: TermType, reading: String, text: String) -> String {
        var bytes = Data()
        for value in [type.rawValue, reading, text] {
            let data = Data(value.utf8); var length = UInt64(data.count).bigEndian
            withUnsafeBytes(of: &length) { bytes.append(contentsOf: $0) }; bytes.append(data)
        }
        return digest(bytes)
    }
    public static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public func validated() throws {
        guard entry_id == Self.key(type: term_type, reading: reading, text: text),
              Self.safe(text, max: 128), Self.safe(source, max: 80),
              annotation.map({ Self.safe($0, max: 80) }) ?? true,
              category.map({ Self.safe($0, max: 80) }) ?? true,
              sources.map({ $0.count <= 16 && $0.allSatisfy { Self.safe($0, max: 512) } }) ?? true,
              policy == nil || policy == "candidate_only",
              usage.map({ $0.commit_count >= 0 && $0.manual_selection_count >= 0 && $0.manual_selection_count <= $0.commit_count }) ?? true
        else { throw LexiconError.invalid("詞條身分、欄位或優先度不合法（第一版只支援 candidate_only）") }
        if term_type == .zhPhrase {
            let syllables = reading.split(separator: "-", omittingEmptySubsequences: false)
            guard (1...8).contains(syllables.count), syllables.count == text.unicodeScalars.count,
                  text.unicodeScalars.allSatisfy({ (0x3400...0x9fff).contains($0.value) || (0x20000...0x323af).contains($0.value) }),
                  syllables.allSatisfy({ Self.validSyllable(String($0)) }) else {
                throw LexiconError.invalid("中文詞須為一至八音節，字與標準注音須逐字對應")
            }
        } else {
            guard (2...64).contains(reading.utf8.count), reading.utf8.allSatisfy({ (33...126).contains($0) }) else {
                throw LexiconError.invalid("英文及技術輸入碼須為 2 至 64 個無空白 ASCII 字元")
            }
        }
        if let s = model_suggestion {
            guard Self.safe(s.suggestion_id, max: 80), s.origin_entry_id.count == 64,
                  Self.safe(s.reason, max: 512), Self.safe(s.model_id, max: 128),
                  s.model_version.map({ Self.safe($0, max: 128) }) ?? true,
                  s.suggested_annotation.map({ Self.safe($0, max: 80) }) ?? true,
                  s.suggested_category.map({ Self.safe($0, max: 80) }) ?? true else { throw LexiconError.invalid("模型建議欄位不合法") }
        }
    }
    public static func safe(_ s: String, max: Int) -> Bool {
        !s.isEmpty && s.utf16.count <= max && s.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0)
                && $0.properties.generalCategory != .format
        }
    }
    public static func validSyllable(_ s: String) -> Bool {
        guard s.unicodeScalars.contains(where: { (0x3105...0x3129).contains($0.value) }) else { return false }
        return s.range(of: "^[ㄅ-ㄙ]?[ㄧㄨㄩ]?[ㄚ-ㄦ]?[ˊˇˋ˙]?$", options: .regularExpression) != nil
    }
}
public struct LexiconDocument: Codable, Sendable, Equatable {
    public var format = "ai-bopomofo.lexicon"
    public var schema_version = "1.0.0"
    public var document_type: String
    public var dictionary_version: String
    public var entries: [LexiconEntry]
    public init(type: String = "review", version: String = UUID().uuidString, entries: [LexiconEntry]) {
        document_type = type; dictionary_version = version; self.entries = entries
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 8 * 1024 * 1024 else { throw LexiconError.invalid("JSON 超過 8 MiB") }
        try JSONPreflight.validate(data)
        try validateKeys(data)
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.format == "ai-bopomofo.lexicon", result.schema_version == "1.0.0",
              ["review", "approved"].contains(result.document_type),
              LexiconEntry.safe(result.dictionary_version, max: 80), result.entries.count <= 20_000 else {
            throw LexiconError.invalid("不支援的格式、版本或過多詞條")
        }
        for entry in result.entries { try entry.validated() }
        return result
    }
    private static func validateKeys(_ data: Data) throws {
        func check(_ object: Any?, allowed: Set<String>) throws {
            guard let object = object as? [String: Any] else { return }
            guard Set(object.keys).isSubset(of: allowed) else { throw LexiconError.invalid("JSON 含不支援的欄位") }
        }
        let root = try JSONSerialization.jsonObject(with: data)
        try check(root, allowed: ["format", "schema_version", "document_type", "dictionary_version", "entries"])
        for entry in (root as? [String: Any])?["entries"] as? [[String: Any]] ?? [] {
            try check(entry, allowed: ["entry_id", "term_type", "reading", "text", "source", "usage", "review", "model_suggestion", "category", "annotation", "sources", "policy"])
            try check(entry["usage"], allowed: ["commit_count", "manual_selection_count"])
            try check(entry["review"], allowed: ["status", "user_confirmed"])
            try check(entry["model_suggestion"], allowed: ["suggestion_id", "origin_entry_id", "reason", "model_id", "model_version", "suggested_annotation", "suggested_category"])
        }
    }
    /// 相同身分的原始觀察保留事實欄位；推測提示放在獨立 model_suggestion 中。
    public static func mergedReviewEntries(_ values: [LexiconEntry]) -> [LexiconEntry] {
        var result: [LexiconEntry] = []; var index: [String: Int] = [:]
        for entry in values.sorted(by: { ($0.model_suggestion == nil ? 0 : 1) < ($1.model_suggestion == nil ? 0 : 1) }) {
            if let i = index[entry.entry_id] {
                if let suggestion = entry.model_suggestion { result[i].model_suggestion = suggestion }
            } else { index[entry.entry_id] = result.count; result.append(entry) }
        }
        return result
    }
    /// 匯出檔也遵循匯入限制，避免產生無法重新校對匯回的交換檔。
    public func exchangeData() throws -> Data {
        let data = try encoded()
        _ = try Self.decode(data)
        return data
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// JSONDecoder 會默默接受重複欄位，先做有界結構掃描，避免審核與部署看到不同值。
public enum JSONPreflight {
    public static func validate(_ data: Data) throws {
        var scanner = Scanner(bytes: Array(data)); try scanner.value(depth: 0); scanner.space()
        guard scanner.i == scanner.bytes.count else { throw LexiconError.invalid("JSON 尾端有多餘資料") }
    }
    struct Scanner {
        var bytes: [UInt8]; var i = 0
        mutating func space() { while i < bytes.count && [9, 10, 13, 32].contains(bytes[i]) { i += 1 } }
        mutating func require(_ b: UInt8) throws { space(); guard i < bytes.count && bytes[i] == b else { throw LexiconError.invalid("JSON 結構錯誤") }; i += 1 }
        mutating func string() throws -> String {
            space(); let start = i; try require(34)
            while i < bytes.count {
                let b = bytes[i]; i += 1
                if b == 92 { guard i < bytes.count else { break }; i += 1 }
                else if b == 34 { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<i])) }
            }
            throw LexiconError.invalid("JSON 字串截斷")
        }
        mutating func value(depth: Int) throws {
            guard depth <= 12 else { throw LexiconError.invalid("JSON 巢狀超過 12 層") }
            space(); guard i < bytes.count else { throw LexiconError.invalid("JSON 截斷") }
            if bytes[i] == 34 { _ = try string(); return }
            if bytes[i] == 123 || bytes[i] == 91 {
                let object = bytes[i] == 123, end: UInt8 = object ? 125 : 93
                i += 1; space(); if i < bytes.count && bytes[i] == end { i += 1; return }
                var keys = Set<String>()
                while true {
                    if object { let key = try string(); guard keys.insert(key).inserted else { throw LexiconError.invalid("JSON 重複欄位：\(key)") }; try require(58) }
                    try value(depth: depth + 1); space()
                    guard i < bytes.count else { throw LexiconError.invalid("JSON 截斷") }
                    if bytes[i] == end { i += 1; return }; try require(44)
                }
            }
            let start = i
            while i < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[i]) { i += 1 }
            guard i > start else { throw LexiconError.invalid("JSON 值不合法") }
        }
    }
}
