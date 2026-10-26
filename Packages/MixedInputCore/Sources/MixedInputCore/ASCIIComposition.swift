// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

public struct TechnicalLexicon: Sendable {
    public static let builtins = [
        "FPGA", "Vivado", "SystemVerilog", "Verilog", "VHDL", "Python", "Flask", "PySide6",
        "GitHub", "Git", "Codex", "McBopomofo", "InputMethodKit", "CoreML", "Swift", "Xcode",
        "MacBook", "Apple", "RTX", "branch", "module"
    ]
    public let words: [String]

    public init(custom: [String] = []) {
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
        guard prefix.count >= 2, !prefix.contains(where: \.isWhitespace) else { return [] }
        let lower = prefix.lowercased()
        return Array(words.lazy.filter { $0.lowercased().hasPrefix(lower) && $0 != prefix }.prefix(8))
    }
}

public struct ASCIIComposition: Sendable {
    public let raw: String
    public let cursor: Int
    public let selectedIndex: Int
    public let candidates: [String]

    public init(raw: String = "", cursor: Int? = nil, selectedIndex: Int = 0,
                lexicon: TechnicalLexicon = TechnicalLexicon()) {
        // All accepted scalars are one UTF-16 code unit; no partial grapheme edits.
        let text = String(raw.unicodeScalars.filter { (32...126).contains($0.value) || $0.value == 176 }.prefix(256))
        self.raw = text
        self.cursor = min(max(cursor ?? text.utf16.count, 0), text.utf16.count)
        candidates = text.isEmpty ? [] : [text] + (self.cursor == text.utf16.count ? lexicon.completions(for: text) : [])
        self.selectedIndex = candidates.indices.contains(selectedIndex) ? selectedIndex : 0
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
            .updated(ASCIIComposition(raw: text, cursor: cursor, selectedIndex: selected, lexicon: lexicon))
        }
        let text = display as NSString
        let position = displayCursor
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
            return updated(text.replacingCharacters(in: NSRange(location: position - 1, length: 1), with: ""), position - 1)
        case .delete:
            guard position < text.length else { return .updated(self) }
            return updated(text.replacingCharacters(in: NSRange(location: position, length: 1), with: ""), position)
        case .left: return updated(display, max(0, position - 1))
        case .right: return updated(display, min(text.length, position + 1))
        case .home: return updated(display, 0)
        case .end: return updated(display, text.length)
        }
    }
}
