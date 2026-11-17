// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import Testing
@testable import CandidateRanking

@Suite @MainActor struct ModelServiceClientTests {
    @MainActor final class Transport {
        var replies: [@Sendable (Data?, String?) -> Void] = []
        var cancellations = 0
        func client(timeout: Duration = .seconds(2)) -> ModelServiceClient {
            ModelServiceClient(transport: { [self] _, _, reply in replies.append(reply) },
                               cancel: { [self] in cancellations += 1 }, timeout: timeout)
        }
        func waitForRequest() async { for _ in 0..<100 where replies.isEmpty { try? await Task.sleep(for: .milliseconds(1)) } }
    }
    func failure(_ body: () async throws -> Data) async -> ModelServiceFailure? {
        do { _ = try await body(); return nil } catch { return error as? ModelServiceFailure }
    }
    @Test func timeoutIsDistinctAndLateResponseReleasesLease() async {
        let wire = Transport(), client = wire.client(timeout: .milliseconds(20))
        let error = await failure { try await client.organizeCards(Data()) }
        #expect(error == .timeout); #expect(wire.cancellations == 1)
        #expect(await failure { try await client.organizeCards(Data()) } == .busy)
        wire.replies[0](Data("[]".utf8), nil)
        for _ in 0..<10 { await Task.yield() }
        let next = Task { await failure { try await client.organizeCards(Data()) } }
        for _ in 0..<100 where wire.replies.count < 2 { try? await Task.sleep(for: .milliseconds(1)) }
        #expect(wire.replies.count == 2)
        wire.replies.last?(Data("[]".utf8), nil)
        #expect(await next.value == nil)
    }
    @Test func explicitCancellationDoesNotBecomeTimeout() async {
        let wire = Transport(), client = wire.client()
        let request = Task { await failure { try await client.organizeCards(Data()) } }
        await wire.waitForRequest(); request.cancel()
        #expect(await request.value == .cancelled)
        #expect(wire.cancellations == 1)
        wire.replies.first?(nil, ModelServiceFailure.cancelled.rawValue)
    }
    @Test func typingDoesNotCancelManualCardsButSecureOrDisabledCan() async {
        let wire = Transport(), client = wire.client()
        let request = Task { await failure { try await client.organizeCards(Data()) } }
        await wire.waitForRequest()
        client.cancelBackground()
        #expect(await failure { try await client.correct(Data()) } == .busy)
        #expect(wire.cancellations == 0)
        client.cancelOrganizing()
        #expect(await request.value == .cancelled); #expect(wire.cancellations == 1)
        wire.replies.first?(nil, ModelServiceFailure.cancelled.rawValue)
    }
    @Test func automaticWorkStillYieldsToTyping() async {
        let wire = Transport(), client = wire.client()
        let request = Task { await failure { try await client.organize(Data()) } }
        await wire.waitForRequest()
        #expect(await failure { try await client.correct(Data()) } == .busy)
        #expect(await request.value == .cancelled); #expect(wire.cancellations == 1)
        wire.replies.first?(nil, ModelServiceFailure.cancelled.rawValue)
    }
    @Test func wireFailuresRemainSpecificAndUnknownCodesAreNotDisplayed() async {
        for failureCase in ModelServiceFailure.allCases {
            let client = ModelServiceClient(transport: { _, _, reply in reply(nil, failureCase.rawValue) })
            #expect(await failure { try await client.organizeCards(Data()) } == failureCase)
        }
        #expect(ModelServiceFailure.fromWire("private-model-output") == .generationFailed)
        #expect(!ModelServiceFailure.fromWire("private-model-output").messageKey.contains("private-model-output"))
    }
    @Test func malformedReplyAndOversizedInputAreRejected() async {
        let client = ModelServiceClient(transport: { _, _, reply in reply(Data(repeating: 0, count: 65_537), nil) })
        #expect(await failure { try await client.organizeCards(Data()) } == .invalidResponse)
        #expect(await failure { try await client.organizeCards(Data(repeating: 0, count: 65_537)) } == .invalidRequest)
    }
    @Test func serviceFailureHasCooldownButValidationFailureDoesNot() async {
        let failed = ModelServiceClient(transport: { _, _, reply in reply(nil, ModelServiceFailure.generationFailed.rawValue) })
        #expect(await failure { try await failed.organizeCards(Data()) } == .generationFailed)
        #expect(await failure { try await failed.organizeCards(Data()) } == .coolingDown)
        let invalid = ModelServiceClient(transport: { _, _, reply in reply(nil, ModelServiceFailure.invalidResponse.rawValue) })
        for _ in 0..<2 { #expect(await failure { try await invalid.organizeCards(Data()) } == .invalidResponse) }
    }
    @Test func boundedManualDeadlineDoesNotChangeOtherWork() {
        #expect(ModelRequestKind.organizeCards.timeoutSeconds == 60)
        #expect(ModelRequestKind.organize.timeoutSeconds == 20)
        #expect(ModelRequestKind.correction.timeoutSeconds == 5)
        for kind in [ModelRequestKind.organizeCards, .organize, .correction] {
            #expect(kind.watchdogSeconds > kind.timeoutSeconds)
        }
    }
}
