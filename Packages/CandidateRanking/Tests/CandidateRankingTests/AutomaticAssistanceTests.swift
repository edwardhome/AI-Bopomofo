// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Testing
@testable import CandidateRanking

@Suite struct AutomaticAssistanceTests {
    @Test func onlyCompleteEligibleCompositionsAreScheduled() {
        #expect(AutomaticAssistancePolicy.mode(text: "我再德國", english: false, cursorAtEnd: true) == .correction)
        #expect(AutomaticAssistancePolicy.mode(text: "我", english: false, cursorAtEnd: true) == nil)
        #expect(AutomaticAssistancePolicy.mode(text: "我再德國", english: false, cursorAtEnd: false) == nil)
        #expect(AutomaticAssistancePolicy.mode(text: "我再德國", english: false, cursorAtEnd: true, suppressed: true) == nil)
        #expect(AutomaticAssistancePolicy.mode(text: "al2o3", english: true, cursorAtEnd: true) == .technical)
        #expect(AutomaticAssistancePolicy.mode(text: "sio2", english: true, cursorAtEnd: true, hasCandidates: true) == nil)
        for literal in ["mm", "src/main.swift", "--flag", "a_b", "I would like ", "`code`"] {
            #expect(AutomaticAssistancePolicy.mode(text: literal, english: true, cursorAtEnd: true) == nil)
        }
    }
    @Test func dismissAndRateLimitDoNotRetriggerIdenticalText() {
        var gate = AutomaticAssistanceGate()
        let attempt1 = gate.begin(key: "first", now: 10)
        #expect(attempt1)
        let attempt2 = gate.begin(key: "first", now: 20)
        #expect(!attempt2)
        let attempt3 = gate.begin(key: "edited", now: 10.5)
        #expect(!attempt3)
        #expect(gate.delay(now: 10.5) == 1.5)
        let attempt4 = gate.begin(key: "edited", now: 12)
        #expect(attempt4)
        gate.resetComposition()
        let attempt5 = gate.begin(key: "edited", now: 12.1)
        #expect(!attempt5)
        let attempt6 = gate.begin(key: "edited", now: 14)
        #expect(attempt6)
    }
    @Test func ordinaryKeysNeverSelectSuggestions() {
        for selected in 0...2 {
            #expect(AutomaticSuggestionInteraction.action(key: .ordinary, selected: selected, count: 3) == .replayOriginal)
            #expect(AutomaticSuggestionInteraction.action(key: .tab, selected: selected, count: 3, shortcut: true) == .replayOriginal)
        }
        #expect(AutomaticSuggestionInteraction.action(key: .enter, selected: 0, count: 3) == .replayOriginal)
        #expect(AutomaticSuggestionInteraction.action(key: .enter, selected: 1, count: 3) == .accept(1))
        #expect(AutomaticSuggestionInteraction.action(key: .tab, selected: 0, count: 3) == .select(1))
        #expect(AutomaticSuggestionInteraction.action(key: .backTab, selected: 0, count: 3) == .select(2))
        #expect(AutomaticSuggestionInteraction.action(key: .escape, selected: 1, count: 3) == .dismiss)
    }
    @Test func technicalTypographyPreservesFormulaIdentity() {
        let request = CorrectionRequest(revision: 0, text: "al2o3", mode: .technical, isEnglish: true)
        #expect(request.validated(["Al₂O₃", "Al₂O₄", "AlO₃", "SiO₂", "Al₂O₃\u{200b}", "Al₂O₃"]) == ["Al₂O₃"])
        #expect(CorrectionRequest(revision: 0, text: "so42-", mode: .technical, isEnglish: true).validated(["SO₄²⁻"]) == ["SO₄²⁻"])
        #expect(CorrectionRequest(revision: 0, text: "upsilon", mode: .technical, isEnglish: true).validated(["υ", "λ"]) == ["υ"])
    }
    @Test func technicalSuggestionsDoNotBypassPrivateTermsOrNormalCorrectionRules() {
        let protected = CorrectionRequest(revision: 0, text: "al2o3", mode: .technical, isEnglish: true, protectedWords: ["AL2O3"])
        #expect(protected.validated(["Al₂O₃"]).isEmpty)
        let normal = CorrectionRequest(revision: 0, text: "al2o3", isEnglish: true)
        #expect(normal.validated(["Al₂O₃"]).isEmpty)
        #expect(CorrectionRequest(revision: 0, text: "recieve", mode: .technical, isEnglish: true).validated(["receive"]) == ["receive"])
        #expect(!CorrectionRequest(revision: 0, text: "src/main.swift", mode: .technical, isEnglish: true).isValid)
    }
    @Test func chineseSuggestionsKeepOriginalMeaningConstraints() {
        let request = CorrectionRequest(revision: 0, text: "我在去一次")
        #expect(request.validated(["我再去一次", "我去一次", "我再去一次！"]) == ["我再去一次"])
        let water = CorrectionRequest(revision: 0, text: "我喝了500ML的水")
        #expect(water.validated(["我喝了500mL的水", "我喝了500百萬的水"]) == ["我喝了500mL的水"])
    }
}
