import Foundation
import Testing
@testable import CandidateRanking

private let request = CandidateRankingRequest(
    compositionVersion: 42, contextBefore: "這個 FPGA 需要重新",
    candidates: [.init(id: 7, text: "編意"), .init(id: 12, text: "編譯"), .init(id: 29, text: "邊翼")]
)

private struct Stub: CandidateReranker {
    let result: CandidateRankingResult?
    func rank(_ request: CandidateRankingRequest) async throws -> CandidateRankingResult {
        guard let result else { throw RankingError.unavailable }
        return result
    }
}

/// Deliberately ignores cancellation, as a poorly behaved external inference engine might.
private actor Gate: CandidateReranker {
    private var continuation: CheckedContinuation<CandidateRankingResult, Never>?
    private(set) var calls = 0
    func rank(_ request: CandidateRankingRequest) async throws -> CandidateRankingResult {
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        continuation?.resume(returning: .init(compositionVersion: 42, selectedID: 12))
        continuation = nil
    }
}

@Suite("Candidate ranking validation")
struct ValidationTests {
    @Test func selectedIDPromotesOnlyExistingCandidate() {
        let result = CandidateRankingResult(compositionVersion: 42, selectedID: 12)
        #expect(result.reorderedCandidates(for: request)?.map(\.id) == [12, 7, 29])
        #expect(Set(result.reorderedCandidates(for: request)!.map(\.text)) == Set(request.candidates.map(\.text)))
    }

    @Test func rejectsWrongVersionAndInventedID() {
        #expect(CandidateRankingResult(compositionVersion: 41, selectedID: 12).reorderedCandidates(for: request) == nil)
        #expect(CandidateRankingResult(compositionVersion: 42, selectedID: 99).reorderedCandidates(for: request) == nil)
    }

    @Test func rejectsEmptyDuplicateOrOversizedRequests() {
        #expect(!CandidateRankingRequest(compositionVersion: 1, contextBefore: "", candidates: []).isValid)
        #expect(!CandidateRankingRequest(compositionVersion: 1, contextBefore: "", candidates: [request.candidates[0], request.candidates[0]]).isValid)
        #expect(!CandidateRankingRequest(compositionVersion: 1, contextBefore: String(repeating: "a", count: 1025), candidates: request.candidates).isValid)
        #expect(!CandidateRankingRequest(compositionVersion: 1, contextBefore: "", candidates: [.init(id: 0, text: String(repeating: "a", count: 257))]).isValid)
    }

    @Test func traditionalOrderingIsAlwaysAvailable() async throws {
        let result = try await TraditionalReranker().rank(request)
        #expect(result.reorderedCandidates(for: request) == request.candidates)
    }
}

@Suite("Asynchronous coordination")
@MainActor
struct CoordinatorTests {
    private func settle(_ coordinator: RankingCoordinator) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while coordinator.isInferenceRunning && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(!coordinator.isInferenceRunning)
    }

    private func started(_ gate: Gate) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await gate.calls == 0 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(await gate.calls == 1)
    }

    @Test func disabledByDefaultAndReturnsImmediately() {
        let coordinator = RankingCoordinator(reranker: TraditionalReranker())
        #expect(!coordinator.isEnabled)
        #expect(coordinator.submit(request, isStillCurrent: { _ in true }, apply: { _ in Issue.record("Must not apply") }) == request.candidates)
        #expect(!coordinator.isInferenceRunning)
    }

    @Test func appliesOnlyValidCurrentResult() async throws {
        let coordinator = RankingCoordinator(reranker: Stub(result: .init(compositionVersion: 42, selectedID: 12)), timeout: .seconds(2))
        coordinator.isEnabled = true
        var applied: [RankingCandidate]?
        #expect(coordinator.submit(request, isStillCurrent: { $0 == request }, apply: { applied = $0 }) == request.candidates)
        try await settle(coordinator)
        #expect(applied?.map(\.id) == [12, 7, 29])
    }

    @Test(arguments: [true, false])
    func committedOrChangedCompositionCannotApply(disable: Bool) async throws {
        let gate = Gate()
        let coordinator = RankingCoordinator(reranker: gate, timeout: .seconds(2))
        coordinator.isEnabled = true
        coordinator.submit(request, isStillCurrent: { _ in true }, apply: { _ in Issue.record("Stale result applied") })
        try await started(gate)
        if disable { coordinator.isEnabled = false } else { coordinator.invalidate() }
        await gate.release()
        try await settle(coordinator)
    }

    @Test func callerStateCheckRejectsSelectionAndCandidateChanges() async throws {
        let coordinator = RankingCoordinator(reranker: Stub(result: .init(compositionVersion: 42, selectedID: 12)), timeout: .seconds(2))
        coordinator.isEnabled = true
        coordinator.submit(request, isStillCurrent: { _ in false }, apply: { _ in Issue.record("Obsolete state applied") })
        try await settle(coordinator)
    }

    @Test func invalidModelOutputOrUnavailableModelKeepsTraditionalOrdering() async throws {
        for result: CandidateRankingResult? in [nil, .init(compositionVersion: 99, selectedID: 12), .init(compositionVersion: 42, selectedID: 99)] {
            let coordinator = RankingCoordinator(reranker: Stub(result: result), timeout: .seconds(2))
            coordinator.isEnabled = true
            #expect(coordinator.submit(request, isStillCurrent: { _ in true }, apply: { _ in Issue.record("Invalid output applied") }) == request.candidates)
            try await settle(coordinator)
        }
    }

    @Test func timeoutDoesNotWaitForUncooperativeInferenceOrStartMoreWork() async throws {
        let gate = Gate()
        let coordinator = RankingCoordinator(reranker: gate, timeout: .milliseconds(20))
        coordinator.isEnabled = true
        coordinator.submit(request, isStillCurrent: { _ in true }, apply: { _ in Issue.record("Late output applied") })
        try await started(gate)
        try await Task.sleep(for: .milliseconds(70))
        // The UI remains free; only the inference slot is held until actual completion.
        #expect(coordinator.isInferenceRunning)
        #expect(coordinator.submit(request, isStillCurrent: { _ in true }, apply: { _ in Issue.record("Late output applied") }) == request.candidates)
        #expect(await gate.calls == 1)
        await gate.release()
        try await settle(coordinator)
    }

    @Test func repeatedRequestInvalidatesEarlierWorkEvenWithSameVersion() async throws {
        let gate = Gate()
        let coordinator = RankingCoordinator(reranker: gate, timeout: .seconds(2))
        coordinator.isEnabled = true
        coordinator.submit(request, isStillCurrent: { _ in true }, apply: { _ in Issue.record("Earlier request applied") })
        try await started(gate)
        coordinator.submit(request, isStillCurrent: { _ in true }, apply: { _ in Issue.record("Busy slot started a request") })
        await gate.release()
        try await settle(coordinator)
        #expect(await gate.calls == 1)
    }
}
