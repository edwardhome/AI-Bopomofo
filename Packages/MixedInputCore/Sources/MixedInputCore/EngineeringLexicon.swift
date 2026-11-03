// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

/// 顯示註解不屬於輸出文字；保留來源供候選排序與預測仲裁使用。
public struct TechnicalCandidate: Sendable, Equatable {
    public enum Source: Sendable { case original, technical, engineering }
    public let text: String
    public let annotation: String?
    public let source: Source

    public init(text: String, annotation: String? = nil, source: Source) {
        self.text = text; self.annotation = annotation; self.source = source
    }
}

public struct EngineeringTerm: Codable, Sendable {
    public let id: String
    public let category: String
    public let aliases: [String]
    /// 已校對的輸出順序：Unicode 優先，再列 ASCII；不做相容性正規化。
    public let outputs: [String]
    public let annotation: String
    public let sources: [String]
}

public struct EngineeringLexicon: Sendable {
    public let terms: [EngineeringTerm]
    private let exactIndex: [String: [Int]]
    private let prefixIndex: [String: [Int]]

    /// Swift 靜態值只初始化一次。資源失效時回退空詞庫，不阻擋正常輸入。
    public static let bundled: EngineeringLexicon = {
        guard let url = Bundle.module.url(forResource: "engineering-terms", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return EngineeringLexicon(data: Data()) }
        return EngineeringLexicon(data: data)
    }()

    public init(data: Data) {
        struct Catalog: Decodable { let version: Int; let terms: [EngineeringTerm] }
        let catalog = data.count <= 1_048_576 ? try? JSONDecoder().decode(Catalog.self, from: data) : nil
        let decoded = catalog?.terms ?? []
        let valid = catalog?.version == 1 && decoded.count <= 1000
            && Set(decoded.map(\.id)).count == decoded.count
            && decoded.allSatisfy { term in
                !term.id.isEmpty && !term.category.isEmpty && !term.annotation.isEmpty
                && term.annotation.count <= 80 && !term.sources.isEmpty
                && !term.aliases.isEmpty && term.aliases.count <= 16
                && term.aliases.allSatisfy { alias in
                    (2...64).contains(alias.utf8.count)
                    && alias.utf8.allSatisfy { (33...126).contains($0) }
                }
                && !term.outputs.isEmpty && term.outputs.count <= 8
                && term.outputs.allSatisfy { output in
                    !output.isEmpty && output.utf16.count <= 128
                    && output.unicodeScalars.allSatisfy {
                        !CharacterSet.controlCharacters.contains($0)
                        && !CharacterSet.newlines.contains($0)
                        && $0.properties.generalCategory != .format
                    }
                }
            }
        terms = valid ? decoded : []
        var exact: [String: [Int]] = [:], prefixes: [String: [Int]] = [:]
        for (index, term) in terms.enumerated() {
            for alias in Set(term.aliases.map { $0.lowercased() }) {
                exact[alias, default: []].append(index)
                if alias.count >= 3 {
                    for length in 3...alias.count {
                        prefixes[String(alias.prefix(length)), default: []].append(index)
                    }
                }
            }
        }
        exactIndex = exact.mapValues { Array(Set($0)).sorted() }
        prefixIndex = prefixes.mapValues { Array(Set($0)).sorted() }
    }

    /// 只查詢整個 ASCII 組字；兩字元只能完整吻合，三字元起才展開前綴。
    public func matches(_ query: String) -> (exact: [TechnicalCandidate], prefix: [TechnicalCandidate]) {
        guard query.utf8.count >= 2, query.utf8.allSatisfy({ (33...126).contains($0) }) else {
            return ([], [])
        }
        let lower = query.lowercased()
        let exact = exactIndex[lower] ?? []
        let exactSet = Set(exact)
        let prefix = (prefixIndex[lower] ?? []).filter { !exactSet.contains($0) }
        func candidates(_ indices: [Int], exactMatch: Bool) -> [TechnicalCandidate] {
            indices.sorted { left, right in
                func caseMatches(_ index: Int) -> Bool {
                    terms[index].aliases.contains { exactMatch ? $0 == query : $0.hasPrefix(query) }
                }
                let l = caseMatches(left), r = caseMatches(right)
                return l == r ? left < right : l
            }.flatMap { index in
                terms[index].outputs.map {
                    TechnicalCandidate(text: $0, annotation: terms[index].annotation, source: .engineering)
                }
            }
        }
        return (candidates(exact, exactMatch: true), candidates(prefix, exactMatch: false))
    }
}
