// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Cocoa
import Carbon
import UniformTypeIdentifiers
import LearningCore

@MainActor extension McBopomofoInputMethodController {
    func addLearningMenu(to menu: NSMenu) {
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
        Preferences.lexiconObservationEnabled = false; Preferences.lexiconOrganizerEnabled = false; Preferences.approvedLexiconEnabled = false
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
    private var importBytes: Data?
    private var approvalButton: NSButton?
    init(approved: Bool) {
        self.approved = approved
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 880,height: 540), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
        window.title = NSLocalizedString(approved ? "Manage Approved Lexicon…" : "Export Review Data…", comment: "")
        super.init(window: window)
        window.center(); window.isReleasedWhenClosed = false
        let column = NSTableColumn(identifier: .init("term")); column.title = NSLocalizedString("Terms and Provenance", comment: ""); column.width = 830
        table.addTableColumn(column); table.dataSource = self; table.delegate = self
        table.allowsMultipleSelection = true; table.rowHeight = 34
        table.target = self; table.doubleAction = #selector(showDetails)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        let actions = NSStackView(); actions.orientation = .horizontal
        let names: [(String,Selector)] = approved
            ? [("Import Lexicon JSON…",#selector(importJSON)),("Export Selected…",#selector(exportSelected)),("Delete Selected…",#selector(deleteSelected)),("Restore Previous Version…",#selector(rollback))]
            : [("Export Selected…",#selector(exportSelected)),("Exclude Selected…",#selector(deleteSelected)),("Clear Review Data…",#selector(clear)),("Export Learning Database…",#selector(exportDatabase))]
        for (name, action) in names { actions.addArrangedSubview(NSButton(title: NSLocalizedString(name,comment:""), target: self, action: action)) }
        let all = NSButton(title: NSLocalizedString("Select All",comment:""), target:self, action:#selector(selectAllTerms)); actions.addArrangedSubview(all)
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
    @objc func importJSON() {
        guard !IsSecureEventInputEnabled(), let window else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for:window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task {
                do {
                    guard let store = LearningRuntime.shared.deployment else { throw LexiconError.invalid("詞庫管理尚未就緒") }
                    let bytes = try await Task.detached(priority:.utility) {
                        let handle = try FileHandle(forReadingFrom:url); defer { try? handle.close() }
                        let bytes = try handle.read(upToCount:8*1024*1024+1) ?? Data()
                        guard bytes.count <= 8*1024*1024 else { throw LexiconError.invalid("檔案超過 8 MiB") }; return bytes
                    }.value
                    let preview = try await store.preview(bytes)
                    self.entries = preview.document.entries; self.table.reloadData(); self.table.selectAll(nil)
                    let counts = String(format: NSLocalizedString("Added %d, changed %d, existing %d, duplicates %d, conflicts %d, proposals %d.", comment: ""), preview.added, preview.changed, preview.existing, preview.duplicates, preview.conflicts, preview.proposals)
                    let summary = "\(NSLocalizedString("Import Diff Summary",comment:""))\n\(counts)\n\(NSLocalizedString("Review All Rows Before Approval",comment:""))"
                    self.statusLabel.stringValue = summary
                    // 先展示逐詞資料；核准是另一個明確按鈕，不在檔案選取完成時自動執行。
                    self.importBytes = bytes
                    self.window?.title = NSLocalizedString("Import Preview — Use Approve Selected",comment:"")
                    self.approvalButton?.removeFromSuperview()
                    let button = NSButton(title:NSLocalizedString("Approve Selected…",comment:""),target:self,action:#selector(self.approveImport))
                    self.approvalButton = button
                    if let stack = self.window?.contentView?.subviews.first as? NSStackView { stack.addArrangedSubview(button) }
                } catch { self.showMessage(error.localizedDescription) }
            }
        }
    }
    @objc private func approveImport() {
        guard let bytes = importBytes, !selection.isEmpty, !IsSecureEventInputEnabled() else { return }
        let selected = selection
        confirm(NSLocalizedString("Approve Selected Warning",comment:"")) { [weak self] in
            Task {
                do {
                    guard let store = LearningRuntime.shared.deployment else { return }
                    let selectedBytes = try await Task.detached(priority: .utility) {
                        var doc = try LexiconDocument.decode(bytes); doc.entries = selected
                        return try doc.exchangeData()
                    }.value
                    let preview = try await store.preview(selectedBytes)
                    await LearningRuntime.shared.publish(try await store.approve(preview.token))
                    self?.importBytes = nil; self?.approvalButton?.removeFromSuperview(); self?.approvalButton = nil; self?.reload(); self?.showMessage(NSLocalizedString("Lexicon Activated At Safe Boundary",comment:""))
                } catch { self?.showMessage(error.localizedDescription) }
            }
        }
    }
    @objc private func exportSelected() {
        guard !selection.isEmpty, !IsSecureEventInputEnabled() else { showMessage(NSLocalizedString("Select Terms First",comment:"")); return }
        let values = LexiconDocument.mergedReviewEntries(selection)
        save(suggested: approved ? "approved-lexicon.json" : "lexicon-review.json") {
            try await Task.detached { try LexiconDocument(type:self.approved ? "approved" : "review", entries:values).exchangeData() }.value
        }
    }
    private func save(suggested: String, data: @escaping @MainActor () async throws -> Data) {
        guard let window else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = suggested
        panel.beginSheetModal(for:window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { do { let bytes = try await data(); try await Task.detached { try bytes.write(to:url,options:.atomic); try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path) }.value; self?.showMessage(NSLocalizedString("Export Completed",comment:"")) } catch { self?.showMessage(error.localizedDescription) } }
        }
    }
    @objc private func deleteSelected() {
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
