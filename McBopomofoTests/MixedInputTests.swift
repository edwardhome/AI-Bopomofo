// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Cocoa
import Testing
import MixedInputCore
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

    @Test func engineeringCandidateAnnotationNeverCommits() throws {
        let previous = MixedInputHandler.lexicon
        MixedInputHandler.lexicon = TechnicalLexicon()
        defer { MixedInputHandler.lexicon = previous }
        let s = Session()
        s.begin(); s.type("sio2")
        let raw = try #require(s.state as? InputState.ASCII)
        #expect(raw.candidate(at: 0) == "sio2")
        #expect(raw.candidate(at: 1) == "SiO₂")
        #expect(raw.reading(at: 1) == "二氧化矽")
        s.key("\t", code: 48)
        s.key("x")
        #expect((s.state as? InputState.ASCII)?.composition.raw == "SiO₂x")
        s.key("\r")
        #expect(s.committed == "SiO₂x")
    }

    @Test func engineeringCandidatesRejectPredictionButOrdinaryEnglishStillWorks() {
        let previous = MixedInputHandler.lexicon
        MixedInputHandler.lexicon = TechnicalLexicon()
        defer { MixedInputHandler.lexicon = previous }
        let term = InputState.ASCII(text: "fin", cursor: 3)
        let blocked = MixedInputHandler.withPrediction("finally", state: term)
        #expect(blocked === term)
        #expect(blocked.prediction == nil)
        #expect(blocked.composition.candidates.contains("FinFET"))
        let ordinary = InputState.ASCII(text: "hel", cursor: 3)
        #expect(MixedInputHandler.withPrediction("hello", state: ordinary).prediction == "hello")
    }

    @Test func lexiconRefreshPreservesWrappedShiftAndFState() throws {
        let previous = MixedInputHandler.lexicon
        defer { MixedInputHandler.lexicon = previous }
        let raw = ASCIIComposition(raw: "sio2", lexicon: TechnicalLexicon())
        let index = try #require(raw.candidates.firstIndex(of: "SiO₂"))
        guard case .updated(let selected) = raw.applying(.select(index)) else { Issue.record("Missing selection"); return }
        let shifted = InputState.ShiftASCII(composition: selected, mode: .word, prediction: "stale")
        let held = InputState.QuickSymbols(held: true, originalASCII: shifted)
        let pending = InputState.PendingF(original: held)
        MixedInputHandler.lexicon = TechnicalLexicon(engineeringEnabled: false)
        let restored = try #require(MixedInputHandler.reloadingLexicon(state: pending) as? InputState.PendingF)
        let restoredHeld = try #require(restored.original as? InputState.QuickSymbols)
        let restoredShift = try #require(restoredHeld.originalASCII as? InputState.ShiftASCII)
        #expect(restoredHeld.held)
        #expect(restoredShift.mode == .word)
        #expect(restoredShift.composition.raw == "sio2")
        #expect(restoredShift.composition.selectedIndex == 0)
        #expect(!restoredShift.composition.hasEngineeringCandidates)
        #expect(restoredShift.prediction == nil)
        #expect(restoredShift.predictionSuppressed)
    }

    @Test func phoneticFChordQueryDoesNotChangeComposition() {
        let s = Session()
        for next: UInt16 in [117, 109] { // u、m
            #expect(s.handler.prefersPhoneticFChord(firstKey: 102, nextKey: next, state: s.state))
            #expect(s.handler.canBeginQuickSymbols(with: s.state))
            #expect(s.state is InputState.Empty)
        }
        for next: UInt16 in [114, 27, 106, 85, 0x3107] {
            #expect(!s.handler.prefersPhoneticFChord(firstKey: 102, nextKey: next, state: s.state))
        }
        #expect(!s.handler.prefersPhoneticFChord(firstKey: 70, nextKey: 117, state: s.state))
        #expect(!s.handler.prefersPhoneticFChord(firstKey: 0x3107, nextKey: 117, state: s.state))
        s.key("f", code: 3)
        let before = (s.state as? InputState.Inputting)?.composingBuffer
        #expect(!s.handler.prefersPhoneticFChord(firstKey: 102, nextKey: 117, state: s.state))
        #expect((s.state as? InputState.Inputting)?.composingBuffer == before)
    }

    @Test func protectedOverlapRestoresFBeforeMedialExactlyOnce() {
        for (next, code, reading): (String, UInt16, String) in [("u", 32, "ㄑㄧ"), ("m", 46, "ㄑㄩ")] {
            for elapsed in [0.001, 0.249, 0.250, 0.251] {
                let s = Session()
                var gesture = FHoldGesture(delayMilliseconds: 250)
                _ = gesture.handle(.press(eligible: true, repeating: false))
                _ = gesture.handle(.elapsed(elapsed))
                let original = s.state
                s.state = InputState.PendingF(original: original)
                let prefer = gesture.phase == .pending && s.handler.prefersPhoneticFChord(
                    firstKey: 102, nextKey: next.utf16.first!, state: original)
                let mapped = QuickSymbolLayer.canStartChord(keyCode: code, repeating: false,
                    hasDisallowedModifiers: false, prefersPhonetic: prefer)
                let effects = gesture.handle(.otherKey(isMapped: mapped))
                s.state = original
                if prefer {
                    #expect(effects == [.invalidate, .replayTap])
                    s.key("f", code: 3)
                    s.key(next, code: code)
                    #expect((s.state as? InputState.Inputting)?.composingBuffer == reading)
                    #expect(s.committed.isEmpty)
                    #expect(s.errors == 0)
                    #expect(!gesture.handle(.observedRelease).contains(.replayTap))
                    #expect(!gesture.handle(.release).contains(.replayTap))
                } else {
                    #expect(gesture.phase == .held)
                    #expect(s.handler.beginQuickSymbols(with: s.state, held: true, stateCallback: s.transition))
                    s.key(next, code: code)
                    s.handler.endQuickSymbols(with: s.state, stateCallback: s.transition)
                    #expect(s.committed == (code == 32 ? "8" : "2"))
                }
            }
        }
    }

    @Test func phoneticPriorityExcludesEnglishAndOtherLayouts() {
        let s = Session()
        let englishStates: [InputState] = [InputState.ASCII(text: "", cursor: 0),
            InputState.ShiftASCII(shiftText: "S", cursor: 1),
            InputState.ShiftASCII(composition: ASCIIComposition(), mode: .uppercase)]
        for state in englishStates {
            #expect(!s.handler.prefersPhoneticFChord(firstKey: 102, nextKey: 117, state: state))
            #expect(!s.handler.prefersPhoneticFChord(firstKey: 102, nextKey: 109, state: state))
        }
        let savedLayout = Preferences.keyboardLayout
        defer { Preferences.keyboardLayout = savedLayout }
        for layout: KeyboardLayout in [.eten, .hsu, .eten26, .hanyuPinyin, .IBM, .standard] {
            Preferences.keyboardLayout = layout
            s.handler.syncWithPreferences()
            for next: UInt16 in [117, 109] {
                #expect(s.handler.prefersPhoneticFChord(firstKey: 102, nextKey: next, state: s.state)
                    == (layout == .standard))
            }
        }
    }

    @Test func shiftWordReleaseBackspaceAndLowercaseMM() {
        let old = Preferences.mixedEnglishEnabled
        let switching = Preferences.switchInputSourceUponShiftLetterKeyComboEnabled
        defer { Preferences.mixedEnglishEnabled = old; Preferences.switchInputSourceUponShiftLetterKeyComboEnabled = switching }
        Preferences.mixedEnglishEnabled = true
        Preferences.switchInputSourceUponShiftLetterKeyComboEnabled = false
        let s = Session()
        s.key("M", code: 46, flags: .shift)
        #expect((s.state as? InputState.ShiftASCII)?.mode == .initial)
        #expect(s.handler.releaseShift(with: s.state, stateCallback: s.transition))
        s.key("\u{7F}", code: 51)
        s.type("mm")
        #expect((s.state as? InputState.ShiftASCII)?.mode == .word)
        #expect(s.committed.isEmpty)
        s.key(" ", code: 49)
        #expect(s.committed == "mm ")
        #expect(s.state is InputState.EmptyIgnoringPreviousState)
        s.key("j")
        #expect(s.state is InputState.Inputting)
        #expect(!(s.state is InputState.ASCII))
    }

    @Test func heldShiftABCCommitsThenReturnsToChinese() {
        let s = Session()
        s.state = InputState.ShiftASCII(shiftText: "A", cursor: 1)
        s.key("B", code: 11, flags: .shift)
        #expect(s.committed == "AB")
        s.key("C", code: 8, flags: .shift)
        #expect(s.committed == "ABC")
        #expect((s.state as? InputState.ShiftASCII)?.mode == .uppercase)
        #expect(s.handler.releaseShift(with: s.state, stateCallback: s.transition))
        #expect(s.state is InputState.EmptyIgnoringPreviousState)
        #expect(!s.handler.releaseShift(with: s.state, stateCallback: s.transition))
    }

    @Test func shiftReleasePreservesFStateAndCommitsUppercaseSymbolsOnce() {
        let s = Session()
        let upper = InputState.ShiftASCII(composition: ASCIIComposition(raw: "+"), mode: .uppercase)
        s.state = InputState.QuickSymbols(held: true, originalASCII: upper)
        #expect(s.handler.releaseShift(with: s.state, stateCallback: s.transition))
        #expect(s.state is InputState.QuickSymbols)
        #expect(s.committed == "+")
        s.key("r", code: 15)
        s.handler.endQuickSymbols(with: s.state, stateCallback: s.transition)
        #expect(s.committed == "++")
        s.state = InputState.PendingF(original: InputState.ShiftASCII(shiftText: "S", cursor: 1))
        #expect(s.handler.releaseShift(with: s.state, stateCallback: s.transition))
        #expect(((s.state as? InputState.PendingF)?.original as? InputState.ShiftASCII)?.mode == .word)
    }

    @Test func manualASCIIAndPredictionKeepTheirEntryMode() {
        let s = Session()
        s.begin(); s.type("hello")
        #expect(!s.handler.releaseShift(with: s.state, stateCallback: s.transition))
        s.key(" ")
        #expect(s.committed.isEmpty)
        #expect((s.state as? InputState.ASCII)?.composingBuffer == "hello ")
        s.state = InputState.ShiftASCII(composition: ASCIIComposition(raw: "hel"), mode: .word)
        s.handler.publishPrediction("hello", state: s.state, stateCallback: s.transition)
        #expect((s.state as? InputState.ShiftASCII)?.mode == .word)
        s.key("\r")
        #expect(s.committed == "hel")
    }

    @Test func waitingMarkNeverBecomesCommittedComposition() {
        let empty = InputState.Empty()
        let pending = InputState.PendingF(original: empty)
        #expect(pending.original === empty)
        #expect(!((pending as InputState) is InputState.NotEmpty))
        #expect(InputState.fHoldMarkedText(original: nil).string == "·")
        let ascii = InputState.ASCII(text: "hello", cursor: 2)
        #expect(InputState.fHoldMarkedText(original: ascii).string == ascii.attributedString.string)
        let s = Session()
        s.transition(pending)
        s.transition(empty)
        #expect(s.committed.isEmpty)
        s.transition(InputState.QuickSymbols(held: true))
        s.handler.endQuickSymbols(with: s.state, stateCallback: s.transition)
        #expect(s.committed.isEmpty)
    }

    @Test func delayedFTapRemainsPhonetic() {
        let previousLayout = Preferences.keyboardLayout
        defer { Preferences.keyboardLayout = previousLayout }
        Preferences.keyboardLayout = .standard
        let s = Session()
        var gesture = FHoldGesture(delayMilliseconds: 400)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.elapsed(0.200)).isEmpty)
        let effects = gesture.handle(.release)
        #expect(effects.contains(.replayTap))
        if effects.contains(.replayTap) { s.key("f", code: 3) }
        #expect((s.state as? InputState.Inputting)?.composingBuffer == "ㄑ")
        #expect(s.committed.isEmpty)
        #expect(s.errors == 0)
    }

    @Test func standaloneSymbolsCommitAndReturnToChinese() {
        let s = Session()
        s.type("ji3")
        #expect((s.state as? InputState.Inputting)?.composingBuffer == "我")
        #expect(s.handler.beginQuickSymbols(with: s.state, held: true, stateCallback: s.transition))
        #expect(s.committed == "我")
        s.key("y", code: 16); s.key("r", code: 15); s.key("n", code: 45)
        #expect(s.committed == "我")
        #expect((s.state as? InputState.QuickSymbols)?.heldBuffer?.raw == "7+1")
        s.handler.endQuickSymbols(with: s.state, stateCallback: s.transition)
        #expect(s.committed == "我7+1")
        s.type("ji3"); s.key("\r")
        #expect(s.committed == "我7+1我")
        #expect(s.errors == 0)
    }

    @Test func heldLayerDeletesWithoutCommittingOrLeavingLayer() {
        let s = Session()
        #expect(s.handler.beginQuickSymbols(with: s.state, held: true, stateCallback: s.transition))
        s.key("y", code: 16); s.key("r", code: 15); s.key("n", code: 45)
        for expected in ["7+", "7", "", ""] {
            #expect(s.key("\u{7F}", code: 51))
            #expect((s.state as? InputState.QuickSymbols)?.heldBuffer?.raw == expected)
            #expect(s.committed.isEmpty)
        }
        s.key("r", code: 15)
        s.handler.endQuickSymbols(with: s.state, stateCallback: s.transition)
        #expect(s.committed == "+")
        #expect(!s.key("\u{7F}", code: 51))
        #expect(s.errors == 0)
    }

    @Test func heldEnglishDeletionPreservesCompositionAndCursor() {
        let s = Session()
        s.state = InputState.ASCII(text: "abcd", cursor: 2)
        #expect(s.handler.beginQuickSymbols(with: s.state, held: true, stateCallback: s.transition))
        s.key("r", code: 15)
        s.key("\u{7F}", code: 51)
        s.key("\u{F728}", code: 117)
        s.handler.endQuickSymbols(with: s.state, stateCallback: s.transition)
        #expect((s.state as? InputState.ASCII)?.composingBuffer == "abd")
        #expect((s.state as? InputState.ASCII)?.cursorIndex == 2)
        #expect(s.committed.isEmpty)
    }

    @Test func nativeBackspaceDeletesPhoneticsAndAllowsRepeatedDelivery() {
        let s = Session()
        s.type("ji3")
        #expect(s.key("\u{7F}", code: 51))
        #expect(s.state is InputState.EmptyIgnoringPreviousState)
        #expect(!s.key("\u{7F}", code: 51))
        #expect(!s.key("\u{7F}", code: 51))
        #expect(s.committed.isEmpty)
        #expect(s.errors == 0)
    }

    @Test func earlyFChordHandlesFirstKeyAndEscAsBacktick() {
        for english in [false, true] {
            let s = Session()
            if english { s.begin(); s.type("Hello") }
            var gesture = FHoldGesture()
            _ = gesture.handle(.press(eligible: true, repeating: false))
            #expect(gesture.handle(.otherKey(isMapped: true)) == [.beginLayer])
            #expect(s.handler.beginQuickSymbols(with: s.state, held: true, stateCallback: s.transition))
            #expect(s.key("r", code: 15))
            #expect(s.key("\u{1B}", code: 53))
            #expect(s.state is InputState.QuickSymbols)
            #expect((s.state as? InputState.QuickSymbols)?.editingComposition?.raw == (english ? "Hello+`" : "+`"))
            #expect(s.committed.isEmpty)
            #expect(gesture.handle(.observedRelease).contains(.endLayer))
            s.handler.endQuickSymbols(with: s.state, stateCallback: s.transition)
            if english {
                #expect((s.state as? InputState.ASCII)?.composingBuffer == "Hello+`")
                #expect(s.committed.isEmpty)
            } else {
                #expect(s.committed == "+`")
            }
        }
    }

    @Test func escapeStillExitsManualSymbolMenu() {
        let s = Session()
        #expect(s.handler.beginQuickSymbols(with: s.state, held: false, stateCallback: s.transition))
        #expect(s.key("\u{1B}", code: 53))
        #expect(s.state is InputState.EmptyIgnoringPreviousState)
        #expect(s.committed.isEmpty)
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

    @Test func englishSymbolLayerEnterRestoresCursorWithoutCommitting() {
        let s = Session()
        s.state = InputState.ASCII(text: "abc", cursor: 1)
        #expect(s.handler.beginQuickSymbols(with: s.state, held: true, stateCallback: s.transition))
        s.key("r", code: 15); s.key("\r", code: 36)
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
