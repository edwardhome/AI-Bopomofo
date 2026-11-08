// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import Testing
import LearningCore
import LexiconDeployment

/// 使用 Windows 實際交換樣本固定跨平台契約，不碰安裝中的詞庫或啟動輸入法。
@Suite struct SharedLexiconTests {
    private func fixture(_ name: String = "windows-v1.json") throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appendingPathComponent("research/lexicon-learning/shared-fixtures/" + name))
    }

    @Test func windowsIdentityVectorsAndExactUnicodeRoundTrip() throws {
        let document = try LexiconDocument.decode(fixture())
        #expect(document.entries.count == 7)
        #expect(Set(document.entries.map(\.entry_id)).count == 7)
        #expect(document.entries.filter { $0.reading == "H2O" }.map(\.text) == ["H₂O", "H2O"])
        #expect(document.entries.filter { $0.text == "FinFET" }.map(\.reading) == ["finfet", "FinFET"])
        // decode 會以 Mac 實作重算並核對 Windows fixture 內的固定 SHA-256。
        #expect(try LexiconDocument.decode(document.exchangeData()) == document)
        let index = LexiconSnapshot(entries: document.entries)
        #expect(index.chinese("ㄌㄟˇ-ㄐㄧㄥ").map(\.text) == ["磊晶"])
        #expect(index.chinese("ㄌㄟ-ㄐㄧㄥ").isEmpty)
        #expect(index.english("FINFET").exact.count == 2)
    }

    @Test func windowsNegativeCasesAreRejectedByMac() throws {
        struct NegativeCase: Decodable { let name: String; let json: String }
        let cases = try JSONDecoder().decode([NegativeCase].self, from: fixture("windows-negative-cases.json"))
        #expect(cases.count == 8)
        for item in cases {
            #expect(throws: (any Error).self, Comment(rawValue: item.name)) {
                try LexiconDocument.decode(Data(item.json.utf8))
            }
        }
    }

    @Test func unsupportedAliasesNeverBecomeAnnotations() throws {
        var root = try #require(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        var entries = try #require(root["entries"] as? [[String: Any]])
        entries[6]["zh_aliases"] = ["甲烷"]
        root["entries"] = entries
        #expect(throws: (any Error).self) {
            try LexiconDocument.decode(JSONSerialization.data(withJSONObject: root))
        }
    }

    @Test func foreignApprovalStillNeedsLocalConfirmationAndCanRollback() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try DeploymentStore(root: folder)
        let local = LexiconEntry(type: .unicode, reading: "localtest", text: "m²")
        let initial = try await store.preview(LexiconDocument(version: "local-only", entries: [local]).encoded())
        _ = try await store.approve(initial.token)

        var incoming = try LexiconDocument.decode(fixture())
        incoming.document_type = "approved"
        for i in incoming.entries.indices {
            incoming.entries[i].review.status = .approved
        }
        let cancelled = try await store.preview(incoming.exchangeData())
        await store.cancel(cancelled.token)
        await #expect(throws: (any Error).self) { try await store.approve(cancelled.token) }
        #expect(await store.snapshot().entries.map(\.entry_id) == [local.entry_id])

        let preview = try await store.preview(incoming.exchangeData())
        #expect(await store.snapshot().entries.count == 1)
        let deployed = try await store.approve(preview.token)
        #expect(deployed.entries.count == 8)
        #expect(deployed.entries.contains { $0.entry_id == local.entry_id })
        #expect(deployed.english("H2O").exact.map(\.text) == ["H₂O", "H2O"])
        let repeated = try await store.preview(incoming.exchangeData())
        #expect(try await store.approve(repeated.token).entries.count == 8)
        let restored = try await store.rollback()
        #expect(restored.entries.map(\.entry_id) == [local.entry_id])
        // 已持有的輸入快照必須仍能用，回復不應銷毀正在組字的候選。
        #expect(deployed.chinese("ㄌㄟˇ-ㄐㄧㄥ").map(\.text) == ["磊晶"])
    }
}
