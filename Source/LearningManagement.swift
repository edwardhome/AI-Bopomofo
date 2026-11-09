// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Cocoa
import Carbon
import UniformTypeIdentifiers
import LearningCore
import LearningStorage
import LexiconDeployment
import MixedInputCore

@MainActor extension McBopomofoInputMethodController {
    func addLearningMenu(to menu: NSMenu) {
        let unified = menu.addItem(withTitle: NSLocalizedString("User and Engineering Lexicon…", comment: ""),
            action: #selector(showLearningApproved), keyEquivalent: "")
        unified.target = self
        let item = menu.addItem(withTitle: NSLocalizedString("AI Lexicon Management", comment: ""), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        func add(_ title: String, _ action: Selector, checked: Bool? = nil) {
            let entry = submenu.addItem(withTitle: NSLocalizedString(title, comment: ""), action: action, keyEquivalent: "")
            entry.target = self
            if let checked { entry.state = checked ? .on : .off }
            entry.isEnabled = !IsSecureEventInputEnabled()
        }
        add("Observe Committed Terms", #selector(toggleLearningObservation), checked: Preferences.lexiconObservationEnabled)
        add("FM Background Organization", #selector(toggleLearningOrganizer), checked: Preferences.lexiconOrganizerEnabled)
        add("Approved Extension Lexicon", #selector(toggleLearningExtension), checked: Preferences.approvedLexiconEnabled)
        submenu.addItem(.separator())
        add("Remember Current Term…", #selector(rememberLearningTerm))
        add("Export Review Data…", #selector(showLearningReview))
        add("Import Lexicon JSON…", #selector(importLearningJSON))
        add("Manage Approved Lexicon…", #selector(showLearningApproved))
        add("Learning Status…", #selector(showLearningStatus))
        add("Cancel Background Organization", #selector(cancelLearningOrganizer))
        add("Disable AI Lexicon Features", #selector(disableLearning))
        item.submenu = submenu
    }
    @objc func toggleLearningObservation() {
        Preferences.lexiconObservationEnabled.toggle()
        if !Preferences.lexiconObservationEnabled { let queue = LearningRuntime.shared.queue; Task.detached { queue.clear() } }
    }
    @objc func toggleLearningOrganizer() {
        Preferences.lexiconOrganizerEnabled.toggle()
        if !Preferences.lexiconOrganizerEnabled { LearningRuntime.shared.cancelOrganization() }
        else if let store = LearningRuntime.shared.store { Task { try? await store.retryPending() } }
    }
    @objc func toggleLearningExtension() { Preferences.approvedLexiconEnabled.toggle() }
    @objc func cancelLearningOrganizer() { LearningRuntime.shared.cancelOrganization() }
    @objc func disableLearning() {
        Preferences.lexiconObservationEnabled = false; Preferences.lexiconOrganizerEnabled = false
        LearningRuntime.shared.cancelOrganization()
        let queue = LearningRuntime.shared.queue; Task.detached { queue.clear() }
    }
    @objc func showLearningReview() { presentLearningPanel(approved: false) }
    @objc func showLearningApproved() { presentLearningPanel(approved: true) }
    @objc func showLearningStatus() { presentLearningPanel(approved: false) }
    private func presentLearningPanel(approved: Bool) {
        guard !IsSecureEventInputEnabled() else { return }
        let panel = LearningManagementController(approved: approved)
        LearningRuntime.shared.retain(panel); panel.reload()
    }
    @objc func importLearningJSON() {
        guard !IsSecureEventInputEnabled() else { return }
        let panel = LearningManagementController(approved: true)
        LearningRuntime.shared.retain(panel); panel.importJSON()
    }
    @objc func rememberLearningTerm() {
        guard !IsSecureEventInputEnabled() else { return }
        let panel = LearningManagementController(approved: false)
        LearningRuntime.shared.retain(panel)
        if let ascii = state as? InputState.ASCII {
            panel.remember(type: .technical, reading: ascii.composition.raw, text: ascii.composition.display)
        } else if let candidate = state as? InputState.ChoosingCandidate,
                  candidate.candidates.indices.contains(Int(gCurrentCandidateController?.selectedCandidateIndex ?? 0)) {
            let term = candidate.candidates[Int(gCurrentCandidateController?.selectedCandidateIndex ?? 0)]
            panel.remember(type: .zhPhrase, reading: term.reading, text: term.value)
        } else if let current = state as? InputState.NotEmpty {
            let term = current.learningTerms.first { $0.text == current.composingBuffer }
            panel.remember(type: .zhPhrase, reading: term?.reading ?? "", text: current.composingBuffer)
        } else { panel.showMessage(NSLocalizedString("No Reliable Current Term", comment: "")) }
    }
}

/// 管理視窗由明確選單操作開啟；背景整理從不啟動視窗或搶焦點。
@MainActor final class LearningManagementController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let approved: Bool
    private let table = NSTableView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var entries: [LexiconEntry] = []
    private var importToken: UUID?
    private var approvalButton: NSButton?
    init(approved: Bool) {
        self.approved = approved
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 1000,height: 660), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
        window.title = NSLocalizedString(approved ? "User and Engineering Lexicon…" : "Export Review Data…", comment: "")
        super.init(window: window)
        window.center(); window.isReleasedWhenClosed = false
        let column = NSTableColumn(identifier: .init("term")); column.title = NSLocalizedString("Terms and Provenance", comment: ""); column.width = 830
        table.addTableColumn(column); table.dataSource = self; table.delegate = self
        table.allowsMultipleSelection = true; table.rowHeight = 34
        table.target = self; table.doubleAction = #selector(showDetails)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        let actions = NSStackView(); actions.orientation = .vertical; actions.alignment = .leading
        let names: [(String,Selector)] = approved
            ? [("Add Term…",#selector(addTerm)),("Edit Selected Term…",#selector(editTerm)),("Import SQLite / JSON…",#selector(importJSON)),("Export Selected SQLite…",#selector(exportSelected)),
               ("Export Full SQLite…",#selector(exportAllSQLite)),("Restore SQLite…",#selector(restoreSQLite)),("Delete Selected…",#selector(deleteSelected)),("Restore Previous Version…",#selector(rollback)),
               ("Import Legacy User Terms…",#selector(importLegacy)),("Import Built-in Engineering Terms…",#selector(importBundled)),("Export JSON 1.0…",#selector(exportSelectedJSON)),("Select All",#selector(selectAllTerms)),("Cancel Preview",#selector(cancelPreview))]
            : [("Export Selected…",#selector(exportSelected)),("Exclude Selected…",#selector(deleteSelected)),("Clear Review Data…",#selector(clear)),("Export Learning Database…",#selector(exportDatabase)),("Select All",#selector(selectAllTerms))]
        for start in stride(from: 0, to: names.count, by: 4) {
            let row = NSStackView(); row.orientation = .horizontal
            for (name, action) in names[start..<min(start + 4, names.count)] {
                row.addArrangedSubview(NSButton(title: NSLocalizedString(name,comment:""), target: self, action: action))
            }
            actions.addArrangedSubview(row)
        }
        let stack = NSStackView(views: [statusLabel,scroll,actions]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:16),stack.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-16),scroll.widthAnchor.constraint(equalTo:stack.widthAnchor),scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:300)])
    }
    required init?(coder: NSCoder) { nil }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let e = entries[row]
        let count = e.usage?.commit_count ?? 0
        return NSTextField(labelWithString: "\(e.reading) → \(e.text)   \(e.annotation ?? "")   [\(e.source) / \(e.review.status.rawValue), \(count)]")
    }
    func reload() {
        Task {
            do {
                let runtime = LearningRuntime.shared
                if approved { entries = runtime.snapshot.entries }
                else if let store = runtime.store { entries = try await store.entries() + store.suggestions() }
                else { throw LexiconError.invalid("學習資料庫不可用或仍在準備") }
                table.reloadData()
                let audit = approved ? ((try? await runtime.deployment?.auditDescription()) ?? "") : ""
                statusLabel.stringValue = "\(NSLocalizedString(runtime.status,comment:""))\n\(NSLocalizedString("Current Version",comment:"")): \(runtime.snapshot.version)；\(entries.count) \(NSLocalizedString("Terms",comment:""))\n\(audit)"
            } catch { showMessage(error.localizedDescription) }
        }
    }
    @objc private func showDetails() {
        guard let entry = selection.first else { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let bytes = try? encoder.encode(entry) { showMessage(String(decoding: bytes, as: UTF8.self)) }
    }
    @objc private func selectAllTerms() { table.selectAll(nil) }
    private var selection: [LexiconEntry] { table.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0] : nil } }
    func showMessage(_ text: String) {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = NSLocalizedString("AI Lexicon Management",comment:""); alert.informativeText = NSLocalizedString(text, comment: "")
        alert.beginSheetModal(for:window)
    }
    private func confirm(_ text: String, action: @escaping @MainActor () -> Void) {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = NSLocalizedString("Confirm Lexicon Change",comment:""); alert.informativeText = NSLocalizedString(text, comment: "")
        alert.addButton(withTitle:NSLocalizedString("Confirm",comment:"")); alert.addButton(withTitle:NSLocalizedString("Cancel",comment:""))
        alert.beginSheetModal(for:window) { response in if response == .alertFirstButtonReturn { action() } }
    }
    @objc func importJSON() { chooseImport(replacing: false) }
    @objc private func restoreSQLite() { chooseImport(replacing: true) }
    private func chooseImport(replacing: Bool) {
        guard !IsSecureEventInputEnabled(), let window else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json, UTType(filenameExtension: "sqlite") ?? .data]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task {
                do {
                    guard let store = LearningRuntime.shared.deployment else { throw LexiconError.invalid("詞庫管理尚未就緒") }
                    let bytes = try await Task.detached(priority: .utility) {
                        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                        let bytes = try handle.read(upToCount: UnifiedSQLite.maximumBytes + 1) ?? Data()
                        guard bytes.count <= UnifiedSQLite.maximumBytes else { throw LexiconError.invalid("詞庫超過 16 MiB") }
                        return bytes
                    }.value
                    self.displayPreview(try await store.preview(bytes, replacing: replacing), replacing: replacing)
                } catch { self.showMessage(error.localizedDescription) }
            }
        }
    }
    private var restoring = false
    private func displayPreview(_ preview: ImportPreview, replacing: Bool = false, note: String = "") {
        entries = preview.document.entries; table.reloadData(); table.selectAll(nil)
        restoring = replacing; importToken = preview.token
        let counts = String(format: NSLocalizedString("Added %d, changed %d, existing %d, duplicates %d, conflicts %d, proposals %d.", comment: ""), preview.added, preview.changed, preview.existing, preview.duplicates, preview.conflicts, preview.proposals)
        statusLabel.stringValue = counts + "\n" + NSLocalizedString(replacing ? "Restore Replaces Entire Managed Lexicon" : "Review All Rows Before Approval", comment: "")
            + "\n" + NSLocalizedString("Linked Terms Are Included Together", comment: "") + " " + note
        window?.title = NSLocalizedString("Import Preview — Use Approve Selected", comment: "")
        approvalButton?.removeFromSuperview()
        let button = NSButton(title: NSLocalizedString(replacing ? "Confirm Full Replacement…" : "Approve Selected…", comment: ""), target: self, action: #selector(approveImport))
        approvalButton = button
        if let stack = window?.contentView?.subviews.first as? NSStackView { stack.addArrangedSubview(button) }
    }
    @objc private func approveImport() {
        guard let token = importToken, (!selection.isEmpty || restoring), !IsSecureEventInputEnabled() else { return }
        let ids = Set((restoring ? entries : selection).map(\.entry_id))
        confirm(NSLocalizedString(restoring ? "Restore Replaces Entire Managed Lexicon" : "Approve Selected Warning", comment: "")) { [weak self] in
            Task {
                do {
                    guard let store = LearningRuntime.shared.deployment else { return }
                    guard !IsSecureEventInputEnabled() else { return }
                    let preview = try await store.selectPreview(token, keys: ids)
                    await LearningRuntime.shared.publish(try await store.approve(preview.token))
                    self?.importToken = nil; self?.approvalButton?.removeFromSuperview(); self?.approvalButton = nil
                    self?.reload(); self?.showMessage(NSLocalizedString("Lexicon Activated At Safe Boundary", comment: ""))
                } catch { self?.showMessage(error.localizedDescription) }
            }
        }
    }
    @objc private func cancelPreview() {
        if let token = importToken, let store = LearningRuntime.shared.deployment { Task { await store.cancel(token) } }
        importToken = nil; restoring = false; approvalButton?.removeFromSuperview(); approvalButton = nil
        window?.title = NSLocalizedString("User and Engineering Lexicon…", comment: ""); reload()
    }
    @objc private func addTerm() { editTermForm(nil) }
    @objc private func editTerm() {
        guard selection.count == 1, importToken == nil else { showMessage(NSLocalizedString("Select OneSavedTerm", comment: "")); return }
        editTermForm(selection[0])
    }
    private func editTermForm(_ original: LexiconEntry?) {
        guard !IsSecureEventInputEnabled(), let window, importToken == nil else { return }
        let baseRevision = LearningRuntime.shared.snapshot.revision
        let alert = NSAlert(); alert.messageText = NSLocalizedString(original == nil ? "Add Term…" : "Edit Selected Term…", comment: "")
        let types: [TermType] = [.zhPhrase, .english, .technical, .unicode]
        let kind = NSPopUpButton(); kind.addItems(withTitles: ["Chinese Phrase", "English Term", "Engineering Term", "Unicode Mapping"].map { NSLocalizedString($0, comment: "") })
        kind.selectItem(at: original.flatMap { types.firstIndex(of: $0.term_type) } ?? 2)
        let reading = NSTextField(string: original?.reading ?? ""), text = NSTextField(string: original?.text ?? "")
        let annotation = NSTextField(string: original?.annotation ?? ""), category = NSTextField(string: original?.category ?? "")
        let alias = NSTextField(string: ""), aliasReading = NSTextField(string: "")
        let fields = NSStackView(); fields.orientation = .vertical; fields.alignment = .leading
        fields.addArrangedSubview(kind)
        for (title, field) in [("Reading or Input Code", reading), ("Output Text", text), ("Term Annotation", annotation), ("Term Category", category), ("Chinese Alias Optional", alias), ("Chinese Alias Reading", aliasReading)] {
            fields.addArrangedSubview(NSTextField(labelWithString: NSLocalizedString(title, comment: "")))
            fields.addArrangedSubview(field); field.widthAnchor.constraint(equalToConstant: 460).isActive = true
        }
        fields.frame = NSRect(x: 0, y: 0, width: 460, height: 340); alert.accessoryView = fields
        alert.informativeText = NSLocalizedString("Alias Needs Confirmed Reading", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Preview Changes", comment: "")); alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, !IsSecureEventInputEnabled(), let self else { return }
            Task {
                do {
                    guard let store = LearningRuntime.shared.deployment else { throw LexiconError.invalid("詞庫管理尚未就緒") }
                    var entry = LexiconEntry(type: types[kind.indexOfSelectedItem], reading: reading.stringValue, text: text.stringValue, source: "user-editor")
                    entry.annotation = annotation.stringValue.isEmpty ? nil : annotation.stringValue
                    entry.category = category.stringValue.isEmpty ? nil : category.stringValue
                    entry.sources = original?.sources
                    entry.policy = original?.policy
                    try entry.validated()
                    var value = await store.unifiedCurrent()
                    value.document.dictionary_version = UUID().uuidString
                    if let original {
                        value.document.entries.removeAll { $0.entry_id == original.entry_id }
                        value.relations = value.relations.compactMap { relation in
                            var changed = relation
                            if changed.source_id == original.entry_id { changed.source_id = entry.entry_id }
                            if changed.target_id == original.entry_id { changed.target_id = entry.entry_id }
                            return changed
                        }
                    }
                    value.document.entries.removeAll { $0.entry_id == entry.entry_id }; value.document.entries.append(entry)
                    if !alias.stringValue.isEmpty || !aliasReading.stringValue.isEmpty {
                        guard entry.term_type != .zhPhrase else { throw LexiconError.invalid("中文詞請直接編輯讀音；別名用於連結工程輸出") }
                        let chinese = LexiconEntry(type: .zhPhrase, reading: aliasReading.stringValue, text: alias.stringValue, source: "user-editor")
                        try chinese.validated()
                        if !value.document.entries.contains(where: { $0.entry_id == chinese.entry_id }) { value.document.entries.append(chinese) }
                        let relation = LexiconRelation(source: chinese.entry_id, target: entry.entry_id)
                        if !value.relations.contains(relation) { value.relations.append(relation) }
                    }
                    self.displayPreview(try await store.preview(value, replacing: true, expectedRevision: baseRevision), replacing: true)
                } catch { self.showMessage(error.localizedDescription) }
            }
        }
    }
    @objc private func importBundled() {
        guard !IsSecureEventInputEnabled() else { return }
        Task {
            do {
                guard let store = LearningRuntime.shared.deployment else { throw LexiconError.invalid("詞庫管理尚未就緒") }
                let value = try await Task.detached(priority: .utility) {
                    var entries: [LexiconEntry] = [], seen = Set<String>()
                    for term in EngineeringLexicon.bundled.terms {
                        for alias in term.aliases { for output in term.outputs {
                            var entry = LexiconEntry(type: .unicode, reading: alias, text: output, source: "bundled-engineering", annotation: term.annotation)
                            entry.category = term.category; entry.sources = term.sources
                            try entry.validated()
                            if seen.insert(entry.entry_id).inserted { entries.append(entry) }
                        } }
                    }
                    return UnifiedLexicon(document: LexiconDocument(entries: entries))
                }.value
                displayPreview(try await store.preview(value), note: NSLocalizedString("AnnotationsAreNotReadings", comment: ""))
            } catch { showMessage(error.localizedDescription) }
        }
    }
    @objc private func importLegacy() {
        guard !IsSecureEventInputEnabled() else { return }
        // 只有使用者點選此入口才讀既有私人詞檔；保留檔案與原引擎行為。
        let phrasePath = LanguageModelManager.userPhrasesDataPathMcBopomofo
        let excludedPath = LanguageModelManager.excludedPhrasesDataPathMcBopomofo
        Task {
            do {
                guard let store = LearningRuntime.shared.deployment else { throw LexiconError.invalid("詞庫管理尚未就緒") }
                let imported = try await Task.detached(priority: .utility) {
                    func read(_ path: String, optional: Bool = false) throws -> String {
                        if optional && !FileManager.default.fileExists(atPath: path) { return "" }
                        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)); defer { try? handle.close() }
                        let data = try handle.read(upToCount: 4 * 1024 * 1024 + 1) ?? Data()
                        guard data.count <= 4 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw LexiconError.invalid("舊詞庫格式或大小不合法") }
                        return text
                    }
                    return try LegacyTermImport(phrases: read(phrasePath), excluded: read(excludedPath, optional: true))
                }.value
                let summary = String(format: NSLocalizedString("LegacyImportSkipped", comment: ""), imported.excludedCount, imported.rejectedLines.map(String.init).joined(separator: ", "))
                displayPreview(try await store.preview(UnifiedLexicon(document: LexiconDocument(entries: imported.entries))), note: summary)
            } catch { showMessage(error.localizedDescription) }
        }
    }
    @objc private func exportSelected() {
        guard importToken == nil else { showMessage(NSLocalizedString("CompleteOrCancelPreview", comment: "")); return }
        guard !selection.isEmpty, !IsSecureEventInputEnabled() else { showMessage(NSLocalizedString("Select Terms First", comment: "")); return }
        if !approved { exportSelectedJSON(); return }
        let ids = Set(selection.map(\.entry_id))
        save(suggested: "selected-lexicon.sqlite") {
            guard let store = LearningRuntime.shared.deployment else { throw LexiconError.invalid("詞庫管理尚未就緒") }
            return try await store.exportSQLite(keys: ids)
        }
    }
    @objc private func exportAllSQLite() {
        guard importToken == nil else { showMessage(NSLocalizedString("CompleteOrCancelPreview", comment: "")); return }
        guard !IsSecureEventInputEnabled() else { return }
        save(suggested: "lexicon.sqlite") {
            guard let store = LearningRuntime.shared.deployment else { throw LexiconError.invalid("詞庫管理尚未就緒") }
            return try await store.exportSQLite()
        }
    }
    @objc private func exportSelectedJSON() {
        guard importToken == nil else { showMessage(NSLocalizedString("CompleteOrCancelPreview", comment: "")); return }
        guard !selection.isEmpty, !IsSecureEventInputEnabled() else { showMessage(NSLocalizedString("Select Terms First", comment: "")); return }
        let values = LexiconDocument.mergedReviewEntries(selection), ids = Set(values.map(\.entry_id))
        if approved && LearningRuntime.shared.snapshot.relations.contains(where: { ids.contains($0.source_id) || ids.contains($0.target_id) }) {
            showMessage(NSLocalizedString("JSON Cannot Preserve Relations", comment: "")); return
        }
        save(suggested: approved ? "approved-lexicon.json" : "lexicon-review.json") {
            try await Task.detached { try LexiconDocument(type: self.approved ? "approved" : "review", entries: values).exchangeData() }.value
        }
    }
    private func save(suggested: String, data: @escaping @MainActor () async throws -> Data) {
        guard let window else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = suggested
        panel.beginSheetModal(for:window) { [weak self] response in
            guard response == .OK, let url = panel.url, !IsSecureEventInputEnabled() else { return }
            Task { do { let bytes = try await data(); try await Task.detached { try bytes.write(to:url,options:.atomic); try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path) }.value; self?.showMessage(NSLocalizedString("Export Completed",comment:"")) } catch { self?.showMessage(error.localizedDescription) } }
        }
    }
    @objc private func deleteSelected() {
        guard importToken == nil, !IsSecureEventInputEnabled() else { return }
        let ids = Set(selection.map(\.entry_id)); guard !ids.isEmpty else { return }
        confirm(NSLocalizedString(approved ? "Delete Approved Terms Warning" : "Exclude Terms Warning",comment:"")) { [weak self] in
            Task {
                do {
                    guard let self else { return }
                    if self.approved, let store = LearningRuntime.shared.deployment {
                        let p = try await store.deletionPreview(keys:ids)
                        await LearningRuntime.shared.publish(try await store.approve(p.token))
                    } else { try await LearningRuntime.shared.exclude(ids) }
                    self.reload()
                } catch { self?.showMessage(error.localizedDescription) }
            }
        }
    }
    @objc private func rollback() {
        guard importToken == nil, !IsSecureEventInputEnabled() else { return }
        confirm(NSLocalizedString("Rollback Lexicon Warning",comment:"")) { [weak self] in
            Task { do { guard let store = LearningRuntime.shared.deployment else { return }; await LearningRuntime.shared.publish(try await store.rollback()); self?.reload() } catch { self?.showMessage(error.localizedDescription) } }
        }
    }
    @objc private func clear() {
        confirm(NSLocalizedString("Clear Review Data Warning",comment:"")) { [weak self] in
            Task { do { try await LearningRuntime.shared.clearObservations(); self?.reload() } catch { self?.showMessage(error.localizedDescription) } }
        }
    }
    @objc private func exportDatabase() {
        guard let window, !IsSecureEventInputEnabled() else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "learning-backup.sqlite"
        panel.beginSheetModal(for:window) { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { do { guard let store = LearningRuntime.shared.store else { throw LexiconError.invalid("學習資料庫不可用") }; try await store.backup(to:url); self?.showMessage(NSLocalizedString("Export Completed",comment:"")) } catch { self?.showMessage(error.localizedDescription) } }
        }
    }
    func remember(type: TermType, reading: String, text: String) {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = NSLocalizedString("Remember Current Term…",comment:"")
        alert.informativeText = NSLocalizedString("Remember Term Warning",comment:"")
        let code = NSTextField(string:reading), value = NSTextField(string:text)
        let fields = NSStackView(views:[NSTextField(labelWithString:NSLocalizedString("Reading or Input Code",comment:"")),code,NSTextField(labelWithString:NSLocalizedString("Output Text",comment:"")),value]); fields.orientation = .vertical; fields.frame = NSRect(x:0,y:0,width:400,height:110)
        alert.accessoryView = fields; alert.addButton(withTitle:NSLocalizedString("Confirm",comment:"")); alert.addButton(withTitle:NSLocalizedString("Cancel",comment:""))
        alert.beginSheetModal(for:window) { [weak self] response in
            guard response == .alertFirstButtonReturn, !IsSecureEventInputEnabled() else { return }
            do { let entry = LexiconEntry(type:type,reading:code.stringValue,text:value.stringValue); try entry.validated(); guard LearningRuntime.shared.offer(entry,kind:.explicitRemember) else { throw LexiconError.invalid("學習暫停或佇列已滿，未記住此詞") }; self?.showMessage(NSLocalizedString("Remembered For Review",comment:"")) } catch { self?.showMessage(error.localizedDescription) }
        }
    }
}
