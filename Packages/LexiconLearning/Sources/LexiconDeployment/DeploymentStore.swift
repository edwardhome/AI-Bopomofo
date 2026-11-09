// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import LearningCore
import LearningStorage

public struct LexiconSnapshot: Sendable {
    public let version: String
    public let revision: String
    public let entries: [LexiconEntry]
    public let relations: [LexiconRelation]
    private let exact: [String: [LexiconEntry]]
    private let prefixes: [String: [LexiconEntry]]
    public init(version: String = "", entries: [LexiconEntry] = [], relations: [LexiconRelation] = [], revision: String = "") {
        self.version = version; self.revision = revision; self.entries = entries; self.relations = relations
        var exact: [String: [LexiconEntry]] = [:], prefixes: [String: [LexiconEntry]] = [:]
        for e in entries {
            let key = e.term_type == .zhPhrase ? "zh:" + e.reading : "en:" + e.reading.lowercased()
            exact[key, default: []].append(e)
            if e.term_type != .zhPhrase && e.reading.count >= 3 {
                for length in 3...e.reading.count { prefixes[String(e.reading.lowercased().prefix(length)), default: []].append(e) }
            }
        }
        self.exact = exact; self.prefixes = prefixes
    }
    public func chinese(_ reading: String) -> [LexiconEntry] { exact["zh:" + reading] ?? [] }
    public func english(_ code: String) -> (exact: [LexiconEntry], prefix: [LexiconEntry]) {
        let matches = exact["en:" + code.lowercased()] ?? []
        let keys = Set(matches.map(\.entry_id))
        let prefix = code.count >= 3 ? (prefixes[code.lowercased()] ?? []).filter { !keys.contains($0.entry_id) } : []
        func ordered(_ es: [LexiconEntry]) -> [LexiconEntry] {
            es.enumerated().sorted { a, b in
                let x = a.element.reading.hasPrefix(code), y = b.element.reading.hasPrefix(code)
                return x == y ? a.offset < b.offset : x
            }.map(\.element)
        }
        return (ordered(matches), ordered(prefix))
    }
}
public struct ImportPreview: Sendable {
    public let token: UUID
    public let document: LexiconDocument
    public let relations: [LexiconRelation]
    public let added: Int, changed: Int, existing: Int, duplicates: Int, conflicts: Int, proposals: Int
    public let digest: String
}
private struct Receipt: Codable {
    var approval: UUID
    var approvedAt: Date
    var sourceChecksum: String
    var checksum: String
    var version: String
    var sqliteChecksum: String?
}
private struct Manifest: Codable { var active: String?; var history: [String] = [] }
public enum DeploymentCheckpoint: Sendable { case staged, verified, activating }

/// 核准版本以獨立 SQLite 保存中文與工程詞；完整復原快照保留資料庫失效時的輸入能力。
public actor DeploymentStore {
    public let root: URL
    private var manifest = Manifest()
    private var current = LexiconSnapshot()
    private var previews: [UUID: (ImportPreview, String, Bool)] = [:]
    private let checkpoint: @Sendable (DeploymentCheckpoint) throws -> Void
    public private(set) var recoveryNotice: String?
    public init(root: URL, checkpoint: @escaping @Sendable (DeploymentCheckpoint) throws -> Void = { _ in }) throws {
        self.root = root
        self.checkpoint = checkpoint
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public func load() throws -> LexiconSnapshot {
        let pointer = root.appendingPathComponent("active.json")
        if FileManager.default.fileExists(atPath: pointer.path) {
            do { manifest = try JSONDecoder().decode(Manifest.self, from: boundedRead(pointer, max: 4096)) }
            catch {
                manifest = try JSONDecoder().decode(Manifest.self, from: boundedRead(root.appendingPathComponent("previous-active.json"), max: 4096))
                recoveryNotice = "目前版本指標損毀，已回復上一次版本指標"
            }
        }
        for id in ([manifest.active].compactMap { $0 } + manifest.history).prefix(6) {
            if let snapshot = try? readVersion(id) {
                if manifest.active != id {
                    manifest.active = id; manifest.history.removeAll { $0 == id }; try persistManifest()
                    recoveryNotice = "目前詞庫損毀，已回復有效歷史版本"
                }
                current = snapshot; return snapshot
            }
        }
        if manifest.active != nil { throw LexiconError.invalid("擴充詞庫與歷史版本驗證失敗；本次停用擴充") }
        return current
    }
    public func snapshot() -> LexiconSnapshot { current }
    public func preview(_ bytes: Data, replacing: Bool = false) throws -> ImportPreview {
        let value = UnifiedSQLite.isSQLite(bytes) ? try UnifiedSQLite.decode(bytes)
            : UnifiedLexicon(document: try LexiconDocument.decode(bytes))
        return try preview(value, replacing: replacing)
    }
    public func preview(_ value: UnifiedLexicon, replacing: Bool = false, expectedRevision: String? = nil) throws -> ImportPreview {
        if let expectedRevision, expectedRevision != (manifest.active ?? "") {
            throw LexiconError.invalid("詞庫已變更，請重新開啟編輯")
        }
        let doc = value.document
        var unique: [String: LexiconEntry] = [:], entries: [LexiconEntry] = []
        var duplicates = 0
        for entry in doc.entries {
            if let old = unique[entry.entry_id] {
                guard old == entry else { throw LexiconError.invalid("同一詞彙識別碼包含矛盾資料") }
                duplicates += 1
            } else { unique[entry.entry_id] = entry; entries.append(entry) }
        }
        var normalized = doc; normalized.entries = entries
        let old = Dictionary(uniqueKeysWithValues: current.entries.map { ($0.entry_id, $0) })
        var added = 0, changed = 0, existing = 0
        for entry in entries {
            if let previous = old[entry.entry_id] {
                if previous.annotation == entry.annotation && previous.category == entry.category { existing += 1 } else { changed += 1 }
            } else { added += 1 }
        }
        var readingValues: [String: Set<String>] = [:]
        for e in current.entries + entries { readingValues[e.term_type.rawValue + ":" + e.reading, default: []].insert(e.text) }
        let normalizedValue = UnifiedLexicon(document: normalized, relations: value.relations)
        let digest = LexiconEntry.digest(try normalizedValue.encoded())
        // 版本名稱不能重用來表示另一份資料，亦不可用來源檔內的 approved 繞過預覽。
        for id in ([manifest.active].compactMap { $0 } + manifest.history) {
            if let receipt = try? readReceipt(id), receipt.version == doc.dictionary_version,
               receipt.sourceChecksum != digest {
                // 舊版 JSON receipt 的來源摘要尚未包入關聯容器；原檔可再次預覽並遷移。
                let legacyDigest = LexiconEntry.digest(try normalized.encoded())
                guard receipt.sqliteChecksum == nil, value.relations.isEmpty,
                      receipt.sourceChecksum == legacyDigest else { throw LexiconError.invalid("同一詞庫版本已存在不同內容") }
            }
        }
        let preview = ImportPreview(token: UUID(), document: normalized, relations: value.relations, added: added, changed: changed,
            existing: existing, duplicates: duplicates, conflicts: readingValues.values.filter { $0.count > 1 }.count,
            proposals: entries.filter { $0.review.status == .proposed || $0.model_suggestion != nil }.count, digest: digest)
        previews.removeAll(); previews[preview.token] = (preview, manifest.active ?? "", replacing)
        return preview
    }
    /// 只能使用本程序產生、尚未過期的預覽 token；UI 確認按鈕是唯一正式呼叫入口。
    public func approve(_ token: UUID) throws -> LexiconSnapshot {
        guard let (preview, base, replacing) = previews.removeValue(forKey: token), base == (manifest.active ?? "") else {
            throw LexiconError.invalid("預覽已失效，請重新核對")
        }
        var values = replacing ? [] : current.entries
        var positions = Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0.element.entry_id, $0.offset) })
        for var entry in preview.document.entries {
            entry.review.status = .approved; entry.usage = nil
            if let index = positions[entry.entry_id] { values[index] = entry }
            else { positions[entry.entry_id] = values.count; values.append(entry) }
        }
        guard values.count <= 20_000 else { throw LexiconError.invalid("合併後超過 20,000 詞") }
        let doc = LexiconDocument(type: "approved", version: preview.document.dictionary_version, entries: values)
        var relations = replacing ? [] : current.relations
        var seenRelations = Set(relations)
        for relation in preview.relations where seenRelations.insert(relation).inserted { relations.append(relation) }
        let ids = Set(values.map(\.entry_id))
        relations.removeAll { !ids.contains($0.source_id) || !ids.contains($0.target_id) }
        let value = UnifiedLexicon(document: doc, relations: relations)
        let bytes = try value.encoded()
        let sqlite = try UnifiedSQLite.encode(value)
        let checksum = LexiconEntry.digest(bytes)
        if manifest.active == checksum { return current }
        let stage = root.appendingPathComponent("stage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: stage) }
        try write(bytes, to: stage.appendingPathComponent("unified.json"))
        try write(sqlite, to: stage.appendingPathComponent("lexicon.sqlite"))
        let receipt = Receipt(approval: UUID(), approvedAt: Date(), sourceChecksum: preview.digest, checksum: checksum, version: doc.dictionary_version, sqliteChecksum: LexiconEntry.digest(sqlite))
        try write(try JSONEncoder().encode(receipt), to: stage.appendingPathComponent("receipt.json"))
        try checkpoint(.staged)
        let folder = root.appendingPathComponent(checksum)
        if !FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.moveItem(at: stage, to: folder) }
        let snapshot = try readVersion(checksum)
        try checkpoint(.verified)
        let old = manifest
        manifest.history = Array(([manifest.active].compactMap { $0 } + manifest.history).filter { $0 != checksum }.prefix(5))
        manifest.active = checksum
        do { try checkpoint(.activating); try persistManifest() } catch { manifest = old; throw error }
        current = snapshot; pruneVersions(); return snapshot
    }
    public func cancel(_ token: UUID) { previews.removeValue(forKey: token) }
    public func rollback() throws -> LexiconSnapshot {
        guard let previous = manifest.history.first else { throw LexiconError.invalid("沒有可回復的上一版本") }
        let snapshot = try readVersion(previous), old = manifest
        manifest.history = Array(([manifest.active].compactMap { $0 } + manifest.history.dropFirst()).prefix(5))
        manifest.active = previous
        do { try persistManifest() } catch { manifest = old; throw error }
        previews.removeAll(); current = snapshot; return snapshot
    }
    public func unifiedCurrent() -> UnifiedLexicon {
        UnifiedLexicon(document: LexiconDocument(type: "approved", version: current.version, entries: current.entries), relations: current.relations)
    }
    public func exportSQLite(keys: Set<String>? = nil) throws -> Data {
        let value = unifiedCurrent()
        var selected = keys.map { value.selecting($0) } ?? value
        // 核准／合併／選取後的快照不是原始匯入檔，使用內容衍生的交換版本。
        selected.document.dictionary_version = "snapshot-" + LexiconEntry.digest(try selected.encoded())
        return try UnifiedSQLite.encode(selected)
    }
    public func exportCurrent() throws -> Data {
        guard current.relations.isEmpty else { throw LexiconError.invalid("JSON 1.0 無法保留中文別名關聯，請匯出 SQLite") }
        var value = unifiedCurrent()
        value.document.dictionary_version = "snapshot-" + LexiconEntry.digest(try value.encoded())
        return try value.document.encoded()
    }
    public func selectPreview(_ token: UUID, keys: Set<String>) throws -> ImportPreview {
        guard let (p, base, replacing) = previews[token], base == (manifest.active ?? "") else { throw LexiconError.invalid("預覽已失效") }
        let selection = UnifiedLexicon(document: p.document, relations: p.relations).selecting(keys)
        try selection.validated()
        // 核准選取範圍不改變來源檔的身分，之後仍可匯入同檔其他詞條。
        let selected = ImportPreview(token: UUID(), document: selection.document, relations: selection.relations,
            added: p.added, changed: p.changed, existing: p.existing, duplicates: p.duplicates,
            conflicts: p.conflicts, proposals: p.proposals, digest: p.digest)
        previews.removeAll(); previews[selected.token] = (selected, base, replacing)
        return selected
    }
    public func deletionPreview(keys: Set<String>) throws -> ImportPreview {
        let entries = current.entries.filter { !keys.contains($0.entry_id) }
        let ids = Set(entries.map(\.entry_id))
        return try preview(UnifiedLexicon(document: LexiconDocument(entries: entries),
            relations: current.relations.filter { ids.contains($0.source_id) && ids.contains($0.target_id) }), replacing: true)
    }
    private func readReceipt(_ id: String) throws -> Receipt {
        guard id.count == 64 && id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw LexiconError.invalid("不合法版本路徑") }
        return try JSONDecoder().decode(Receipt.self, from: boundedRead(root.appendingPathComponent(id).appendingPathComponent("receipt.json"), max: 4096))
    }
    private func readVersion(_ id: String) throws -> LexiconSnapshot {
        let receipt = try readReceipt(id)
        if let sqlChecksum = receipt.sqliteChecksum {
            let folder = root.appendingPathComponent(id)
            var value: UnifiedLexicon
            do {
                let bytes = try boundedRead(folder.appendingPathComponent("lexicon.sqlite"), max: UnifiedSQLite.maximumBytes)
                guard LexiconEntry.digest(bytes) == sqlChecksum else { throw LexiconError.invalid("SQLite 校驗失敗") }
                value = try UnifiedSQLite.decode(bytes)
                guard LexiconEntry.digest(try value.encoded()) == id else { throw LexiconError.invalid("SQLite 內容校驗失敗") }
            } catch {
                let bytes = try boundedRead(folder.appendingPathComponent("unified.json"), max: UnifiedSQLite.maximumBytes)
                guard LexiconEntry.digest(bytes) == id else { throw LexiconError.invalid("復原快照校驗失敗") }
                value = try UnifiedLexicon.decode(bytes)
                recoveryNotice = "SQLite 詞庫不可用，已載入核准復原快照"
            }
            guard receipt.checksum == id, value.document.document_type == "approved",
                  value.document.dictionary_version == receipt.version,
                  value.document.entries.allSatisfy({ $0.review.status == .approved }) else { throw LexiconError.invalid("缺少有效核准版本") }
            return LexiconSnapshot(version: receipt.version, entries: value.document.entries, relations: value.relations, revision: id)
        }
        let bytes = try boundedRead(root.appendingPathComponent(id).appendingPathComponent("lexicon.json"), max: 8*1024*1024)
        guard receipt.checksum == id && LexiconEntry.digest(bytes) == id else { throw LexiconError.invalid("詞庫校驗失敗") }
        let doc = try LexiconDocument.decode(bytes)
        guard doc.document_type == "approved", doc.dictionary_version == receipt.version,
              doc.entries.allSatisfy({ $0.review.status == .approved }), Set(doc.entries.map(\.entry_id)).count == doc.entries.count else { throw LexiconError.invalid("缺少有效核准版本") }
        return LexiconSnapshot(version: doc.dictionary_version, entries: doc.entries, revision: id)
    }
    public func auditDescription() throws -> String {
        guard let id = manifest.active else { return "" }
        let receipt = try readReceipt(id)
        return "\(receipt.version)\n\(ISO8601DateFormatter().string(from: receipt.approvedAt))\nSHA-256: \(receipt.checksum)\nApproval: \(receipt.approval.uuidString)"
    }
    public func activeAudit() throws -> (id: String, version: String, checksum: String, at: Date)? {
        guard let id = manifest.active else { return nil }
        let receipt = try readReceipt(id)
        return (receipt.approval.uuidString, receipt.version, receipt.checksum, receipt.approvedAt)
    }
    private func persistManifest() throws {
        let pointer = root.appendingPathComponent("active.json")
        if let previous = try? boundedRead(pointer, max: 4096), (try? JSONDecoder().decode(Manifest.self, from: previous)) != nil {
            try write(previous, to: root.appendingPathComponent("previous-active.json"))
        }
        try write(try JSONEncoder().encode(manifest), to: pointer)
    }
    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func pruneVersions() {
        let keep = Set([manifest.active].compactMap { $0 } + manifest.history)
        for folder in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            let id = folder.lastPathComponent
            if id.count == 64 && !keep.contains(id) && (try? readReceipt(id)) != nil { try? FileManager.default.removeItem(at: folder) }
        }
    }
    private func boundedRead(_ url: URL, max: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: max + 1) ?? Data()
        guard data.count <= max else { throw LexiconError.invalid("詞庫檔案超過限制") }; return data
    }
}
