// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import Testing
@testable import MixedInputCore

@Suite("Engineering and science candidates")
struct EngineeringLexiconTests {
    private let lexicon = TechnicalLexicon()

    private func edit(_ state: ASCIIComposition, _ action: ASCIIComposition.Action,
                      lexicon: TechnicalLexicon = TechnicalLexicon()) -> ASCIIComposition {
        guard case .updated(let next) = state.applying(action, lexicon: lexicon) else {
            Issue.record("Expected composition update"); return state
        }
        return next
    }

    private func select(_ output: String, raw: String) -> ASCIIComposition {
        let state = ASCIIComposition(raw: raw)
        guard let index = state.candidates.firstIndex(of: output) else {
            Issue.record("Missing candidate: \(output)"); return state
        }
        return edit(state, .select(index))
    }

    @Test func bundledResourceAndEveryAliasAreReachable() {
        let terms = EngineeringLexicon.bundled.terms
        #expect(terms.count == 103)
        #expect(Set(terms.map(\.id)).count == terms.count)
        for term in terms {
            for alias in term.aliases {
                let matches = EngineeringLexicon.bundled.matches(alias).exact
                for output in term.outputs {
                    #expect(matches.contains { $0.text == output && $0.annotation == term.annotation })
                }
            }
        }
    }

    @Test func prefixThresholdAndShortExactAliases() {
        #expect(lexicon.completions(for: "s").isEmpty)
        #expect(lexicon.completions(for: "si") == ["Si"])
        #expect(lexicon.completions(for: "ge") == ["Ge"])
        #expect(!lexicon.completions(for: "la").contains("λ"))
        #expect(lexicon.completions(for: "lam").contains("λ"))
        #expect(lexicon.completions(for: "sio") == ["SiO₂", "SiO2"])
        #expect(lexicon.completions(for: "uF").contains("µF"))
        // 原本英文詞庫仍以兩字元補全。
        #expect(lexicon.completions(for: "py").contains("Python"))
    }

    @Test(arguments: [("sio2", "SiO₂"), ("i2c", "I²C"), ("finfet", "FinFET"),
                      ("lambda", "λ"), ("m2", "m²"), ("so42-", "SO₄²⁻")])
    func rawFirstAndExplicitCommit(pair: (String, String)) {
        let (raw, output) = pair
        let state = ASCIIComposition(raw: raw)
        #expect(state.candidates.first == raw)
        #expect(state.selectedIndex == 0)
        if case .commit(let value) = state.applying(.enter) { #expect(value == raw) }
        else { Issue.record("Expected raw commit") }
        let selected = select(output, raw: raw)
        #expect(selected.raw == raw)
        #expect(selected.display == output)
        #expect(selected.candidateItems[selected.selectedIndex].annotation != nil)
        if case .commit(let value) = selected.applying(.enter) { #expect(value == output) }
        else { Issue.record("Expected candidate commit") }
        #expect(edit(selected, .escape).display == raw)
        if case .passThrough(let value) = selected.applying(.shortcut) { #expect(value == output) }
        else { Issue.record("Expected shortcut passthrough") }
    }

    @Test func caseAmbiguityIsOrderedButNeverAutomaticallySelected() {
        #expect(lexicon.completions(for: "m2").first == "m²")
        #expect(lexicon.completions(for: "M2").first == "M²")
        #expect(lexicon.completions(for: "m2").contains("M²"))
        let notes = lexicon.candidateItems(for: "m2").compactMap(\.annotation)
        #expect(notes.contains("平方公尺：面積"))
        #expect(notes.contains("光束傳輸因子"))
        #expect(ASCIIComposition(raw: "SIO2").display == "SIO2")
        #expect(lexicon.completions(for: "SIO2").contains("SiO₂"))
    }

    @Test func orderingDeduplicationAndPrivateTermsStaySeparate() {
        let custom = TechnicalLexicon(custom: ["sio2Custom", "SiO2", "Github", "sio2Custom"])
        #expect(custom.completions(for: "sio2") == ["SiO₂", "SiO2", "sio2Custom"])
        #expect(custom.completions(for: "sio") == ["SiO2", "sio2Custom", "SiO₂"])
        #expect(custom.completions(for: "github").filter { $0 == "GitHub" }.count == 1)
        #expect(!custom.words.contains("SiO₂"))
        #expect(!TechnicalLexicon.isValid("SiO₂"))
        #expect(TechnicalLexicon.userTerms(from: "SiO₂ _english_sio2\nCustomTerm _english_customterm") == ["CustomTerm"])
        let many = TechnicalLexicon(custom: (0..<20).map { "sio2Custom\($0)" })
        #expect(many.completions(for: "sio2").count == 8)
        #expect(many.completions(for: "sio2").prefix(2) == ["SiO₂", "SiO2"])
    }

    @Test(arguments: ["linux/i2c.h", "my_sio2", "sio2file", "voltage sio2", "https://sio2", "--sio2", "sio2\n"])
    func onlyWholeCompositionMatches(_ raw: String) {
        #expect(lexicon.candidateItems(for: raw).allSatisfy { $0.source != .engineering })
    }

    @Test func unicodeEditingPreservesSubscriptsAndCursor() {
        let selected = select("SiO₂", raw: "sio2")
        #expect(edit(selected, .insert("x")).raw == "SiO₂x")
        #expect(edit(selected, .backspace).raw == "SiO")
        let left = edit(selected, .left)
        #expect(left.raw == "SiO₂")
        #expect(left.cursor == 3)
        #expect(edit(left, .delete).raw == "SiO")
        #expect(edit(left, .insert("2")).raw == "SiO2₂")
        #expect(edit(edit(selected, .home), .delete).raw == "iO₂")
        #expect(edit(edit(selected, .home), .end).cursor == 4)
        #expect(edit(select("λ", raw: "lambda"), .insert("x")).raw == "λx")
    }

    @Test func editingUsesGraphemeBoundariesAndUTF16Positions() throws {
        // 數學補充平面字元與結合附加符號，不能拆掉 surrogate 或組合字元。
        let data = Data(#"{"version":1,"terms":[{"id":"test","category":"test","aliases":["glyph"],"outputs":["𝛌x́"],"annotation":"測試字形","sources":["test"]}]}"#.utf8)
        let lex = TechnicalLexicon(engineering: EngineeringLexicon(data: data))
        let state = ASCIIComposition(raw: "glyph", lexicon: lex)
        let index = try #require(state.candidates.firstIndex(of: "𝛌x́"))
        let selected = edit(state, .select(index), lexicon: lex)
        #expect(selected.displayCursor == 4)
        let left = edit(selected, .left, lexicon: lex)
        #expect(left.cursor == 2)
        #expect(edit(left, .delete, lexicon: lex).raw == "𝛌")
        #expect(edit(selected, .backspace, lexicon: lex).raw == "𝛌")
        #expect(edit(left, .backspace, lexicon: lex).raw == "x́")
        #expect(edit(left, .left, lexicon: lex).cursor == 0)
        #expect(edit(left, .right, lexicon: lex).cursor == 4)
    }

    @Test func toggleRestoresRawAndPreservesAcceptedUnicode() {
        let disabled = TechnicalLexicon(custom: ["sioCustom"], engineeringEnabled: false)
        let selected = select("SiO₂", raw: "sio2")
        let raw = selected.rebuilding(lexicon: disabled)
        #expect(raw.raw == "sio2")
        #expect(raw.selectedIndex == 0)
        #expect(!raw.hasEngineeringCandidates)
        let accepted = edit(selected, .insert("x")).rebuilding(lexicon: disabled)
        #expect(accepted.raw == "SiO₂x")
        #expect(accepted.cursor == 5)
        #expect(disabled.completions(for: "sio") == ["sioCustom"])
    }

    @Test func malformedOrUnsupportedResourceFallsBackToExistingWords() {
        for text in ["", "{}", #"{"version":99,"terms":[]}"#,
                     #"{"version":1,"terms":[{"id":"bad","category":"x","aliases":["bad"],"outputs":["\n"],"annotation":"x","sources":["test"]}]}"#] {
            let catalog = EngineeringLexicon(data: Data(text.utf8))
            #expect(catalog.terms.isEmpty)
            let lex = TechnicalLexicon(custom: ["MyTerm"], engineering: catalog)
            #expect(lex.completions(for: "py").contains("Python"))
            #expect(lex.completions(for: "my") == ["MyTerm"])
            #expect(!ASCIIComposition(raw: "sio2", lexicon: lex).hasEngineeringCandidates)
        }
    }

    @Test func shiftWordAndHeldSymbolEditingUseSameUnicodeBuffer() {
        let selected = select("SiO₂", raw: "Sio2")
        let word = ShiftLetterSession(composition: selected, mode: .word)
        if case .commit(let text) = word.applying(.insert(" "), shiftHeld: false) {
            #expect(text == "SiO₂ ")
        } else { Issue.record("Space must commit the explicitly selected word") }
        let withSymbol = edit(selected, .insert("+"))
        #expect(withSymbol.raw == "SiO₂+")
        #expect(edit(withSymbol, .backspace).raw == "SiO₂")
        let initial = ShiftLetterSession(composition: ASCIIComposition(raw: "S"))
        if case .commitAndContinue(let text, let upper) = initial.applying(.insert("I"), shiftHeld: true) {
            #expect(text == "SI")
            #expect(upper.mode == .uppercase)
        } else { Issue.record("Continuous uppercase must remain literal") }
    }

    @Test func literalInputStillRejectsUnicodeAndControlInjection() {
        let state = ASCIIComposition(raw: "x")
        for literal in ["₂", "λ", "\n", "\u{202E}"] {
            if case .rejected = state.applying(.insert(literal)) {} else { Issue.record("Unexpected literal acceptance") }
        }
        #expect(ASCIIComposition(raw: "x₂").raw == "x")
    }
}
