// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import Testing
@testable import LearningCore
import LearningStorage
import LexiconDeployment
import LearningOrganizer

@Suite struct CardTests {
    func sample() throws -> CardGraph {
        var g = CardGraph(); let c = LexiconConcept(definition: "銀行", domain: "金融"); g.concepts.append(c)
        try g.editName(concept: c.id, text: "銀行", kind: "zh", codes: [], readings: ["ㄧㄣˊ-ㄏㄤˊ"])
        try g.editName(concept: c.id, text: "bank", kind: "en", codes: ["bank"], readings: [])
        let r = LexiconConcept(definition: "河岸"); g.concepts.append(r)
        let form = g.forms.first { $0.text == "bank" }!
        let name = ConceptForm(concept: r.id, form: form.id); g.names.append(name)
        g.bindings.append(.init(name: name.id, code: "bank", type: .english)); try g.validated(); return g
    }
    @Test func manyToManyRoundTripAndDistinctSenses() throws {
        let g = try sample(), value = try g.exchange(version: "fixture-2")
        let decoded = try UnifiedSQLite.decode(UnifiedSQLite.encode(value))
        #expect(decoded == value); #expect(decoded.cards?.concepts.count == 2)
        #expect(try g.projectedEntries().filter { $0.text == "bank" }.count == 1)
    }
    @Test func editingSharedFormDoesNotChangeOtherSense() throws {
        var g = try sample(); let name = g.names.last!
        try g.editName(concept: name.concept_id, nameID: name.id, text: "riverbank", kind: "en", codes: ["riverbank"], readings: [])
        #expect(g.forms.contains { $0.text == "bank" }); #expect(g.forms.contains { $0.text == "riverbank" })
        try g.removeName(name.id); #expect(g.forms.contains { $0.text == "bank" })
    }
    @Test func legacyMigrationDoesNotInferSynonymy() throws {
        let a = LexiconEntry(type: .zhPhrase, reading: "ㄐㄧㄚˇ-ㄨㄢˊ", text: "甲烷")
        let b = LexiconEntry(type: .unicode, reading: "ch4", text: "CH₄")
        let old = UnifiedLexicon(document: LexiconDocument(entries: [a,b]), relations: [.init(source: a.entry_id, target: b.entry_id)])
        let g = try CardGraph.migrating(old)
        #expect(g.concepts.count == 2); #expect(g.legacy_links.count == 1)
        #expect(try g.projectedEntries().map(\.entry_id) == [a.entry_id,b.entry_id])
        #expect(try CardGraph.migrating(old) == g)
    }
    @Test func orphanDuplicateAndWrongReadingAreRejected() throws {
        let g = try sample(); var bad = g
        bad.names[0].concept_id = CardGraph.newID(); #expect(throws: Error.self) { try bad.validated() }
        bad = g; bad.concepts.append(bad.concepts[0]); #expect(throws: Error.self) { try bad.validated() }
        bad = g; bad.bindings[0].reading_id = ""; #expect(throws: Error.self) { try bad.validated() }
        bad = g; bad.forms[0].text = "壞\u{0}字"; #expect(throws: Error.self) { try bad.validated() }
    }
    @Test func selectionDoesNotPullAllRelatedCards() throws {
        var g = try sample()
        g.relations = [.init(from: g.concepts[0].id, to: g.concepts[1].id, kind: "related")]
        let part = g.selecting([g.concepts[0].id]); try part.validated()
        #expect(part.concepts.count == 1); #expect(part.relations.isEmpty)
        #expect(part.forms.contains { $0.text == "bank" })
    }
    @Test func proposalApprovalIsPerOperationAndRevisionBound() throws {
        let g = try sample(), c = g.concepts[0].id
        let a = CardChange(operation: "set_definition", concept: c, text: "金融機構", reason: "補充意思")
        let b = CardChange(operation: "add_name", concept: c, text: "financial institution", kind: "en", code: "financial", reason: "待查證別名")
        let batch = CardProposalBatch(base: "base", changes: [a,b])
        let accepted = try batch.applying(selected: [a.id], to: g, revision: "base")
        #expect(accepted.concepts[0].definition == "金融機構"); #expect(accepted.forms == g.forms)
        #expect(throws: Error.self) { try batch.applying(selected: [b.id], to: g, revision: "changed") }
        #expect(try batch.applying(selected: [], to: g, revision: "base") == g)
    }
    @Test func unicodeAndMultipleReadingsSurviveExchange() throws {
        var g = try sample(); let c = g.concepts[0].id
        try g.editName(concept: c, text: "行", kind: "zh", codes: [], readings: ["ㄏㄤˊ","ㄒㄧㄥˊ"])
        try g.editName(concept: c, text: "SiO₂", kind: "symbol", codes: ["sio2"], readings: [])
        let decoded = try UnifiedSQLite.decode(UnifiedSQLite.encode(g.exchange()))
        #expect(decoded.cards == g)
        #expect(decoded.document.entries.contains { $0.text == "SiO₂" })
    }
    @Test func approvalCancelRollbackAndRecoveryAcrossVersions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DeploymentStore(root: root)
        let old = LexiconDocument(version: "old", entries: [LexiconEntry(type: .english, reading: "bank", text: "bank")])
        let p = try await store.preview(old.encoded()); let v1 = try await store.approve(p.token)
        let g = try sample(), draft = try await store.previewCards(g, expectedRevision: v1.revision)
        #expect(await store.snapshot().cards == nil)
        await store.cancel(draft.token); await #expect(throws: Error.self) { try await store.approve(draft.token) }
        let p2 = try await store.previewCards(g, expectedRevision: v1.revision); let v2 = try await store.approve(p2.token)
        #expect(v2.cards == g)
        #expect(try await DeploymentStore(root: root).load().cards == g)
        let exported = try await store.exportSQLite(); #expect(try UnifiedSQLite.decode(exported).cards == g)
        try Data("broken".utf8).write(to: root.appendingPathComponent(v2.revision).appendingPathComponent("lexicon.sqlite"))
        #expect(try await DeploymentStore(root: root).load().cards == g)
        let back = try await store.rollback(); #expect(back.cards == nil); #expect(back.entries == v1.entries)
    }
    @Test func utf16DefinitionProjectionPreservesOriginalAndSources() throws {
        var g = try sample(); g.concepts[0].definition = String(repeating: "𠀀", count: 128)
        g.origins.append(.init(subject: g.names[0].id, source: "fixture", reference: "https://example.org/reference"))
        let value = try g.exchange()
        #expect(value.document.entries[0].annotation?.utf16.count == 80)
        #expect(try UnifiedSQLite.decode(UnifiedSQLite.encode(value)).cards == g)
    }
    @Test func mergingSharedNamesAndSplittingPreservesBindings() throws {
        var g = try sample(); let from = g.concepts[0].id, to = g.concepts[1].id
        try g.mergeConcept(from, into: to)
        #expect(g.concepts.count == 1); #expect(g.bindings.count == 2)
        let name = g.names.first { n in g.forms.contains { $0.id == n.form_id && $0.kind == "en" } }!
        let split = CardChange(operation: "split_name", concept: to, target: name.id, text: "另一詞義", reason: "人工確認")
        let next = try split.applying(to: g, source: "user")
        #expect(next.concepts.count == 2); #expect(next.bindings == g.bindings)
    }
    @Test func modelOutputIsUntrustedAndDraftRevisionBound() throws {
        let g = try sample(), request = CardOrganizationRequest(revision: "r", graph: g)
        let bad = CardChange(operation: "sql", concept: g.concepts[0].id, reason: "not permitted")
        #expect(throws: Error.self) { try request.validateResponse(JSONEncoder().encode([bad])) }
        #expect(throws: Error.self) { try request.validateResponse(Data("[{".utf8)) }
        let a = CardChange(operation: "set_definition", concept: g.concepts[0].id, text: "金融機構", reason: "待確認")
        var batch = try request.validateResponse(JSONEncoder().encode([a])); batch.graph_digest = try g.digest()
        var changed = g; changed.concepts[0].definition = "已修改"
        #expect(throws: Error.self) { try batch.applying(selected: [a.id], to: changed, revision: "r") }
        let result = try batch.applying(selected: [a.id], to: g, revision: "r")
        #expect(result.origins.last?.source == "apple_fm"); #expect(result.origins.last?.reference == "待確認")
    }
    @Test func originalV1SurvivesHistoryPruning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DeploymentStore(root: root)
        let entry = LexiconEntry(type: .english, reading: "oldword", text: "oldword")
        let first = try await store.preview(LexiconDocument(entries: [entry]).encoded())
        let original = try await store.approve(first.token)
        var g = try sample()
        for i in 0..<7 {
            g.concepts[0].definition = "版本 \(i)"
            let preview = try await store.previewCards(g, expectedRevision: store.snapshot().revision)
            _ = try await store.approve(preview.token)
        }
        let restored = try await store.restoreOriginalV1()
        #expect(restored.revision == original.revision); #expect(restored.cards == nil)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(original.revision).path))
    }
    @Test func failedActivationPreservesOldVersion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DeploymentStore(root: root, checkpoint: { if case .activating = $0 { throw LexiconError.invalid("injected") } })
        let p = try await store.previewCards(sample(), expectedRevision: "")
        await #expect(throws: Error.self) { try await store.approve(p.token) }
        #expect(await store.snapshot().entries.isEmpty)
        #expect(try await DeploymentStore(root: root).load().entries.isEmpty)
    }
}

@Suite struct CardFixtureTests {
    @Test func independentSharedFixtureAndSwiftExport() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let folder = root.appendingPathComponent("research/lexicon-learning/shared-fixtures/cards-v2")
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("synthetic.json").path) else {
            Issue.record("Missing independent card fixture"); return
        }
        struct Fixture: Decodable { var dictionary_version: String; var document_type: String; var cards: CardGraph }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: folder.appendingPathComponent("synthetic.json")))
        let value = try fixture.cards.exchange(version: fixture.dictionary_version)
        let decoded = try UnifiedSQLite.decode(Data(contentsOf: folder.appendingPathComponent("independent.sqlite")))
        #expect(decoded.cards == fixture.cards)
        #expect(try UnifiedSQLite.decode(UnifiedSQLite.encode(value)).cards == fixture.cards)
        if let path = ProcessInfo.processInfo.environment["AI_BOPOMOFO_CARDS_FIXTURE_OUTPUT"] { try UnifiedSQLite.encode(value).write(to: URL(fileURLWithPath: path)) }
        let rust = folder.appendingPathComponent("rust.sqlite")
        #expect(try UnifiedSQLite.decode(Data(contentsOf: rust)).cards == fixture.cards)
        let boundary = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: folder.appendingPathComponent("utf16-definition-boundary.json")))
        #expect(try UnifiedSQLite.decode(Data(contentsOf: folder.appendingPathComponent("rust-boundary.sqlite"))).cards == boundary.cards)
    }
}

@Suite struct CardRobustnessTests {
    @Test func mutatedV2TablesVersionsAndValuesAreRejected() throws {
        var g = CardGraph(); let c = LexiconConcept(definition: "測試詞義"); g.concepts.append(c)
        try g.editName(concept: c.id, text: "sample", kind: "en", codes: ["sample"], readings: [])
        let original = try UnifiedSQLite.encode(g.exchange())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); defer { try? FileManager.default.removeItem(at: root) }
        for sql in ["CREATE VIEW hidden AS SELECT * FROM forms;", "PRAGMA user_version=99;", "UPDATE bindings SET name_id='orphan';", "UPDATE forms SET kind='unknown';", "INSERT INTO metadata VALUES ('approved_by','external');", "UPDATE concepts SET definition=char(0);"] {
            let file = root.appendingPathComponent("test.sqlite"); try original.write(to: file)
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3"); process.arguments = [file.path, sql]; process.standardOutput = FileHandle.nullDevice
            try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
            let data = try Data(contentsOf: file); #expect(throws: Error.self) { try UnifiedSQLite.decode(data) }
        }
        #expect(throws: Error.self) { try UnifiedSQLite.decode(original.prefix(500)) }
    }
    @Test func largeSyntheticGraphProjectionAndLookupMeasurements() throws {
        var g = CardGraph()
        for i in 0..<2000 {
            let c = LexiconConcept(definition: "合成測試詞義 \(i)"), f = LexiconForm(text: "synthetic\(i)", kind: "en")
            let n = ConceptForm(concept: c.id, form: f.id)
            g.concepts.append(c); g.forms.append(f); g.names.append(n); g.bindings.append(.init(name: n.id, code: f.text, type: .english))
        }
        let start = Date(); let entries = try g.projectedEntries(); let snapshot = LexiconSnapshot(entries: entries)
        let buildMS = Date().timeIntervalSince(start) * 1000
        var times: [Double] = []
        for i in 0..<1000 { let start = Date(); let found = snapshot.english("synthetic\(i)"); times.append(Date().timeIntervalSince(start)*1000); #expect(found.exact.count == 1) }
        times.sort(); print("CARD_METRICS synthetic=2000 indexBuildMS=\(buildMS) lookupP95MS=\(times[949]); module only, not IMK latency")
    }
}
