// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import Testing
import LearningCore
import LearningStorage
import LexiconDeployment

@Suite struct UnifiedSQLiteTests {
    private func terms(version: String = "synthetic-one") -> UnifiedLexicon {
        var chinese = LexiconEntry(type: .zhPhrase, reading: "ㄐㄧㄚˇ-ㄨㄢˊ", text: "甲烷", source: "synthetic")
        chinese.usage = Usage(commits: 7, manual: 2)
        var symbol = LexiconEntry(type: .unicode, reading: "ch4", text: "CH₄", source: "synthetic", annotation: "甲烷")
        symbol.category = "chemistry"; symbol.sources = ["synthetic-fixture"]
        return UnifiedLexicon(document: LexiconDocument(version: version, entries: [chinese, symbol]),
            relations: [.init(source: chinese.entry_id, target: symbol.entry_id)])
    }
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    private func mutate(_ bytes: Data, sql: String) throws -> Data {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("lexicon.sqlite"); try bytes.write(to: url)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path, sql]; process.standardOutput = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
        return try Data(contentsOf: url)
    }
    @Test func independentSQLiteFixtureRoundTripsWithoutLosingRelations() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        root.appendPathComponent("research/lexicon-learning/shared-fixtures")
        let expected = try UnifiedLexicon.decode(Data(contentsOf: root.appendingPathComponent("unified-v1.json")))
        let actual = try UnifiedSQLite.decode(Data(contentsOf: root.appendingPathComponent("unified-v1.sqlite")))
        #expect(actual == expected)
        #expect(try UnifiedSQLite.decode(UnifiedSQLite.encode(actual)) == expected)
        let rust = try UnifiedSQLite.decode(Data(contentsOf: root.appendingPathComponent("rust-unified-v1.sqlite")))
        #expect(rust == expected)
        // 僅以公開合成資料產生雙向驗證檔，預設測試不寫入原始碼目錄。
        if let destination = ProcessInfo.processInfo.environment["AI_BOPOMOFO_SQLITE_FIXTURE_OUTPUT"] {
            try UnifiedSQLite.encode(rust).write(to: URL(fileURLWithPath: destination))
        }
    }
    @Test func repeatedSelectionsAndExportedSnapshotsKeepDistinctVersionIdentity() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try DeploymentStore(root: root)
        let first = LexiconEntry(type: .english, reading: "alpha", text: "Alpha")
        let second = LexiconEntry(type: .english, reading: "beta", text: "Beta")
        let original = LexiconDocument(version: "same-source", entries: [first, second])
        let p1 = try await store.preview(original.encoded())
        _ = try await store.approve(store.selectPreview(p1.token, keys: [first.entry_id]).token)
        let firstRevision = await store.snapshot().revision
        let p2 = try await store.preview(original.encoded())
        _ = try await store.approve(store.selectPreview(p2.token, keys: [second.entry_id]).token)
        #expect(await store.snapshot().entries.count == 2)
        #expect(await store.snapshot().revision != firstRevision)
        await #expect(throws: (any Error).self) {
            try await store.preview(UnifiedLexicon(document: original), replacing: true, expectedRevision: firstRevision)
        }
        let full = try await store.exportSQLite()
        let selected = try await store.exportSQLite(keys: [first.entry_id])
        #expect(try UnifiedSQLite.decode(full).document.dictionary_version != UnifiedSQLite.decode(selected).document.dictionary_version)
        _ = try await store.approve(store.preview(full, replacing: true).token)
        _ = try await store.approve(store.preview(full, replacing: true).token)
        #expect(await store.snapshot().entries.count == 2)
    }
    @Test func sqlitePreservesMetadataUnicodeAndLinkedSelection() throws {
        let original = terms(), bytes = try UnifiedSQLite.encode(original)
        #expect(UnifiedSQLite.isSQLite(bytes))
        #expect(try UnifiedSQLite.decode(bytes) == original)
        let selected = original.selecting([original.document.entries[1].entry_id])
        #expect(selected.document.entries.count == 2)
        #expect(selected.relations.count == 1)
        let snapshot = LexiconSnapshot(entries: original.document.entries, relations: original.relations)
        #expect(snapshot.chinese("ㄐㄧㄚˇ-ㄨㄢˊ").map(\.text) == ["甲烷"])
        #expect(snapshot.english("CH4").exact.map(\.text) == ["CH₄"])
    }
    @Test func entireBundledEngineeringCatalogFitsSharedSchema() throws {
        struct Catalog: Decodable { var terms: [Term] }
        struct Term: Decodable {
            var aliases: [String]; var outputs: [String]; var annotation: String
            var category: String; var sources: [String]
        }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent("Packages/MixedInputCore/Sources/MixedInputCore/Resources/engineering-terms.json")
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        var values: [LexiconEntry] = [], seen = Set<String>()
        for term in catalog.terms {
            for code in term.aliases { for output in term.outputs {
                var entry = LexiconEntry(type: .unicode, reading: code, text: output,
                    source: "bundled-engineering", annotation: term.annotation)
                entry.category = term.category; entry.sources = term.sources
                try entry.validated()
                if seen.insert(entry.entry_id).inserted { values.append(entry) }
            } }
        }
        #expect(catalog.terms.count == 103)
        #expect(values.count == 186)
        let value = UnifiedLexicon(document: LexiconDocument(entries: values))
        #expect(try UnifiedSQLite.decode(UnifiedSQLite.encode(value)) == value)
    }
    @Test(arguments: [
        "PRAGMA user_version=2;", "PRAGMA application_id=0;",
        "CREATE VIEW injected AS SELECT * FROM entries;",
        "CREATE TRIGGER injected AFTER INSERT ON entries BEGIN DELETE FROM entries; END;",
        "CREATE TABLE extra (text TEXT);",
        "UPDATE entries SET text='different' WHERE position=0;",
        "UPDATE entries SET position=20 WHERE position=0;",
        "UPDATE metadata SET value='2.0.0' WHERE key='schema_version';",
        "UPDATE relations SET source_id='missing';",
        "UPDATE relations SET kind='automatic-replacement';",
        "UPDATE entries SET payload='{}' WHERE position=0;"
    ])
    func malformedOrUnsupportedFilesAreRejected(_ sql: String) throws {
        let bad = try mutate(UnifiedSQLite.encode(terms()), sql: sql)
        #expect(throws: (any Error).self) { try UnifiedSQLite.decode(bad) }
    }
    @Test func truncatedAndOversizedInputRejected() throws {
        let bytes = try UnifiedSQLite.encode(terms())
        #expect(throws: (any Error).self) { try UnifiedSQLite.decode(Data(bytes.prefix(100))) }
        #expect(throws: (any Error).self) { try UnifiedSQLite.decode(Data(count: UnifiedSQLite.maximumBytes + 1)) }
    }
    @Test func duplicateAndOrphanRelationsRejected() throws {
        var value = terms(); value.relations.append(value.relations[0])
        #expect(throws: (any Error).self) { try UnifiedSQLite.encode(value) }
        value = terms(); value.document.entries.removeLast()
        #expect(throws: (any Error).self) { try UnifiedSQLite.encode(value) }
    }
    @Test func approvalSelectionRollbackAndSQLiteFallback() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try DeploymentStore(root: root)
        let original = terms()
        let preview = try await store.preview(UnifiedSQLite.encode(original))
        #expect(await store.snapshot().entries.isEmpty)
        let chosen = try await store.selectPreview(preview.token, keys: [original.document.entries[1].entry_id])
        #expect(chosen.document.entries.count == 2)
        let first = try await store.approve(chosen.token)
        #expect(first.relations.count == 1)
        #expect(first.entries.allSatisfy { $0.review.status == .approved && $0.usage == nil })
        await #expect(throws: (any Error).self) { try await store.exportCurrent() }
        #expect(try UnifiedSQLite.decode(await store.exportSQLite()).relations.count == 1)
        let deletion = try await store.deletionPreview(keys: [original.document.entries[1].entry_id])
        #expect(try await store.approve(deletion.token).relations.isEmpty)
        #expect(try await store.rollback().relations.count == 1)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("active.json"))) as! [String: Any]
        let active = manifest["active"] as! String
        try Data("broken".utf8).write(to: root.appendingPathComponent(active).appendingPathComponent("lexicon.sqlite"))
        let reopened = try DeploymentStore(root: root)
        #expect(try await reopened.load().relations.count == 1)
        #expect(await reopened.recoveryNotice != nil)
        #expect(first.chinese("ㄐㄧㄚˇ-ㄨㄢˊ").count == 1)
    }
    @Test func fullRestoreDoesNotTakeMergeIdempotenceShortcut() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try DeploymentStore(root: root)
        let old = LexiconDocument(entries: [LexiconEntry(type: .english, reading: "old", text: "old")])
        _ = try await store.approve(store.preview(old.encoded()).token)
        let bytes = try UnifiedSQLite.encode(terms())
        _ = try await store.approve(store.preview(bytes).token)
        #expect(await store.snapshot().entries.count == 3)
        _ = try await store.approve(store.preview(bytes, replacing: true).token)
        #expect(await store.snapshot().entries.count == 2)
    }
    @Test func oldJSONDeploymentLoadsAndCanMigrateWithoutVersionSpoofing() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let incoming = terms(version: "legacy-json").document
        var approved = incoming
        approved.document_type = "approved"
        for i in approved.entries.indices { approved.entries[i].review.status = .approved; approved.entries[i].usage = nil }
        let bytes = try approved.encoded(), checksum = LexiconEntry.digest(bytes)
        let folder = root.appendingPathComponent(checksum)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try bytes.write(to: folder.appendingPathComponent("lexicon.json"))
        let receipt: [String: Any] = ["approval": UUID().uuidString, "approvedAt": 0,
            "sourceChecksum": LexiconEntry.digest(try incoming.encoded()), "checksum": checksum, "version": "legacy-json"]
        try JSONSerialization.data(withJSONObject: receipt).write(to: folder.appendingPathComponent("receipt.json"))
        try JSONSerialization.data(withJSONObject: ["active": checksum, "history": []]).write(to: root.appendingPathComponent("active.json"))
        let store = try DeploymentStore(root: root)
        #expect(try await store.load().entries.count == 2)
        let preview = try await store.preview(incoming.encoded())
        #expect(try await store.approve(preview.token).entries.count == 2)
        let migrated = try await store.exportSQLite()
        #expect(try UnifiedSQLite.decode(migrated).document.entries.count == 2)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("lexicon.json").path))
    }
    @Test func legacyParserPreservesExclusionsAndReportsBadReadings() throws {
        let source = "# synthetic\n甲烷 ㄐㄧㄚˇ-ㄨㄢˊ\n甲烷 ㄐㄧㄚˇ-ㄨㄢˊ\nSwift _english_swift\n錯誤 guessed\n只有文字\n"
        let value = try LegacyTermImport(phrases: source, excluded: "甲烷 ㄐㄧㄚˇ-ㄨㄢˊ\n")
        #expect(value.entries.map(\.text) == ["Swift"])
        #expect(value.excludedCount == 2)
        #expect(value.rejectedLines == [5, 6])
        #expect(try LegacyTermImport(phrases: source).entries.count == 2)
    }
}
