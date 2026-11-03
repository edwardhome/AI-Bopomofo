// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

public struct TechnicalLexicon: Sendable {
    public static let builtins = [
        "FPGA", "Vivado", "SystemVerilog", "Verilog", "VHDL", "Python", "Flask", "PySide6",
        "GitHub", "Git", "Codex", "McBopomofo", "InputMethodKit", "CoreML", "Swift", "Xcode",
        "MacBook", "Apple", "RTX", "branch", "module"
    ]
    public let words: [String]
    private let engineering: EngineeringLexicon?
    private var approved: EngineeringLexicon? = nil
    public func withApproved(_ lexicon: EngineeringLexicon?) -> Self {
        var copy = self; copy.approved = lexicon; return copy
    }

    public init(custom: [String] = [], engineeringEnabled: Bool = true,
                engineering: EngineeringLexicon = .bundled) {
        self.engineering = engineeringEnabled ? engineering : nil
        words = Array(Set(Self.builtins + custom.prefix(5000).filter(Self.isValid))).sorted()
    }

    public static func isValid(_ word: String) -> Bool {
        !word.isEmpty && !word.hasPrefix("#") && word.utf8.count <= 64
        && word.utf8.contains(where: { (65...90).contains($0) || (97...122).contains($0) })
        && word.utf8.allSatisfy { (33...126).contains($0) }
    }

    /// Read only explicit English entries from the existing McBopomofo user phrase format.
    public static func userTerms(from phrases: String) -> [String] {
        var terms: [String] = []
        for line in phrases.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, !fields[0].hasPrefix("#"),
                  fields[1].hasPrefix("_english_"), isValid(String(fields[0])) else { continue }
            terms.append(String(fields[0]))
            if terms.count == 5000 { break }
        }
        return terms
    }

    public func completions(for prefix: String) -> [String] {
        candidateItems(for: prefix).map(\.text)
    }

    public func candidateItems(for prefix: String) -> [TechnicalCandidate] {
        guard prefix.count >= 2, !prefix.contains(where: \.isWhitespace) else { return [] }
        let lower = prefix.lowercased()
        let matches = engineering?.matches(prefix) ?? (exact: [], prefix: [])
        let additional = approved?.matches(prefix) ?? (exact: [], prefix: [])
        func approvedItems(_ items: [TechnicalCandidate]) -> [TechnicalCandidate] {
            items.map { TechnicalCandidate(text: $0.text, annotation: $0.annotation, source: .approved) }
        }
        let legacy = words.lazy.filter { $0.lowercased().hasPrefix(lower) && $0 != prefix }
            .prefix(8).map { TechnicalCandidate(text: $0, source: .technical) }
        var seen: Set<String> = [prefix]
        return Array((matches.exact + approvedItems(additional.exact) + legacy + matches.prefix + approvedItems(additional.prefix)).filter { seen.insert($0.text).inserted }.prefix(8))
    }

}

public struct ASCIIComposition: Sendable {
    public let raw: String
    public let cursor: Int
    public let selectedIndex: Int
    public let candidates: [String]
    public let candidateItems: [TechnicalCandidate]
    public var hasEngineeringCandidates: Bool { candidateItems.contains { $0.source == .engineering || $0.source == .approved } }

    public init(raw: String = "", cursor: Int? = nil, selectedIndex: Int = 0,
                lexicon: TechnicalLexicon = TechnicalLexicon()) {
        // 外部鍵盤／預測文字維持既有 ASCII 規則，不能藉此注入任意 Unicode。
        let text = String(raw.unicodeScalars.filter { (32...126).contains($0.value) || $0.value == 176 }.prefix(256))
        self.init(acceptedText: text, cursor: cursor, selectedIndex: selectedIndex, lexicon: lexicon)
    }

    /// 僅由已驗證候選或既有組字編輯進入；保留其 Unicode，不重新過濾下標。
    private init(acceptedText text: String, cursor: Int?, selectedIndex: Int = 0, lexicon: TechnicalLexicon) {
        raw = text
        let requested = min(max(cursor ?? text.utf16.count, 0), text.utf16.count)
        self.cursor = Self.boundaries(text).last(where: { $0 <= requested }) ?? 0
        candidateItems = text.isEmpty ? [] : [TechnicalCandidate(text: text, source: .original)]
            + (self.cursor == text.utf16.count ? lexicon.candidateItems(for: text) : [])
        candidates = candidateItems.map(\.text)
        self.selectedIndex = candidates.indices.contains(selectedIndex) ? selectedIndex : 0
    }

    /// 更新偏好時保留原文與游標，清除候選選取，不把預覽文字當成已接受文字。
    public func rebuilding(lexicon: TechnicalLexicon) -> ASCIIComposition {
        Self(acceptedText: raw, cursor: cursor, lexicon: lexicon)
    }

    private static func boundaries(_ text: String) -> [Int] {
        var offsets = [0], position = 0
        for character in text {
            position += String(character).utf16.count
            offsets.append(position)
        }
        return offsets
    }

    public var display: String { candidates.isEmpty ? raw : candidates[selectedIndex] }
    public var displayCursor: Int { selectedIndex == 0 ? cursor : display.utf16.count }

    public enum Action: Sendable {
        case insert(String), backspace, delete, left, right, home, end, cycle(Int), select(Int), escape, enter, shortcut
    }
    public enum Result: Sendable {
        case updated(ASCIIComposition), commit(String), cancel, passThrough(String), rejected
    }

    public func applying(_ action: Action, lexicon: TechnicalLexicon = TechnicalLexicon()) -> Result {
        func updated(_ text: String, _ cursor: Int, selected: Int = 0) -> Result {
            .updated(ASCIIComposition(acceptedText: text, cursor: cursor, selectedIndex: selected, lexicon: lexicon))
        }
        let text = display as NSString
        let position = displayCursor
        let boundaries = Self.boundaries(display)
        let previous = boundaries.last(where: { $0 < position }) ?? 0
        let next = boundaries.first(where: { $0 > position }) ?? text.length
        switch action {
        case .escape:
            return selectedIndex == 0 ? .cancel : updated(raw, cursor)
        case .enter: return .commit(display)
        case .shortcut: return .passThrough(display)
        case .select(let index):
            guard candidates.indices.contains(index) else { return .rejected }
            return updated(raw, cursor, selected: index)
        case .cycle(let direction):
            guard candidates.count > 1 else { return .updated(self) }
            let index = (selectedIndex + (direction < 0 ? candidates.count - 1 : 1)) % candidates.count
            return updated(raw, cursor, selected: index)
        case .insert(let literal):
            guard !literal.isEmpty, text.length + literal.utf16.count <= 256,
                  literal.unicodeScalars.allSatisfy({ (32...126).contains($0.value) || $0.value == 176 }) else { return .rejected }
            return updated(text.replacingCharacters(in: NSRange(location: position, length: 0), with: literal), position + literal.utf16.count)
        case .backspace:
            guard position > 0 else { return .updated(self) }
            return updated(text.replacingCharacters(in: NSRange(location: previous, length: position - previous), with: ""), previous)
        case .delete:
            guard position < text.length else { return .updated(self) }
            return updated(text.replacingCharacters(in: NSRange(location: position, length: next - position), with: ""), position)
        case .left: return updated(display, previous)
        case .right: return updated(display, next)
        case .home: return updated(display, 0)
        case .end: return updated(display, text.length)
        }
    }
}
