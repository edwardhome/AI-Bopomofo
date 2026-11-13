// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

/// Ctrl＋數字的詞長與範圍計算；不讀寫詞庫，也不依賴 AppKit。
public enum PhraseShortcut {
    /// 實體數字列的 2～9；0／1 不重新定義成詞長，數字鍵盤也不混用。
    public static func length(keyCode: UInt16, control: Bool, otherModifiers: Bool) -> Int? {
        guard control && !otherModifiers else { return nil }
        return [UInt16(19): 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9][keyCode]
    }

    public struct Selection: Equatable, Sendable {
        public let range: NSRange
        public let markerUTF16: Int
        public let text: String
        public let readings: [String]
    }

    /// 只接受完整字元邊界及一字一讀音，不截斷超出組字的範圍。
    public static func selection(text: String, readings: [String], cursorUTF16: Int,
                                 length: Int, beforeCursor: Bool) -> Selection? {
        guard (2...9).contains(length) else { return nil }
        let characters = Array(text)
        guard length <= characters.count, characters.count == readings.count else { return nil }
        var boundaries = [0]
        for character in characters { boundaries.append(boundaries.last! + String(character).utf16.count) }
        guard let cursor = boundaries.firstIndex(of: cursorUTF16) else { return nil }
        let start = beforeCursor ? cursor - length : cursor
        let end = beforeCursor ? cursor : cursor + length
        guard start >= 0, end <= characters.count else { return nil }
        let selected = Array(readings[start..<end])
        guard selected.allSatisfy({ !$0.isEmpty && !$0.hasPrefix("_") }) else { return nil }
        return Selection(range: NSRange(location: boundaries[start], length: boundaries[end] - boundaries[start]),
                         markerUTF16: beforeCursor ? boundaries[start] : boundaries[end],
                         text: String(characters[start..<end]), readings: selected)
    }
}
