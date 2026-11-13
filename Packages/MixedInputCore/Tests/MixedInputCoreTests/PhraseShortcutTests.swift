// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Testing
@testable import MixedInputCore

@Suite("Ctrl number phrase selection")
struct PhraseShortcutTests {
    @Test func onlyPlainControlAndDigitsTwoThroughNineAreShortcuts() {
        for (code, length): (UInt16, Int) in [(19, 2), (20, 3), (21, 4), (23, 5), (22, 6), (26, 7), (28, 8), (25, 9)] {
            #expect(PhraseShortcut.length(keyCode: code, control: true, otherModifiers: false) == length)
            #expect(PhraseShortcut.length(keyCode: code, control: false, otherModifiers: false) == nil)
            #expect(PhraseShortcut.length(keyCode: code, control: true, otherModifiers: true) == nil)
        }
        for code: UInt16 in [18, 29, 3, 51, 82, 83, 84] {
            #expect(PhraseShortcut.length(keyCode: code, control: true, otherModifiers: false) == nil)
        }
    }
    @Test func nineCharacterPhraseAndInvalidLengths() throws {
        let text = "甲乙丙丁戊己庚辛壬"
        let readings = Array(repeating: "ㄐㄧㄚˇ", count: 9)
        let selected = try #require(PhraseShortcut.selection(text: text, readings: readings, cursorUTF16: 9, length: 9, beforeCursor: true))
        #expect(selected.text == text)
        #expect(selected.readings.count == 9)
        for length in [Int.min, -1, 0, 1, 10, Int.max] {
            #expect(PhraseShortcut.selection(text: text, readings: readings, cursorUTF16: 9, length: length, beforeCursor: true) == nil)
        }
    }
    @Test func selectsExactLengthInBothDirectionsWithoutMovingCursor() throws {
        let text = "甲乙丙丁"
        let readings = ["ㄐㄧㄚˇ", "ㄧˇ", "ㄅㄧㄥˇ", "ㄉㄧㄥ"]
        let before = try #require(PhraseShortcut.selection(text: text, readings: readings, cursorUTF16: 2, length: 2, beforeCursor: true))
        let after = try #require(PhraseShortcut.selection(text: text, readings: readings, cursorUTF16: 2, length: 2, beforeCursor: false))
        #expect(before.text == "甲乙")
        #expect(before.readings == Array(readings.prefix(2)))
        #expect(before.markerUTF16 == 0)
        #expect(after.text == "丙丁")
        #expect(after.readings == Array(readings.suffix(2)))
        #expect(after.markerUTF16 == 4)
    }
    @Test func neverTruncatesOrInventsReadings() {
        for (cursor, length, before) in [(0, 2, true), (2, 2, false), (1, 3, true), (1, 0, false)] {
            #expect(PhraseShortcut.selection(text: "甲乙", readings: ["ㄐㄧㄚˇ", "ㄧˇ"], cursorUTF16: cursor, length: length, beforeCursor: before) == nil)
        }
        #expect(PhraseShortcut.selection(text: "甲乙", readings: ["ㄐㄧㄚˇ"], cursorUTF16: 2, length: 2, beforeCursor: true) == nil)
        #expect(PhraseShortcut.selection(text: "甲，", readings: ["ㄐㄧㄚˇ", "_punctuation_,"], cursorUTF16: 2, length: 2, beforeCursor: true) == nil)
    }
    @Test func respectsUTF16AndCompleteCharacters() throws {
        let text = "甲𠮷乙"
        let readings = ["ㄐㄧㄚˇ", "ㄐㄧˊ", "ㄧˇ"]
        #expect(PhraseShortcut.selection(text: text, readings: readings, cursorUTF16: 2, length: 2, beforeCursor: true) == nil)
        let result = try #require(PhraseShortcut.selection(text: text, readings: readings, cursorUTF16: 4, length: 2, beforeCursor: true))
        #expect(result.text == "𠮷乙")
        #expect(result.range.location == 1)
        #expect(result.range.length == 3)
    }
}
