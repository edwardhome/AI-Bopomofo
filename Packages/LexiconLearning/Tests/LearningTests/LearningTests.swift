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
    @Test func stableIdentity() {
        #expect(term().entry_id == term().entry_id)
        #expect(term("SiO2").entry_id != term().entry_id)
        #expect(term(code: "SiO2").entry_id != term().entry_id)
    }
    @Test func roundTripAndUnicode() throws {
        let data = try LexiconDocument(entries: [term()]).encoded()
        #expect(try LexiconDocument.decode(data).entries[0].text == "SiO₂")
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
