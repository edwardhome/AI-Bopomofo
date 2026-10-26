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

    @Test func standaloneSymbolsCommitAndReturnToChinese() {
        let s = Session()
        s.type("ji3")
        #expect((s.state as? InputState.Inputting)?.composingBuffer == "我")
        #expect(s.handler.beginQuickSymbols(with: s.state, held: true, stateCallback: s.transition))
        #expect(s.committed == "我")
        s.key("y", code: 16); s.key("r", code: 15); s.key("n", code: 45)
        #expect(s.committed == "我7+1")
        s.handler.endQuickSymbols(with: s.state, stateCallback: s.transition)
        s.type("ji3"); s.key("\r")
        #expect(s.committed == "我7+1我")
        #expect(s.errors == 0)
    }

    @Test func contextualPredictionAcceptsOnlyOnTab() {
        let s = Session()
        s.begin(); s.type("I would like to ")
        s.handler.publishPrediction("I would like to learn", state: s.state, stateCallback: s.transition)
        #expect((s.state as? InputState.ASCII)?.composingBuffer == "I would like to ")
        #expect(s.committed.isEmpty)
        s.key("\t", code: 48)
        #expect((s.state as? InputState.ASCII)?.composingBuffer == "I would like to learn")
        #expect(s.committed.isEmpty)
        s.key("\r")
        #expect(s.committed == "I would like to learn")
    }

    @Test func predictionEnterNeverCommitsUnacceptedSuffix() {
        let s = Session()
        s.begin(); s.type("hel")
        s.handler.publishPrediction("hello", state: s.state, stateCallback: s.transition)
        s.key("\r")
        #expect(s.committed == "hel")
    }

    @Test func predictionEscapeKeepsOriginalAndSuppressesRepeat() {
        let s = Session()
        s.begin(); s.type("hel")
        s.handler.publishPrediction("hello", state: s.state, stateCallback: s.transition)
        s.key("\u{1B}")
        #expect((s.state as? InputState.ASCII)?.composingBuffer == "hel")
        #expect((s.state as? InputState.ASCII)?.prediction == nil)
        #expect((s.state as? InputState.ASCII)?.predictionSuppressed == true)
        s.key("p")
        #expect((s.state as? InputState.ASCII)?.composingBuffer == "help")
        #expect((s.state as? InputState.ASCII)?.predictionSuppressed == false)
    }

    @Test func typingDoesNotInsertPredictionOrProtectCodeIncorrectly() {
        let s = Session()
        s.begin(); s.type("hel")
        s.handler.publishPrediction("hello", state: s.state, stateCallback: s.transition)
        s.key("p"); s.key("\r")
        #expect(s.committed == "help")
        let code = Session()
        code.begin(); code.type("foo_bar")
        code.handler.publishPrediction("foo_bar value", state: code.state, stateCallback: code.transition)
        #expect((code.state as? InputState.ASCII)?.prediction == nil)
    }

    @Test func correctionEscapeRestoresChineseEngineAndCursor() {
        let s = Session()
        s.type("ji3")
        let original = s.state as! InputState.Inputting
        #expect(s.handler.canBeginAssistance(with: original))
        s.handler.publishAssistance(InputState.Assistance(original: original, suggestions: ["你"], message: "test"), stateCallback: s.transition)
        s.key("\u{1B}")
        #expect(s.state === original)
        #expect(s.committed.isEmpty)
        s.type("su3"); s.key("\r")
        #expect(s.committed == "我你")
    }

    @Test func correctionCommitClearsEngineAndCommitsOnlyOnce() {
        let s = Session()
        s.type("ji3")
        let original = s.state as! InputState.Inputting
        s.handler.publishAssistance(InputState.Assistance(original: original, suggestions: ["你"], message: "test"), stateCallback: s.transition)
        s.handler.acceptAssistance(at: 1, state: s.state, stateCallback: s.transition)
        #expect(s.committed == "你")
        s.type("ji3"); s.key("\r")
        #expect(s.committed == "你我")
    }

    @Test func typingWhileCheckingRestoresInsteadOfSelectingHotkey() {
        let s = Session()
        s.begin(); s.type("teh")
        let original = s.state as! InputState.ASCII
        s.handler.publishAssistance(InputState.Assistance(original: original, suggestions: ["the"], isChecking: true, message: "test"), stateCallback: s.transition)
        s.key("a")
        #expect((s.state as? InputState.ASCII)?.composingBuffer == "teha")
        #expect(s.committed.isEmpty)
    }

    @Test func correctionShortcutRestoresAndPassesThrough() {
        let s = Session()
        s.begin(); s.type("teh")
        let original = s.state as! InputState.ASCII
        s.handler.publishAssistance(InputState.Assistance(original: original, suggestions: ["the"], message: "test"), stateCallback: s.transition)
        #expect(!s.key("a", flags: .command))
        #expect(s.committed == "teh")
    }

    @Test func symbolLayerPreservesReadingsAndSupportsEnglish() {
        let s = Session()
        s.key("j")
        #expect(!s.handler.canBeginQuickSymbols(with: s.state))
        let text = (s.state as? InputState.Inputting)?.composingBuffer
        #expect(!s.handler.beginQuickSymbols(with: s.state, held: true, stateCallback: s.transition))
        #expect((s.state as? InputState.Inputting)?.composingBuffer == text)
        let ascii = Session()
        ascii.begin(); ascii.type("Markdown")
        #expect(ascii.handler.canBeginQuickSymbols(with: ascii.state))
    }

    @Test func englishCompositionSurvivesHeldFSymbols() {
        let s = Session()
        s.begin(); s.type("Hello")
        #expect(s.handler.beginQuickSymbols(with: s.state, held: true, stateCallback: s.transition))
        s.key("R", code: 15, flags: .shift); s.key("r", code: 15)
        #expect(s.committed.isEmpty)
        s.handler.endQuickSymbols(with: s.state, stateCallback: s.transition)
        #expect((s.state as? InputState.ASCII)?.composingBuffer == "Hello++")
        s.type("world"); s.key("\r")
        #expect(s.committed == "Hello++world")
    }

    @Test func englishSymbolLayerEscRestoresCursorWithoutCommitting() {
        let s = Session()
        s.state = InputState.ASCII(text: "abc", cursor: 1)
        #expect(s.handler.beginQuickSymbols(with: s.state, held: true, stateCallback: s.transition))
        s.key("r", code: 15); s.key("\u{1B}")
        #expect((s.state as? InputState.ASCII)?.composingBuffer == "a+bc")
        #expect((s.state as? InputState.ASCII)?.cursorIndex == 2)
        #expect(s.committed.isEmpty)
    }

    @Test func backtickIsLiteralAndBig5RemainsAvailable() {
        let old = Preferences.backtickOpensPunctuationList
        let big5 = Preferences.big5InputEnabled
        defer { Preferences.backtickOpensPunctuationList = old; Preferences.big5InputEnabled = big5 }
        Preferences.backtickOpensPunctuationList = false
        Preferences.big5InputEnabled = true
        let s = Session()
        s.type("ji3"); s.key("`", code: 50)
        #expect(s.committed == "我`")
        s.key("`", code: 50, flags: .control)
        #expect(s.state is InputState.Big5)
        #expect(s.committed == "我`")
    }

    @Test func symbolShortcutsEscapeAndPointerSelection() {
        let s = Session()
        #expect(s.handler.beginQuickSymbols(with: s.state, held: false, stateCallback: s.transition))
        s.handler.selectQuickSymbol(at: 0, state: s.state, stateCallback: s.transition)
        #expect(s.committed == "7")
        #expect(s.state is InputState.QuickSymbols)
        #expect(!s.key("a", code: 0, flags: .command))
        #expect(s.state is InputState.EmptyIgnoringPreviousState)
        #expect(s.handler.beginQuickSymbols(with: s.state, held: false, stateCallback: s.transition))
        s.key("\u{1B}")
        #expect(s.state is InputState.EmptyIgnoringPreviousState)
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
