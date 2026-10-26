// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Cocoa
import Testing
@testable import McBopomofo

@Suite("Mixed ASCII input", .serialized)
@MainActor
struct MixedInputTests {
    final class Session {
        let handler = KeyHandler()
        var state: InputState = InputState.Empty()
        var committed = ""
        var errors = 0

        init() {
            LanguageModelManager.loadDataModels()
            handler.inputMode = .bopomofo
        }

        func transition(_ next: InputState) {
            // Mirror the IMK controller's Empty/Committing contract.
            if next is InputState.Empty, let previous = state as? InputState.NotEmpty {
                committed += previous.composingBuffer
            }
            if let committing = next as? InputState.Committing { committed += committing.poppedText }
            state = next
        }

        @discardableResult func key(_ text: String, code: UInt16 = 0, flags: NSEvent.ModifierFlags = []) -> Bool {
            handler.handle(input: KeyHandlerInput(inputText: text, keyCode: code,
                charCode: text.utf16.first ?? 0, flags: flags, isVerticalMode: false),
                state: state, stateCallback: transition, errorCallback: { self.errors += 1 })
        }

        func type(_ text: String) { for char in text { key(String(char)) } }

        @discardableResult func begin() -> Bool {
            handler.beginASCII(with: state, stateCallback: transition, errorCallback: { self.errors += 1 })
        }
    }

    @Test(arguments: ["1234567890", "[]", "{}", "()", "<>", "/ \\ _ - + = * # @",
                       "Python3", "PySide6", "RTX 4090", "module_name", "foo.bar", "path/to/file"])
    func literals(_ value: String) {
        let s = Session()
        #expect(s.begin())
        s.type(value)
        #expect((s.state as? InputState.ASCII)?.composingBuffer == value)
        #expect(s.committed.isEmpty)
        s.key("\r")
        #expect(s.committed == value)
        #expect(s.state is InputState.Empty)
        #expect(s.errors == 0)
    }

    @Test func cancellation() {
        let s = Session()
        s.begin(); s.type("Unknown_Python3")
        s.key("\u{1B}")
        #expect(s.state is InputState.EmptyIgnoringPreviousState)
        #expect(s.committed.isEmpty)
        s.key("s")
        #expect(s.state is InputState.Inputting)
        #expect(!(s.state is InputState.ASCII))
    }

    @Test func editing() {
        let s = Session()
        s.begin(); s.type("PySide66")
        s.key("\u{8}")
        s.key("", code: KeyCode.home.rawValue)
        s.key("", code: KeyCode.delete.rawValue)
        s.key("P")
        s.key("", code: KeyCode.end.rawValue)
        s.key("", code: KeyCode.left.rawValue)
        s.key("3")
        #expect((s.state as? InputState.ASCII)?.composingBuffer == "PySide36")
        s.key("", code: KeyCode.right.rawValue)
        s.key("\r")
        #expect(s.committed == "PySide36")
    }

    @Test func unfinishedBopomofoIsPreserved() {
        let s = Session()
        s.key("s")
        let before = (s.state as? InputState.Inputting)?.composingBuffer
        #expect(!s.begin())
        #expect((s.state as? InputState.Inputting)?.composingBuffer == before)
        #expect(s.committed.isEmpty)
        #expect(s.errors == 1)
    }

    @Test func chineseThenEnglishThenChinese() {
        let s = Session()
        s.type("su3cl3")
        #expect((s.state as? InputState.Inputting)?.composingBuffer == "你好")
        #expect(s.begin())
        s.type(" Python3 "); s.key("\r")
        s.type("su3cl3"); s.key("\r")
        #expect(s.committed == "你好 Python3 你好")
    }

    @Test func shortcutsCommitOnceAndPassThrough() {
        let s = Session()
        s.begin(); s.type("GitHub")
        #expect(!s.key("a", flags: .command))
        #expect(s.committed == "GitHub")
        #expect(s.state is InputState.Empty)
    }

    @Test func shiftedSymbolsAreLiteralOnlyInsideASCII() {
        let s = Session()
        s.begin()
        for c in "{}()<>_+*#@" { s.key(String(c), flags: .shift) }
        s.key("\r")
        #expect(s.committed == "{}()<>_+*#@")
    }

    @Test func upstreamShiftPunctuation() {
        let previous = Preferences.halfWidthPunctuationEnabled
        defer { Preferences.halfWidthPunctuationEnabled = previous }
        for half in [false, true] {
            Preferences.halfWidthPunctuationEnabled = half
            for (key, full, narrow) in [("<", "，", ","), (">", "。", ".")] {
                let s = Session()
                s.key(key, flags: .shift)
                #expect((s.state as? InputState.Inputting)?.composingBuffer == (half ? narrow : full))
                #expect(!(s.state is InputState.ASCII))
            }
        }
    }

    @Test func keypadInChineseComposition() {
        let previous = Preferences.selectCandidateWithNumericKeypad
        Preferences.selectCandidateWithNumericKeypad = false
        defer { Preferences.selectCandidateWithNumericKeypad = previous }
        for literal in "0123456789+-*/." {
            let s = Session()
            s.type("su3cl3")
            s.key(String(literal), flags: .numericPad)
            #expect(s.committed == "你好" + String(literal))
            #expect(s.errors == 0)
        }
    }

    @Test func boundedCompositionAndRapidInput() {
        let s = Session()
        s.begin()
        s.type(String(repeating: "a", count: 256))
        s.key("b")
        #expect((s.state as? InputState.ASCII)?.composingBuffer.count == 256)
        #expect(s.errors == 1)
        s.key("\u{8}"); s.key("b"); s.key("\r")
        #expect(s.committed == String(repeating: "a", count: 255) + "b")
    }

    @Test func optInShiftLetterAndCancelRestart() {
        let mixed = Preferences.mixedEnglishEnabled
        let switching = Preferences.switchInputSourceUponShiftLetterKeyComboEnabled
        defer {
            Preferences.mixedEnglishEnabled = mixed
            Preferences.switchInputSourceUponShiftLetterKeyComboEnabled = switching
        }
        Preferences.mixedEnglishEnabled = true
        Preferences.switchInputSourceUponShiftLetterKeyComboEnabled = false
        let s = Session()
        s.key("P", flags: .shift); s.type("ython3")
        #expect((s.state as? InputState.ASCII)?.composingBuffer == "Python3")
        s.key("\u{1B}")
        s.key("F", flags: .shift); s.type("PGA")
        s.key("\r")
        #expect(s.committed == "FPGA")
        Preferences.switchInputSourceUponShiftLetterKeyComboEnabled = true
        let other = Session()
        #expect(!other.key("A", flags: .shift))
        #expect(other.state is InputState.SwitchingInputSource)
    }

    @Test func englishCandidateDoesNotChangeRawAutomatically() {
        let s = Session()
        s.begin(); s.type("py")
        #expect((s.state as? InputState.ASCII)?.composingBuffer == "py")
        s.key("\t", code: KeyCode.tab.rawValue)
        #expect((s.state as? InputState.ASCII)?.composingBuffer != "py")
        s.key("\u{1B}")
        #expect((s.state as? InputState.ASCII)?.composingBuffer == "py")
        s.key("\r")
        #expect(s.committed == "py")
    }
}
