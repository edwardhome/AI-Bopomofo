import Foundation

public struct RankingCandidate: Codable, Equatable, Sendable {
    public let id: Int
    public let text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

/// The caller supplies only current, uncommitted composition text. Never fetches client text.
public struct CandidateRankingRequest: Codable, Equatable, Sendable {
    public let compositionVersion: UInt64
    public let contextBefore: String
    public let candidates: [RankingCandidate]

    public init(compositionVersion: UInt64, contextBefore: String, candidates: [RankingCandidate]) {
        self.compositionVersion = compositionVersion
        self.contextBefore = contextBefore
        self.candidates = candidates
    }

    public var isValid: Bool {
        !candidates.isEmpty && candidates.count <= 32 && contextBefore.utf8.count <= 1024
            && Set(candidates.map(\.id)).count == candidates.count
            && candidates.allSatisfy { !$0.text.isEmpty && $0.text.utf8.count <= 256 }
    }
}

public struct CandidateRankingResult: Equatable, Sendable {
    public let compositionVersion: UInt64
    public let selectedID: Int

    public init(compositionVersion: UInt64, selectedID: Int) {
        self.compositionVersion = compositionVersion
        self.selectedID = selectedID
    }

    /// A model can only promote an existing ID; it cannot insert or change text.
    public func reorderedCandidates(for request: CandidateRankingRequest) -> [RankingCandidate]? {
        guard request.isValid, compositionVersion == request.compositionVersion,
            let selected = request.candidates.first(where: { $0.id == selectedID })
        else { return nil }
        return [selected] + request.candidates.filter { $0.id != selectedID }
    }
}

public protocol CandidateReranker: Sendable {
    func rank(_ request: CandidateRankingRequest) async throws -> CandidateRankingResult
}

public enum RankingError: Error, Sendable {
    case invalidRequest
    case unavailable
    case unsupportedLanguage
}

public struct TraditionalReranker: CandidateReranker {
    public init() {}

    public func rank(_ request: CandidateRankingRequest) async throws -> CandidateRankingResult {
        guard request.isValid, let first = request.candidates.first else {
            throw RankingError.invalidRequest
        }
        return CandidateRankingResult(compositionVersion: request.compositionVersion, selectedID: first.id)
    }
}

/// Scheduling only: integration must invalidate on every edit, selection, commit, mode/app change,
/// deactivation, or secure input. The callback must check current composition and candidate identity.
/// This class never commits text or reads the surrounding application.
@MainActor
public final class RankingCoordinator {
    public var isEnabled = false {
        didSet { if !isEnabled { invalidate() } }
    }
    public private(set) var isInferenceRunning = false
    private let reranker: any CandidateReranker
    private let timeout: Duration
    private let clock = ContinuousClock()
    private var pendingID: UUID?
    private var inference: Task<Void, Never>?
    private var timer: Task<Void, Never>?

    public init(reranker: any CandidateReranker, timeout: Duration = .milliseconds(150)) {
        self.reranker = reranker
        self.timeout = max(.zero, timeout)
    }

    deinit {
        inference?.cancel()
        timer?.cancel()
    }

    public func invalidate() {
        pendingID = nil
        inference?.cancel()
        timer?.cancel()
        timer = nil
        // Keep the slot occupied until inference actually returns, even if it ignores cancellation.
    }

    /// Returns traditional ordering synchronously. AI results are optional, later callbacks.
    @discardableResult
    public func submit(
        _ request: CandidateRankingRequest,
        isStillCurrent: @escaping @MainActor @Sendable (CandidateRankingRequest) -> Bool,
        apply: @escaping @MainActor @Sendable ([RankingCandidate]) -> Void
    ) -> [RankingCandidate] {
        invalidate()
        guard isEnabled, request.isValid, !isInferenceRunning, timeout > .zero else {
            return request.candidates
        }
        let id = UUID()
        pendingID = id
        isInferenceRunning = true
        let deadline = clock.now.advanced(by: timeout)
        let reranker = self.reranker
        inference = Task.detached(priority: .utility) { [weak self] in
            let result = try? await reranker.rank(request)
            await self?.finish(id: id, request: request, result: result, deadline: deadline,
                               isStillCurrent: isStillCurrent, apply: apply)
        }
        timer = Task { [weak self] in
            do { try await ContinuousClock().sleep(until: deadline) } catch { return }
            guard let self, self.pendingID == id else { return }
            self.invalidate()
        }
        return request.candidates
    }

    private func finish(
        id: UUID, request: CandidateRankingRequest, result: CandidateRankingResult?,
        deadline: ContinuousClock.Instant,
        isStillCurrent: @MainActor @Sendable (CandidateRankingRequest) -> Bool,
        apply: @MainActor @Sendable ([RankingCandidate]) -> Void
    ) {
        isInferenceRunning = false
        inference = nil
        guard pendingID == id else { return }
        pendingID = nil
        timer?.cancel()
        timer = nil
        guard isEnabled, clock.now < deadline, isStillCurrent(request),
            let candidates = result?.reorderedCandidates(for: request)
        else { return }
        apply(candidates)
    }
}
