// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

/// 只解析使用者主動選擇匯入的文字快照，不讀檔、不猜讀音、不改原檔。
public struct LegacyTermImport: Sendable {
    public let entries: [LexiconEntry]
    public let rejectedLines: [Int]
    public let excludedCount: Int
    public init(phrases: String, excluded: String = "") throws {
        guard phrases.utf8.count <= 4 * 1024 * 1024, excluded.utf8.count <= 4 * 1024 * 1024 else {
            throw LexiconError.invalid("舊詞庫超過 4 MiB")
        }
        func fields(_ line: Substring) -> [String] {
            line.split(whereSeparator: \.isWhitespace).map(String.init)
        }
        let exclusions = Set(excluded.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let f = fields(line)
            return f.count >= 2 && !f[0].hasPrefix("#") ? f[0] + "\t" + f[1] : nil
        })
        var values: [LexiconEntry] = [], rejected: [Int] = [], seen = Set<String>(), excludedCount = 0
        for (offset, line) in phrases.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let f = fields(line)
            if f.isEmpty || f[0].hasPrefix("#") { continue }
            guard f.count >= 2 else { rejected.append(offset + 1); continue }
            if exclusions.contains(f[0] + "\t" + f[1]) { excludedCount += 1; continue }
            let english = f[1].hasPrefix("_english_")
            let code = english ? String(f[1].dropFirst("_english_".count)) : f[1]
            let entry = LexiconEntry(type: english ? .english : .zhPhrase, reading: code, text: f[0], source: "legacy-user")
            do { try entry.validated() } catch { rejected.append(offset + 1); continue }
            if seen.insert(entry.entry_id).inserted { values.append(entry) }
        }
        guard values.count <= 20_000 else { throw LexiconError.invalid("舊詞庫超過 20,000 詞") }
        entries = values; rejectedLines = rejected; self.excludedCount = excludedCount
    }
}
