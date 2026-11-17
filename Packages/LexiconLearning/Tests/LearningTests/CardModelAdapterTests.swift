// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import Testing
import LearningCore
import LearningOrganizer
import LearningStorage

@Suite struct CardModelAdapterTests {
    func request() throws -> CardOrganizationRequest {
        var graph = CardGraph(); let c = LexiconConcept(definition: "波的相鄰波峰之間的距離", domain: "物理")
        graph.concepts.append(c)
        try graph.editName(concept: c.id, text: "波長", kind: "zh", codes: [], readings: ["ㄅㄛ-ㄔㄤˊ"])
        graph.origins.append(.init(subject: c.id, source: "user", reference: "private-history-not-for-model"))
        return .init(revision: "private-revision", graph: graph)
    }
    @Test func promptHasNamesReadingsButNoIdentifiersOrHistory() throws {
        let r = try request(), prompt = try CardModelInput(r).prompt()
        #expect(prompt.contains("波長")); #expect(prompt.contains("ㄅㄛ-ㄔㄤˊ"))
        #expect(!prompt.contains(r.graph.concepts[0].id)); #expect(!prompt.contains("private-"))
        #expect(prompt.utf8.count < (try r.encoded()).count)
    }
    @available(macOS 26.0, *) @Test func typedActionsCannotPutCodeIntoChineseName() throws {
        let r = try request(), adapter = CardModelInput(r)
        let output = CardModelSuggestions(changes: [
            .init(card: 0, action: .chineseName(text: "波距", reading: "ㄅㄛ-ㄐㄩˋ"), reason: "待確認別名"),
            .init(card: 0, action: .englishName(text: "wavelength", code: "wavelength"), reason: "英文名稱"),
            .init(card: 0, action: .symbol(text: "λ", code: "lambda"), reason: "常用符號")])
        let batch = try r.validateServiceResponse(adapter.validatedResponse(output))
        #expect(batch.changes.count == 3)
        #expect(batch.changes[0].code.isEmpty); #expect(batch.changes[1].reading.isEmpty)
        #expect(batch.changes.allSatisfy { $0.concept_id == r.graph.concepts[0].id })
        #expect(r.graph.forms.count == 1) // 只建立提議，沒有改動卡片或部署。
    }
    @available(macOS 26.0, *) @Test func invalidProposalsAreIsolatedAndReportedWithoutWeakeningValidation() throws {
        let r = try request(), adapter = CardModelInput(r)
        let invalid: [CardModelSuggestion] = [
            .init(card: -1, action: .definition("無效"), reason: "測試"),
            .init(card: 1, action: .definition("不存在"), reason: "測試"),
            .init(card: 0, action: .chineseName(text: "波長", reading: "bo chang"), reason: "測試"),
            .init(card: 0, action: .englishName(text: "wave", code: "with spaces"), reason: "測試"),
            .init(card: 0, action: .related(card: 4), reason: "測試"),
            .init(card: 0, action: .splitName(name: 99, meaning: "無效"), reason: "測試")]
        for bad in invalid {
            let response = try r.validateServiceResponse(adapter.validatedResponse(.init(changes: [
                .init(card: 0, action: .symbol(text: "λ", code: "lambda"), reason: "有效"), bad])))
            #expect(response.changes.count == 1); #expect(response.rejected.count == 1)
            #expect(response.rejected[0].index == 2)
        }
    }
    @available(macOS 26.0, *) @Test func emptyResponseAndCountLimit() throws {
        let r = try request(), adapter = CardModelInput(r)
        #expect(try r.validateServiceResponse(adapter.validatedResponse(.init(changes: []))).changes.isEmpty)
        let change = CardModelSuggestion(card: 0, action: .definition("距離"), reason: "待確認")
        #expect(throws: Error.self) { try adapter.validatedResponse(.init(changes: Array(repeating: change, count: 5))) }
    }
    @available(macOS 26.0, *) @Test func modelCannotReferenceUnselectedCard() throws {
        var r = try request(); r.graph.concepts.append(.init(definition: "頻率"))
        r.graph = r.graph.selecting([r.graph.concepts[0].id])
        let response = try r.validateServiceResponse(CardModelInput(r).validatedResponse(.init(changes: [
            .init(card: 0, action: .merge(card: 1), reason: "無效引用")])))
        #expect(response.changes.isEmpty); #expect(response.rejected == [.init(index: 1, reason: .reference)])
    }
    @Test func malformedEnvelopeCannotHideInvalidAcceptedChanges() throws {
        let r = try request()
        #expect(throws: Error.self) { try r.validateServiceResponse(Data("{broken".utf8)) }
        let bad = CardChange(operation: "sql", concept: r.graph.concepts[0].id, reason: "測試")
        #expect(throws: Error.self) { try r.validateServiceResponse(JSONEncoder().encode(CardOrganizationResponse(changes: [bad], rejected: []))) }
        for rejected in [[CardProposalRejection(index: 0, reason: .fields)], [.init(index: 2, reason: .fields)], [.init(index: 1, reason: .fields), .init(index: 1, reason: .reading)]] {
            #expect(throws: Error.self) { try r.validateServiceResponse(JSONEncoder().encode(CardOrganizationResponse(changes: [], rejected: rejected))) }
        }
    }
    @available(macOS 26.0, *) @Test func originalInvalidReadingAndSelfLinkReproduction() throws {
        let r = try request()
        let result = try r.validateServiceResponse(CardModelInput(r).validatedResponse(.init(changes: [
            .init(card: 0, action: .englishName(text: "wavelength", code: "wavelength"), reason: "英文名稱"),
            .init(card: 0, action: .chineseName(text: "波峰間距", reading: "ㄅㄛ-ㄆㄧㄥˊ-ㄐㄧㄢˋ"), reason: "錯誤讀音"),
            .init(card: 0, action: .symbol(text: "λ", code: "lambda"), reason: "常用符號"),
            .init(card: 0, action: .related(card: 0), reason: "錯誤自我關聯")
        ])))
        #expect(result.changes.map(\.text) == ["wavelength", "λ"])
        #expect(result.rejected == [.init(index: 2, reason: .reading), .init(index: 4, reason: .reference)])
    }
    @Test func largePromptFailsBeforeModelInference() throws {
        var r = try request()
        for index in 0..<15 {
            let c = LexiconConcept(definition: String(repeating: "合成詞義", count: 60), domain: "測試")
            r.graph.concepts.append(c)
            try r.graph.editName(concept: c.id, text: "word" + String(index), kind: "en", codes: [], readings: [])
        }
        #expect(throws: Error.self) { try CardModelInput(r).prompt() }
    }

    @Test func cancelledSavedProposalDoesNotReappear() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let bytes = Data("synthetic-proposal".utf8)
        try CardProposalPersistence.write(bytes, to: path)
        #expect(try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? Int == 0o600)
        #expect(try CardProposalPersistence.discard(bytes, at: path))
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }
    @Test func staleCleanupDoesNotEraseNewerProposal() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let old = Data("old".utf8), newer = Data("new".utf8)
        try CardProposalPersistence.write(newer, to: path)
        #expect(try !CardProposalPersistence.discard(old, at: path))
        #expect(try Data(contentsOf: path) == newer)
    }

}
