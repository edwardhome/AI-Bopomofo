// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import Testing
import LearningCore
import LearningStorage
import LexiconDeployment
import LearningOrganizer

private func term(_ text: String = "SiO₂", code: String = "sio2") -> LexiconEntry {
    LexiconEntry(type: .unicode, reading: code, text: text, annotation: "二氧化矽")
}
private func temporary() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
}
@Suite struct SchemaTests {
    @Test func commitProjectionDoesNotLearnPartialOrChangedText() {
        let spans = [TermSpan(reading: "ㄒㄧˋ-ㄊㄨㄥˇ", text: "系統", location: 0, manual: true),
                     TermSpan(reading: "ㄙㄜˋ-ㄐㄧˋ", text: "設計", location: 2, manual: false)]
        #expect(CommitProjection.terms(committed: "系統", composition: "系統設計", spans: spans).count == 1)
        #expect(CommitProjection.terms(committed: "系", composition: "系統設計", spans: spans).isEmpty)
        #expect(CommitProjection.terms(committed: "", composition: "系統設計", spans: spans).isEmpty)
        #expect(CommitProjection.terms(committed: "變更", composition: "系統設計", spans: spans).isEmpty)
        #expect(CommitProjection.terms(committed: "系統設計", composition: "系統設計", spans: spans).count == 2)
    }
    @Test func publishedExampleAndBundledEngineeringAdapter() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let example = try LexiconDocument.decode(Data(contentsOf: root.appendingPathComponent("examples/lexicon-review-example.json")))
        #expect(example.entries.count == 2)
        struct Catalog: Decodable {
            struct Term: Decodable { let aliases: [String]; let outputs: [String]; let annotation: String }
            let terms: [Term]
        }
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: root.appendingPathComponent("Packages/MixedInputCore/Sources/MixedInputCore/Resources/engineering-terms.json")))
        let converted = catalog.terms.flatMap { term in term.aliases.flatMap { code in term.outputs.map {
            LexiconEntry(type: .unicode, reading: code, text: $0, source: "bundled_engineering", annotation: term.annotation)
        } } }
        #expect(catalog.terms.count == 103)
        let doc = try LexiconDocument.decode(LexiconDocument(entries: converted).encoded())
        #expect(Set(doc.entries.map(\.text)) == Set(catalog.terms.flatMap(\.outputs)))
        #expect(doc.entries.allSatisfy { $0.review.status != .approved })
    }
    @Test func unknownKeysDepthAndIdentityTampering() throws {
        let bytes = try LexiconDocument(entries: [term()]).encoded()
        var object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        object["execute"] = "do not execute"
        #expect(throws: (any Error).self) { try LexiconDocument.decode(JSONSerialization.data(withJSONObject: object)) }
        #expect(throws: (any Error).self) { try JSONPreflight.validate(Data((String(repeating: "[", count: 14) + "0" + String(repeating: "]", count: 14)).utf8)) }
        var e = term(); e.text = "SiO2"
        #expect(throws: (any Error).self) { try e.validated() }
    }
    @Test func suggestionDoesNotOverwriteObservedFacts() {
        let original = term()
        var proposal = original; proposal.review.status = .proposed; proposal.source = "apple_fm"
        proposal.annotation = "模型推測"
        proposal.model_suggestion = ModelSuggestion(origin: original.entry_id, reason: "待確認", model: "synthetic")
        proposal.model_suggestion?.suggested_annotation = "模型推測"
        let merged = LexiconDocument.mergedReviewEntries([original, proposal])
        #expect(merged.count == 1)
        #expect(merged[0].annotation == original.annotation)
        #expect(merged[0].source == "user_observation")
        #expect(merged[0].model_suggestion?.suggested_annotation == "模型推測")
    }
    @Test func stableIdentity() {
        #expect(term().entry_id == term().entry_id)
        #expect(term("SiO2").entry_id != term().entry_id)
        #expect(term(code: "SiO2").entry_id != term().entry_id)
    }
    @Test func roundTripAndUnicode() throws {
        let data = try LexiconDocument(entries: [term()]).encoded()
        #expect(try LexiconDocument.decode(data).entries[0].text == "SiO₂")
        #expect(try LexiconDocument.decode(LexiconDocument(entries: [term()]).exchangeData()).entries[0].text == "SiO₂")
        var invalid = LexiconDocument(entries: [term()]); invalid.schema_version = "2.0.0"
        #expect(throws: (any Error).self) { try invalid.exchangeData() }
    }
    @Test func rejectDuplicateKeys() throws {
        let data = try LexiconDocument(entries: [term()]).encoded()
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"format\" :", with: "\"format\":\"ignored\",\"format\" :")
        #expect(throws: (any Error).self) { try LexiconDocument.decode(Data(text.utf8)) }
    }
    @Test func rejectUnknownVersionAndPrefer() throws {
        var e = term(); e.policy = "prefer"
        #expect(throws: (any Error).self) { try e.validated() }
        var doc = LexiconDocument(entries: [term()]); doc.schema_version = "2.0.0"
        #expect(throws: (any Error).self) { try LexiconDocument.decode(doc.encoded()) }
    }
    @Test func invalidReadingAndControls() {
        #expect(throws: (any Error).self) { try LexiconEntry(type: .zhPhrase, reading: "ㄒㄧˋ-ㄊㄨㄥˇ", text: "系統詞").validated() }
        // 重新建立身分後仍拒絕不對應的讀音與控制字元。
        #expect(throws: (any Error).self) { try LexiconEntry(type: .zhPhrase, reading: "abc", text: "詞").validated() }
        #expect(throws: (any Error).self) { try term("Si\nO2").validated() }
    }
    @Test func validChinese() throws {
        try LexiconEntry(type: .zhPhrase, reading: "ㄒㄧˋ-ㄊㄨㄥˇ", text: "系統").validated()
    }
    @Test func queueDropsAndDrainsInOrder() {
        let queue = ObservationQueue(capacity: 2)
        #expect(queue.offer(Observation(entry: term(), kind: .manualSelected)))
        #expect(queue.offer(Observation(entry: term("SiO2"), kind: .autoCommitted)))
        #expect(!queue.offer(Observation(entry: term(), kind: .autoCommitted)))
        #expect(queue.drain(limit: 1).first?.entry.text == "SiO₂")
        #expect(queue.drain().first?.entry.text == "SiO2")
        #expect(queue.drain().isEmpty)
    }
    @Test func independentSwitches() {
        var state = LearningState(); state.modelAvailable = true; state.observationEnabled = false
        #expect(state.canOrganize(secure: false, idle: true, hasPending: true))
        state.organizerEnabled = false; state.observationEnabled = true
        #expect(state.worker == .collecting)
        #expect(!state.canOrganize(secure: false, idle: true, hasPending: true))
    }
}
@Suite struct StorageTests {
    @Test func failedTransactionRollsBackCountsAndDedupMarker() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("learning.sqlite")
        let event = Observation(entry: term(), kind: .manualSelected)
        let broken = try SQLiteStore(url: url) { throw LexiconError.invalid("synthetic SQLITE_FULL before COMMIT") }
        await #expect(throws: (any Error).self) { try await broken.ingest([event]) }
        #expect(try await broken.entries().isEmpty)
        let healthy = try SQLiteStore(url: url)
        try await healthy.ingest([event])
        #expect(try await healthy.entries()[0].usage == Usage(commits: 1, manual: 1))
    }
    @Test func newerDatabaseIsNotDowngraded() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("learning.sqlite")
        let store = try SQLiteStore(url: url)
        try await store.ingest([Observation(entry: term(), kind: .autoCommitted)])
        let command = Process(); command.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        command.arguments = [url.path, "PRAGMA user_version=2;"]
        try command.run(); command.waitUntilExit(); #expect(command.terminationStatus == 0)
        #expect(throws: (any Error).self) { try SQLiteStore(url: url) }
        #expect(try await store.entries().count == 1)
    }
    @Test func readOnlyFailureKeepsInputQueueIndependent() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("learning.sqlite")
        let writer = try SQLiteStore(url: url)
        try await writer.ingest([Observation(entry: term(), kind: .autoCommitted)])
        let reader = try SQLiteStore(url: url, readOnly: true)
        await #expect(throws: (any Error).self) { try await reader.ingest([Observation(entry: term(), kind: .autoCommitted)]) }
        #expect(try await writer.entries()[0].usage?.commit_count == 1)
        let queue = ObservationQueue(capacity: 1)
        #expect(queue.offer(Observation(entry: term(), kind: .autoCommitted)))
    }
    @Test func boundedRetriesAndClear() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(url: root.appendingPathComponent("learning.sqlite"))
        try await store.ingest([Observation(entry: term(), kind: .autoCommitted)])
        for _ in 0..<3 { try await store.failedBatch([term()]) }
        #expect(try await store.entries(pendingOnly: true).isEmpty)
        try await store.retryPending(); #expect(try await store.entries(pendingOnly: true).count == 1)
        try await store.clear(); #expect(try await store.entries().isEmpty)
    }
    @Test func aggregationDedupAndBackup() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(url: root.appendingPathComponent("learning.sqlite"))
        let event = Observation(entry: term(), kind: .manualSelected)
        try await store.ingest([event,event,Observation(entry: term(), kind: .autoCommitted)])
        let entries = try await store.entries()
        #expect(entries.count == 1); #expect(entries[0].usage == Usage(commits: 2, manual: 1))
        #expect(!entries[0].review.user_confirmed)
        try await store.ingest([Observation(entry: term(), kind: .explicitRemember)])
        #expect(try await store.entries()[0].review.user_confirmed)
        let backup = root.appendingPathComponent("backup.sqlite")
        try await store.backup(to: backup)
        let restored = try SQLiteStore(url: backup)
        #expect(try await restored.entries()[0].usage?.commit_count == 2)
        try await store.exclude(term().entry_id)
        try await store.ingest([Observation(entry: term(), kind: .autoCommitted)])
        #expect(try await store.entries().isEmpty)
        // 明確重新記住可撤回排除，但不補算先前被略過的提交。
        try await store.ingest([Observation(entry: term(), kind: .explicitRemember)])
        #expect(try await store.entries()[0].review.user_confirmed)
        #expect(try await store.entries()[0].usage?.commit_count == 0)
        let remembered = try await store.entries(pendingOnly: true)
        #expect(remembered.count == 1)
        try await store.finishBatch(remembered, suggestions: [])
        #expect(try await store.entries(pendingOnly: true).isEmpty)
    }
    @Test func failedOpenAndCorruption() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("corrupt.sqlite")
        try Data("not a database".utf8).write(to: file)
        #expect(throws: (any Error).self) { try SQLiteStore(url: file) }
        let moved = try SQLiteStore.quarantine(file)
        #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent("corrupt.sqlite").path))
    }
    @Test func cancellationAndProposalValidation() throws {
        var gate = OrganizerGate(); let id = gate.begin(now: Date(), idleSeconds: 31, secure: false, enabled: true, suitable: true, pending: true)!
        gate.cancel(); let accepted = gate.finish(id); #expect(!accepted)
        let restarted = gate.begin(now: Date(), idleSeconds: 31, secure: false, enabled: true, suitable: true, pending: true); #expect(restarted == nil)
        let p = OrganizerProposal(origin: term().entry_id, type: .unicode, reading: "sio2", text: "SiO₂", annotation: "二氧化矽", category: "chemistry", reason: "確認上下標")
        let result = try SuggestionValidator.validate(JSONEncoder().encode([p]), originals: [term()])
        #expect(result[0].review.status == .proposed)
        #expect(throws: (any Error).self) { try SuggestionValidator.validate(Data("{".utf8), originals: [term()]) }
        #expect(throws: (any Error).self) { try SuggestionValidator.validate(JSONEncoder().encode([p]), originals: []) }
    }
}
@Suite struct DeploymentTests {
    @Test(arguments: [DeploymentCheckpoint.staged, .verified, .activating])
    func interruptedDeploymentKeepsOldVersion(_ failure: DeploymentCheckpoint) async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try DeploymentStore(root: root)
        let first = try await original.preview(LexiconDocument(version: "one", entries: [term()]).encoded())
        _ = try await original.approve(first.token)
        let broken = try DeploymentStore(root: root) { step in
            if step == failure { throw LexiconError.invalid("synthetic disk full") }
        }
        _ = try await broken.load()
        let next = try await broken.preview(LexiconDocument(version: "two", entries: [term("SiO2")]).encoded())
        await #expect(throws: (any Error).self) { try await broken.approve(next.token) }
        let restored = try DeploymentStore(root: root)
        #expect(try await restored.load().version == "one")
    }
    @Test func corruptActiveVersionFallsBack() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try DeploymentStore(root: root)
        for (version,text) in [("one","SiO₂"),("two","SiO2")] {
            let p = try await store.preview(LexiconDocument(version: version, entries: [term(text)]).encoded())
            _ = try await store.approve(p.token)
        }
        let pointer = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("active.json"))) as! [String:Any]
        let active = pointer["active"] as! String
        try Data("{".utf8).write(to: root.appendingPathComponent(active).appendingPathComponent("lexicon.json"))
        let restored = try DeploymentStore(root: root)
        #expect(try await restored.load().version == "one")
        #expect(await restored.recoveryNotice != nil)
    }
    @Test func approvalRollbackAndNoDatabase() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try DeploymentStore(root: root)
        var e = term(); e.review.status = .approved
        let first = try await store.preview(LexiconDocument(version: "one", entries: [e]).encoded())
        #expect(await store.snapshot().entries.isEmpty)
        #expect(throws: (any Error).self) { try LexiconDocument.decode(Data("{".utf8)) }
        let one = try await store.approve(first.token); #expect(one.entries.count == 1)
        let second = try await store.preview(LexiconDocument(version: "two", entries: [term("SiO2")]).encoded())
        #expect(second.conflicts == 1)
        let two = try await store.approve(second.token); #expect(two.entries.count == 2)
        #expect(try await store.rollback().version == "one")
        let reopened = try DeploymentStore(root: root)
        #expect(try await reopened.load().entries.count == 1)
    }
    @Test func stalePreviewAndVersionSpoofing() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try DeploymentStore(root: root)
        let bytes = try LexiconDocument(version: "same", entries: [term()]).encoded()
        let first = try await store.preview(bytes), next = try await store.preview(bytes)
        await #expect(throws: (any Error).self) { try await store.approve(first.token) }
        _ = try await store.approve(next.token)
        await #expect(throws: (any Error).self) { try await store.preview(LexiconDocument(version: "same", entries: [term("SiO2")]).encoded()) }
        let repeatPreview = try await store.preview(bytes)
        #expect(try await store.approve(repeatPreview.token).entries.count == 1)
    }
    @Test func indexedCandidateBoundaries() {
        let s = LexiconSnapshot(entries: [term(),term("Si",code:"si")])
        #expect(s.english("si").prefix.isEmpty)
        #expect(s.english("sio").prefix.count == 1)
        #expect(s.english("SIO2").exact.count == 1)
    }
}
