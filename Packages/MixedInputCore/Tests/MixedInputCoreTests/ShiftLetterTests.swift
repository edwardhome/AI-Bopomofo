// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Testing
@testable import MixedInputCore

@Suite("Shift letter modes")
struct ShiftLetterTests {
    private func updated(_ result: ShiftLetterSession.Result) throws -> ShiftLetterSession {
        guard case .updated(let next) = result else {
            Issue.record("Expected composition to remain editable")
            throw Failure.unexpected
        }
        return next
    }
    private enum Failure: Error { case unexpected }

    @Test func oneLetterReleaseContinuesEnglishWord() throws {
        var session = ShiftLetterSession(composition: ASCIIComposition(raw: "S"))
        session = try updated(session.releasingShift())
        #expect(session.mode == .word)
        session = try updated(session.applying(.insert("wift"), shiftHeld: false))
        #expect(session.composition.raw == "Swift")
        if case .commit(let text) = session.applying(.enter, shiftHeld: false) {
            #expect(text == "Swift")
        } else { Issue.record("Enter must commit and finish the word") }
    }

    @Test func heldShiftCommitsUppercaseAndReleaseFinishes() {
        var session = ShiftLetterSession(composition: ASCIIComposition(raw: "A"))
        if case .commitAndContinue(let text, let next) = session.applying(.insert("B"), shiftHeld: true) {
            #expect(text == "AB")
            session = next
        } else { Issue.record("Second held letter must start direct uppercase") }
        #expect(session.mode == .uppercase)
        if case .commitAndContinue(let text, let next) = session.applying(.insert("C"), shiftHeld: true) {
            #expect(text == "C")
            #expect(next.composition.raw.isEmpty)
        } else { Issue.record("Uppercase must commit immediately") }
        if case .commit(let text) = session.releasingShift() { #expect(text.isEmpty) }
        else { Issue.record("Release must return to Chinese") }
    }

    @Test func backspaceToEmptyStillAllowsLowercaseMillimetres() throws {
        var session = try updated(ShiftLetterSession(composition: ASCIIComposition(raw: "M")).releasingShift())
        session = try updated(session.applying(.backspace, shiftHeld: false))
        #expect(session.mode == .word)
        #expect(session.composition.raw.isEmpty)
        for _ in 0..<2 { session = try updated(session.applying(.insert("m"), shiftHeld: false)) }
        if case .commit(let text) = session.applying(.insert(" "), shiftHeld: false) { #expect(text == "mm ") }
        else { Issue.record("Space must commit lowercase mm") }
    }

    @Test func repeatIsNotASecondNewLetterAndShortcutDoesNotBecomeText() throws {
        let initial = ShiftLetterSession(composition: ASCIIComposition(raw: "S"))
        let repeated = try updated(initial.applying(.insert("S"), shiftHeld: true, repeating: true))
        #expect(repeated.mode == .initial)
        #expect(repeated.composition.raw == "s")
        if case .passThrough(let text) = initial.applying(.shortcut, shiftHeld: true) { #expect(text == "S") }
        else { Issue.record("Shortcut must pass through") }
    }

    @Test func uppercaseEditingKeysStayNativeAndEscCancelsWord() {
        let upper = ShiftLetterSession(composition: ASCIIComposition(), mode: .uppercase)
        if case .forward = upper.applying(.backspace, shiftHeld: true) {} else { Issue.record("Forward backspace") }
        if case .forward = upper.applying(.delete, shiftHeld: true) {} else { Issue.record("Forward forward-delete") }
        let word = ShiftLetterSession(composition: ASCIIComposition(raw: "test"), mode: .word)
        if case .cancel = word.applying(.escape, shiftHeld: false) {} else { Issue.record("Escape must cancel") }
    }

    @Test func laterShiftInsideAWordDoesNotBecomeDirectUppercase() throws {
        let word = ShiftLetterSession(composition: ASCIIComposition(raw: "i"), mode: .word)
        let next = try updated(word.applying(.insert("P"), shiftHeld: true))
        #expect(next.composition.raw == "iP")
        #expect(next.mode == .word)
    }
    @Test func heldInitialLetterLowercasesOnceAfterShiftRelease() throws {
        var session = ShiftLetterSession(composition: ASCIIComposition(raw: "S"))
        session = try updated(session.releasingShift())
        for _ in 0..<10 {
            session = try updated(session.applying(.insert("s"), shiftHeld: false, repeating: true))
            #expect(session.composition.raw == "s")
        }
        session = try updated(session.applying(.insert("wift"), shiftHeld: false))
        #expect(session.composition.raw == "swift")
        #expect(session.heldInitialLetter == nil)
    }

    @Test func laterLetterRepeatAndFreshSameLetterKeepOriginalBehavior() throws {
        var session = try updated(ShiftLetterSession(composition: ASCIIComposition(raw: "M")).releasingShift())
        session = try updated(session.applying(.insert("m"), shiftHeld: false))
        session = try updated(session.applying(.insert("m"), shiftHeld: false, repeating: true))
        #expect(session.composition.raw == "Mmm")
        #expect(session.heldInitialLetter == nil)
    }

    @Test func heldInitialLetterDoesNotChangeUppercaseContinuation() throws {
        let session = try updated(ShiftLetterSession(composition: ASCIIComposition(raw: "S"))
            .applying(.insert("S"), shiftHeld: true, repeating: true))
        if case .commitAndContinue(let text, let next) = session.applying(.insert("W"), shiftHeld: true) {
            #expect(text == "sW")
            #expect(next.mode == .uppercase)
        } else { Issue.record("The second fresh Shift letter keeps uppercase continuation") }
    }

}
