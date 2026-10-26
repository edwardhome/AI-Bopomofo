// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import Testing
@testable import CandidateRanking

@Suite("Correction and prediction validation")
struct TextAssistanceTests {
    @Test func limitsAndUnicode() {
        #expect(!CorrectionRequest(revision: 0, text: " ").isValid)
        #expect(!CorrectionRequest(revision: 0, text: String(repeating: "字", count: 257)).isValid)
        #expect(CorrectionRequest(revision: 0, text: String(repeating: "字", count: 256)).isValid)
        #expect(!CorrectionRequest(revision: 0, text: "hello\nworld").isValid)
        #expect(CorrectionRequest(revision: 0, text: "𠮷野家的招牌").isValid)
        #expect(CorrectionRequest(revision: 0, text: "hello", protectedWords: Array(repeating: "term", count: 5021)).isValid)
        #expect(!CorrectionRequest(revision: 0, text: "hello", protectedWords: Array(repeating: "term", count: 8193)).isValid)
    }
    @Test func suggestionsAreBoundedUniqueAndDoNotContainOriginal() {
        let r = CorrectionRequest(revision: 4, text: "teh", isEnglish: true)
        #expect(r.validated(["teh", "the", "the", "tea", "ten", "tech"]) == ["the", "tea", "ten"])
        #expect(r.validated(["the\n", "中文字", "", String(repeating: "x", count: 257)]).isEmpty)
    }
    @Test(arguments: [
        ("Use `teh` here", "Use `the` here"),
        ("open `file_name", "open `fileName"),
        ("visit https://example.com/teh", "visit https://example.com/the"),
        ("read src/teh.swift", "read src/the.swift"),
        ("use qz_module7", "use qzModule7"),
        ("install PySide6", "install PySide"),
        ("use MacBook", "use Macbook"),
        ("read JSON", "read Json"),
        ("cost 12.5 dollars", "cost 125 dollars"),
        ("# teh title", "teh title"),
        ("**teh** word", "*the* word"),
        ("mail a@b.com", "mail a@c.com"),
        ("Save report_2026.csv", "Save report_2026.csc"),
        ("Open README.md", "Open README.me"),
        ("use --verbose", "use --verify")
    ])
    func protectedSpansCannotChange(_ pair: (String, String)) {
        #expect(CorrectionRequest(revision: 0, text: pair.0).validated([pair.1]).isEmpty)
    }
    @Test func ordinaryTextBesideMarkdownCanBeCorrected() {
        let r = CorrectionRequest(revision: 0, text: "**teh** file `qz_module7`")
        #expect(r.validated(["**the** file `qz_module7`"]) == ["**the** file `qz_module7`"])
        #expect(r.validated(["**the**file `qz_module7`"]).isEmpty)
    }
    @Test func customVocabularyIsProtectedWithoutSubstringFalsePositives() {
        let r = CorrectionRequest(revision: 0, text: "mybrand teh", protectedWords: ["mybrand"])
        #expect(r.validated(["mybrand the"]) == ["mybrand the"])
        #expect(r.validated(["myBrand the"]).isEmpty)
        #expect(TextProtection.signature("swiftly done", words: ["Swift"]).isEmpty)
    }
    @Test func predictionOnlyAppendsAndIsShort() {
        let r = CorrectionRequest(revision: 1, text: "I would like to ", mode: .prediction, isEnglish: true)
        #expect(r.isValid)
        #expect(r.validated(["I would like to learn more"]) == ["I would like to learn more"])
        #expect(r.validated(["You would like to learn", "I would like to `code`", "I would like to 123"]).isEmpty)
        #expect(r.validated([r.text + "a b c d e", r.text + String(repeating: "x", count: 33)]).isEmpty)
        #expect(r.validated([r.text + " "]).isEmpty)
    }
    @Test(arguments: ["use PySide6", "src/foo", "my_name", "**bold", "# title", "use `code", "HTTP", "hi"])
    func predictionDoesNotGuessCodeOrMarkup(_ text: String) {
        #expect(!CorrectionRequest(revision: 0, text: text, mode: .prediction, isEnglish: true).isValid)
    }
    @Test func systemSpellingRangeValidationRejectsSplitUnicodeAndProtectedTokens() {
        let request = CorrectionRequest(revision: 0, text: "𠮷 teh `teh`", isEnglish: false)
        let result = SystemSpelling.apply([
            .init(range: NSRange(location: 1, length: 1), text: "x"),
            .init(range: NSRange(location: 3, length: 3), text: "the"),
            .init(range: NSRange(location: 8, length: 3), text: "the"),
            .init(range: NSRange(location: 999, length: 1), text: "x")
        ], to: request)
        #expect(result == ["𠮷 the `teh`"])
    }
    @Test func systemCandidatesDoNotDuplicateExistingWhitespace() {
        let request = CorrectionRequest(revision: 0, text: "Please send teh report.", isEnglish: true)
        let suggestions = SystemSpelling.apply([
            .init(range: NSRange(location: 12, length: 3), text: "teh "),
            .init(range: NSRange(location: 12, length: 3), text: "the ")
        ], to: request)
        #expect(suggestions == ["Please send the report."])
    }
    @Test func validationPreservesAstralCharactersAndChineseContext() {
        let r = CorrectionRequest(revision: 0, text: "𠮷野家的餐點真好粗")
        #expect(r.validated(["𠮷野家的餐點真好吃"]) == ["𠮷野家的餐點真好吃"])
    }
}

private struct ImmediateProvider: CorrectionProvider {
    let values: [String]?
    func suggest(_ request: CorrectionRequest) async throws -> [String] {
        guard let values else { throw AssistanceError.unavailable }
        return values
    }
}
private actor GateProvider: CorrectionProvider {
    var started = false
    var continuation: CheckedContinuation<[String], Never>?
    func suggest(_ request: CorrectionRequest) async throws -> [String] {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func release(_ values: [String]) { continuation?.resume(returning: values); continuation = nil }
}

@Suite("Shared assistance lifecycle")
@MainActor
struct AssistanceLifecycleTests {
    private func wait(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting for deterministic coordinator state")
    }
    private let request = CorrectionRequest(revision: 1, text: "teh", isEnglish: true)

    @Test func appliesValidatedResultsWithFallback() async {
        let c = AssistanceCoordinator(provider: ImmediateProvider(values: ["the", "the\n"]))
        var result: AssistanceResult?
        c.submit(owner: UUID(), request: request, fallback: ["tea"], isCurrent: { true }) { result = $0 }
        await wait { result != nil }
        #expect(result?.suggestions == ["the", "tea"])
        #expect(result?.status == .ready)
    }
    @Test func unavailableKeepsSystemSuggestions() async {
        let c = AssistanceCoordinator(provider: ImmediateProvider(values: nil))
        var result: AssistanceResult?
        c.submit(owner: UUID(), request: request, fallback: ["the"], isCurrent: { true }) { result = $0 }
        await wait { result != nil }
        #expect(result?.status == .unavailable)
        #expect(result?.suggestions == ["the"])
    }
    @Test func editsOrFocusChangesDiscardReplies() async {
        let provider = GateProvider(), owner = UUID()
        let c = AssistanceCoordinator(provider: provider)
        var applied = false
        c.submit(owner: owner, request: request, isCurrent: { false }) { _ in applied = true }
        while !(await provider.started) { await Task.yield() }
        await provider.release(["the"])
        await wait { !c.isRunning }
        #expect(!applied)
    }
    @Test func cancelledWorkHoldsGlobalSlotUntilActualReturn() async {
        let provider = GateProvider(), owner = UUID()
        let c = AssistanceCoordinator(provider: provider)
        var applied = false, second: AssistanceResult?
        c.submit(owner: owner, request: request, isCurrent: { true }) { _ in applied = true }
        while !(await provider.started) { await Task.yield() }
        c.invalidate(owner: owner)
        c.submit(owner: UUID(), request: request, fallback: ["the"], isCurrent: { true }) { second = $0 }
        #expect(second?.status == .busy)
        #expect(c.isRunning)
        await provider.release(["tea"])
        await wait { !c.isRunning }
        #expect(!applied)
    }
    @Test func timeoutIsBoundedAndLateReplyCannotReplaceFallback() async {
        let provider = GateProvider()
        let c = AssistanceCoordinator(provider: provider, timeout: .milliseconds(25))
        var statuses: [AssistanceStatus] = []
        c.submit(owner: UUID(), request: request, fallback: ["the"], isCurrent: { true }) { statuses.append($0.status) }
        while !(await provider.started) { await Task.yield() }
        await wait { !statuses.isEmpty }
        #expect(statuses == [.timedOut]); #expect(c.isRunning)
        await provider.release(["tea"])
        await wait { !c.isRunning }
        #expect(statuses == [.timedOut])
    }
    @Test func unrelatedControllerCannotCancelCurrentOwner() async {
        let provider = GateProvider()
        let c = AssistanceCoordinator(provider: provider)
        var applied = false
        c.submit(owner: UUID(), request: request, isCurrent: { true }) { _ in applied = true }
        while !(await provider.started) { await Task.yield() }
        c.invalidate(owner: UUID())
        await provider.release(["the"])
        await wait { applied }
    }
    @Test func invalidRequestNeverCallsProvider() async {
        let provider = GateProvider()
        let c = AssistanceCoordinator(provider: provider)
        var result: AssistanceResult?
        c.submit(owner: UUID(), request: .init(revision: 0, text: ""), isCurrent: { true }) { result = $0 }
        #expect(result?.status == .unavailable)
        #expect(!(await provider.started))
    }
}
