// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Cocoa
import Carbon
import LearningCore
import LearningStorage
import LearningOrganizer
import LexiconDeployment
import MixedInputCore
import CandidateRanking

@MainActor
final class LearningRuntime: NSObject {
    static let shared = LearningRuntime()
    let queue = ObservationQueue()
    private(set) var snapshot = LexiconSnapshot()
    private(set) var engineeringTerms: EngineeringLexicon?
    private(set) var chineseIndex = ApprovedLearningIndex()
    private(set) var store: SQLiteStore?
    private(set) var deployment: DeploymentStore?
    private(set) var status = "正在準備本機學習資料"
    private(set) var root: URL
    private var lastActivity = Date()
    private var organizerGate = OrganizerGate()
    private var organizerTask: Task<Void, Never>?
    private var maintenance: Task<Void, Never>?
    private var exclusions = Set<String>()
    private var secure = false
    private var storageFailed = false
    private var generation: UInt64 = 0
    private var windows: [NSWindowController] = []

    private override init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AI-Bopomofo/Learning", isDirectory: true)
        super.init()
        let location = root
        maintenance = Task { [weak self] in
            let stores = await Task.detached(priority: .utility) { () -> (SQLiteStore?, DeploymentStore?, String?) in
                var learning: SQLiteStore?, deployment: DeploymentStore?, errorText: String?
                do { learning = try SQLiteStore(url: location.appendingPathComponent("learning.sqlite")) }
                catch {
                    errorText = error.localizedDescription
                    if errorText?.contains("SQLite 錯誤 11") == true || errorText?.contains("SQLite 錯誤 26") == true || errorText?.contains("完整性") == true {
                        _ = try? SQLiteStore.quarantine(location.appendingPathComponent("learning.sqlite"))
                    }
                }
                do { deployment = try DeploymentStore(root: location.appendingPathComponent("lexicons")) }
                catch { errorText = error.localizedDescription }
                return (learning, deployment, errorText)
            }.value
            guard let self else { return }
            self.store = stores.0; self.deployment = stores.1
            self.status = stores.2 ?? "本機統計就緒；模型只在閒置時整理"
            if let deployment = self.deployment {
                do { await self.publish(try await deployment.load(), recordAudit: false)
                    if let recovery = await deployment.recoveryNotice { self.status = recovery } }
                catch { self.status = error.localizedDescription }
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { break }
                await self.tick()
            }
        }
    }
    func noteActivity(secure: Bool) {
        lastActivity = Date(); self.secure = secure
        if organizerTask != nil { cancelOrganization() }
        if secure { let queue = queue; Task.detached { queue.clear() } }
    }
    @discardableResult func offer(_ entry: LexiconEntry, kind: ObservationKind) -> Bool {
        if kind == .explicitRemember { exclusions.remove(entry.entry_id) }
        guard !storageFailed, !secure, !IsSecureEventInputEnabled(),
              Preferences.lexiconObservationEnabled || kind == .explicitRemember,
              !exclusions.contains(entry.entry_id) else { return false }
        return queue.offer(Observation(entry: entry, kind: kind))
    }
    private func tick() async {
        secure = IsSecureEventInputEnabled()
        guard !secure else { cancelOrganization(); let queue = queue; await Task.detached { queue.clear() }.value; return }
        let queue = queue
        let batch = await Task.detached(priority: .utility) { queue.drain() }.value
        if let store, !storageFailed, !batch.isEmpty {
            do { try await store.ingest(batch); try await store.periodicBackup() }
            catch { storageFailed = true; status = error.localizedDescription }
        }
        guard let store, !storageFailed, organizerTask == nil, Preferences.lexiconOrganizerEnabled,
              Date().timeIntervalSince(lastActivity) >= 30,
              ProcessInfo.processInfo.thermalState == .nominal, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        do {
            let originals = try await store.entries(pendingOnly: true, limit: 16)
            guard let id = organizerGate.begin(now: Date(), idleSeconds: Date().timeIntervalSince(lastActivity),
                secure: secure, enabled: Preferences.lexiconOrganizerEnabled, suitable: true, pending: !originals.isEmpty) else { return }
            status = "FM 背景整理中"
            organizerTask = Task { [weak self] in
                do {
                    let payload = try JSONEncoder().encode(originals)
                    let response = try await ModelServiceClient.shared.organize(payload)
                    let entries = try await Task.detached(priority: .utility) {
                        try SuggestionValidator.validate(response, originals: originals)
                    }.value
                    guard let self else { return }
                    let accepted = self.organizerGate.finish(id)
                    if accepted && !IsSecureEventInputEnabled() && Preferences.lexiconOrganizerEnabled {
                        try await store.finishBatch(originals, suggestions: entries)
                        self.status = "整理完成；建議尚未核准部署"
                    }
                } catch {
                    guard let self else { return }
                    let accepted = self.organizerGate.finish(id)
                    // 使用者取消會使世代失效；仍有效的逾時也算失敗，避免無限重試。
                    if accepted {
                        try? await store.failedBatch(originals)
                        self.status = "FM 暫不可用或整理失敗；統計與正常輸入保持運作"
                    }
                }
                self?.organizerTask = nil
            }
        } catch { storageFailed = true; status = error.localizedDescription }
    }
    func cancelOrganization() {
        if organizerTask != nil { status = "背景整理已取消；正常輸入與統計繼續" }
        organizerGate.cancel(); organizerTask?.cancel()
        ModelServiceClient.shared.cancelBackground()
    }
    func publish(_ value: LexiconSnapshot, recordAudit: Bool = true) async {
        generation &+= 1; let revision = generation
        let built = await Task.detached(priority: .utility) { () -> (ApprovedLearningIndex, EngineeringLexicon) in
            var chinese: [String: [String]] = [:], terms: [[String: Any]] = []
            for e in value.entries {
                if e.term_type == .zhPhrase { chinese[e.reading, default: []].append(e.text); continue }
                terms.append(["id": e.entry_id, "category": e.category ?? "approved", "aliases": [e.reading],
                    "outputs": [e.text], "annotation": String((e.annotation ?? e.text).prefix(80)), "sources": ["local-approval:" + e.entry_id]])
            }
            let bytes = (try? JSONSerialization.data(withJSONObject: ["version": 1, "terms": terms])) ?? Data()
            return (ApprovedLearningIndex(chinese), EngineeringLexicon(data: bytes, maximumTerms: 20_000))
        }.value
        guard generation == revision else { return }
        // 只有新組字取得此快照；不在這裡提交文字或重建在途候選。
        snapshot = value; chineseIndex = built.0; engineeringTerms = built.1
        if recordAudit, let deployment, let store {
            do {
                if let audit = try await deployment.activeAudit() {
                    try await store.recordApproval(id: audit.id, version: audit.version, checksum: audit.checksum, at: audit.at, entries: value.entries)
                }
            } catch { status = "核准版本已保存，但學習資料庫的查閱鏡本更新失敗" }
        }
    }
    func exportObservations(excluding: Set<String>) async throws -> Data {
        guard let store else { throw LexiconError.invalid("學習資料庫不可用") }
        let observed = try await store.entries(), proposed = try await store.suggestions()
        let entries = (observed + proposed).filter { !excluding.contains($0.entry_id) }
        return try await Task.detached { try LexiconDocument(entries: LexiconDocument.mergedReviewEntries(entries)).exchangeData() }.value
    }
    func clearObservations() async throws {
        guard let store else { throw LexiconError.invalid("學習資料庫不可用") }
        cancelOrganization(); let queue = queue
        await Task.detached { queue.clear() }.value
        try await store.clear(); status = "待整理資料已清除；正式詞庫保留"
    }
    func exclude(_ ids: Set<String>) async throws {
        guard let store else { throw LexiconError.invalid("學習資料庫不可用") }
        exclusions.formUnion(ids)
        for id in ids { try await store.exclude(id) }
    }
    func retain(_ controller: NSWindowController) {
        windows.removeAll { $0.window?.isVisible != true }; windows.append(controller)
        controller.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
}
