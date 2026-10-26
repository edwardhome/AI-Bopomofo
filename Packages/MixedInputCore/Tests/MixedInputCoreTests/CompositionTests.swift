// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Testing
@testable import MixedInputCore

@Suite("Headless ASCII composition")
struct CompositionTests {
    func apply(_ state: ASCIIComposition, _ action: ASCIIComposition.Action,
               lexicon: TechnicalLexicon = TechnicalLexicon()) -> ASCIIComposition {
        if case .updated(let next) = state.applying(action, lexicon: lexicon) { return next }
        Issue.record("Expected an updated composition")
        return state
    }

    @Test(arguments: ["1234567890", "[]{}()<>", "/ \\ _ - + = * # @", "Python3", "PySide6",
                      "RTX 4090", "module_name", "foo.bar", "path/to/file", "°"])
    func literalRoundTrip(_ raw: String) {
        var state = ASCIIComposition()
        for c in raw { state = apply(state, .insert(String(c))) }
        #expect(state.raw == raw)
        if case .commit(let committed) = state.applying(.enter) { #expect(committed == raw) }
        else { Issue.record("Expected commit") }
    }

    @Test func completionsAreExplicitAndReversible() {
        let state = ASCIIComposition(raw: "py")
        #expect(state.display == "py")
        #expect(state.candidates.contains("Python"))
        #expect(state.candidates.contains("PySide6"))
        let selected = apply(state, .select(state.candidates.firstIndex(of: "Python")!))
        #expect(selected.display == "Python")
        #expect(selected.raw == "py")
        #expect(apply(selected, .escape).raw == "py")
        if case .cancel = state.applying(.escape) {} else { Issue.record("Must cancel raw input") }
        #expect(apply(selected, .insert("3")).raw == "Python3")
    }

    @Test func unknownNamesNeverChange() {
        for name in ["qz_module7", "aBcD", "my/PrivatePath", "gh.thing"] {
            let state = ASCIIComposition(raw: name)
            #expect(state.candidates == [name])
            #expect(apply(state, .cycle(1)).display == name)
        }
    }

    @Test func editingAndBoundaries() {
        let state = ASCIIComposition(raw: "Python3")
        #expect(apply(state, .backspace).raw == "Python")
        let start = apply(state, .home)
        #expect(apply(start, .delete).raw == "ython3")
        #expect(apply(start, .left).cursor == 0)
        #expect(apply(state, .right).cursor == 7)
        #expect(apply(state, .left).candidates == ["Python3"])
        #expect(apply(apply(state, .home), .end).cursor == 7)
        let full = ASCIIComposition(raw: String(repeating: "x", count: 256))
        if case .rejected = full.applying(.insert("x")) {} else { Issue.record("Must reject overflow") }
        if case .rejected = state.applying(.insert("\n")) {} else { Issue.record("Must reject control text") }
    }

    @Test func dictionaryUsesExistingPhraseFormat() {
        let terms = TechnicalLexicon.userTerms(from: "# ignored\nMyFPGA _english_myfpga\n你好 ㄋㄧˇ-ㄏㄠˇ\nOther reading\nmyTerm _english_myterm\n")
        #expect(terms == ["MyFPGA", "myTerm"])
        let lexicon = TechnicalLexicon(custom: terms + ["bad term", "", "MyFPGA"])
        #expect(lexicon.completions(for: "my") == ["MyFPGA", "myTerm"])
        #expect(!TechnicalLexicon.isValid("123"))
        #expect(!TechnicalLexicon.isValid(String(repeating: "a", count: 65)))
    }

    @Test func boundsAndCycling() {
        let s = ASCIIComposition(raw: "py")
        #expect(apply(s, .cycle(-1)).selectedIndex == s.candidates.count - 1)
        #expect(apply(apply(s, .cycle(-1)), .cycle(1)).selectedIndex == 0)
        if case .rejected = s.applying(.select(-1)) {} else { Issue.record("Invalid ID accepted") }
        if case .rejected = s.applying(.select(99)) {} else { Issue.record("Invalid ID accepted") }
        #expect(ASCIIComposition(raw: "abc", cursor: 500, selectedIndex: 50).cursor == 3)
    }

    @Test func shortcutCommitsSelectedCandidate() {
        let s = ASCIIComposition(raw: "py")
        let selected = apply(s, .cycle(1))
        if case .passThrough(let value) = selected.applying(.shortcut) { #expect(value == selected.display) }
        else { Issue.record("Shortcut must pass through") }
    }

    @Test func downUpSequenceInsertsExactlyOnce() {
        var state = ASCIIComposition()
        for letter in "Python3_[]" {
            for kind in [InputEventKind.keyDown, .keyUp, .modifiers, .other] {
                if case .text = InputEventRouting.route(kind, hasComposition: true) {
                    state = apply(state, .insert(String(letter)))
                }
            }
        }
        #expect(state.raw == "Python3_[]")
        // Real auto-repeat arrives as repeated key-downs and must not be filtered out.
        for _ in 0..<3 {
            if case .text = InputEventRouting.route(.keyDown, hasComposition: true) {
                state = apply(state, .insert("x"))
            }
        }
        #expect(state.raw == "Python3_[]xxx")
        #expect(InputEventRouting.route(.keyUp, hasComposition: false) == .passThrough)
        #expect(InputEventRouting.route(.modifiers, hasComposition: true) == .modifiers)
    }
}
