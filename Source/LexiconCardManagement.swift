// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Cocoa
import Carbon
import UniformTypeIdentifiers
import LearningCore
import LearningStorage
import LearningOrganizer
import LexiconDeployment
import CandidateRanking
import MixedInputCore

/// 所有編輯先留在視窗草稿；只在明確確認後建立核准版本。
@MainActor final class LexiconCardManagementController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private var graph = CardGraph()
    private var baseline = CardGraph()
    private var revision = ""
    private var visible: [LexiconConcept] = []
    private var dirty = false
    private var validating = false
    private var pending: CardReviewSession?
    private var modelTask: Task<Void, Never>?
    private let table = NSTableView()
    private let search = NSSearchField()
    private let details = NSTextView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let filter = NSPopUpButton()
    private func tr(_ s: String) -> String { NSLocalizedString(s, comment: "") }
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1050, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: window); window.title = tr("Vocabulary Cards"); window.center(); window.isReleasedWhenClosed = false; window.delegate = self
        search.placeholderString = tr("Search Chinese, English, Bopomofo or symbols"); search.target = self; search.action = #selector(refresh)
        filter.addItems(withTitles: ["All", "Chinese", "English", "Terms and Symbols"].map(tr)); filter.target = self; filter.action = #selector(refresh)
        let column = NSTableColumn(identifier: .init("card")); column.title = tr("Meaning and Names"); column.width = 850
        table.addTableColumn(column); table.dataSource = self; table.delegate = self; table.allowsMultipleSelection = true
        let list = NSScrollView(); list.documentView = table; list.hasVerticalScroller = true
        details.isEditable = false; details.isRichText = false; details.font = .systemFont(ofSize: 14)
        let detailScroll = NSScrollView(); detailScroll.documentView = details; detailScroll.hasVerticalScroller = true
        let actions: [(String, Selector)] = [("New Card…",#selector(addCard)),("Edit Meaning…",#selector(editMeaning)),("Add Name…",#selector(addName)),("Edit Name…",#selector(editName)),("Remove Name…",#selector(removeName)),("Delete Card…",#selector(deleteCard)),("Organize with FM",#selector(organize)),("Review Suggestions…",#selector(reviewSuggestions)),("Save and Apply…",#selector(save)),("Link Cards…",#selector(linkCards)),("Merge Cards…",#selector(mergeCards)),("Split Name…",#selector(splitName)),("Remove Relationship…",#selector(removeRelation)),("Discard Changes",#selector(discard)),("Import…",#selector(importFile)),("Import Legacy Terms…",#selector(importLegacy)),("Import Built-in Terms…",#selector(importBundled)),("Review Observed Terms…",#selector(importObserved)),("Export All…",#selector(exportAll)),("Export Selected…",#selector(exportSelected)),("Restore Previous Version…",#selector(rollback)),("Restore Original Legacy Version…",#selector(restoreOriginal))]
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        let top = NSStackView(views: [search,filter]); stack.addArrangedSubview(top); stack.addArrangedSubview(status); stack.addArrangedSubview(list); stack.addArrangedSubview(detailScroll)
        let primary = Set(["New Card…", "Edit Meaning…", "Add Name…", "Edit Name…", "Organize with FM", "Review Suggestions…", "Save and Apply…"])
        let row = NSStackView()
        for (title,action) in actions where primary.contains(title) { row.addArrangedSubview(NSButton(title: tr(title), target: self, action: action)) }
        stack.addArrangedSubview(row)
        let more = NSPopUpButton(frame: .zero, pullsDown: true); more.addItem(withTitle: tr("Data and Maintenance"))
        for (title,action) in actions where !primary.contains(title) { let item = NSMenuItem(title: tr(title), action: action, keyEquivalent: ""); item.target = self; more.menu?.addItem(item) }
        stack.addArrangedSubview(NSStackView(views: [more, NSButton(title: tr("Cancel FM Organization"), target: self, action: #selector(cancelCardOrganization))]))
        stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 16),stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -16),stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 16),stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -16),list.widthAnchor.constraint(equalTo: stack.widthAnchor),list.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),detailScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),detailScroll.heightAnchor.constraint(equalToConstant: 210),search.widthAnchor.constraint(greaterThanOrEqualToConstant: 420)])
        reload()
    }
    required init?(coder: NSCoder) { nil }
    private var selected: LexiconConcept? { visible.indices.contains(table.selectedRow) ? visible[table.selectedRow] : nil }
    private var selectedIDs: Set<String> { Set(table.selectedRowIndexes.compactMap { visible.indices.contains($0) ? visible[$0].id : nil }) }
    private func message(_ text: String) { status.stringValue = text }
    private func allowed() -> Bool {
        guard !validating else { message(tr("Please wait for draft validation")); return false }
        guard !IsSecureEventInputEnabled() else { message(tr("Unavailable during Secure Input")); return false }; return true
    }
    private func reload() {
        Task {
            do {
                guard let store = LearningRuntime.shared.deployment else { throw LexiconError.invalid(tr("Lexicon storage is not ready")) }
                graph = try await store.cardGraph(); baseline = graph; revision = await store.snapshot().revision; dirty = false
                let path = LearningRuntime.shared.root.appendingPathComponent("card-proposals.json")
                let data = await Task.detached(priority: .utility) { () -> Data? in
                    guard let h = try? FileHandle(forReadingFrom: path) else { return nil }; defer { try? h.close() }
                    return try? h.read(upToCount: 16*1024*1024+1)
                }.value
                if let data, data.count <= 16*1024*1024 { pending = try? JSONDecoder().decode(CardReviewSession.self, from: data) }
                if pending?.proposal.base_revision != revision { pending = nil }
                refresh()
            } catch { message(error.localizedDescription) }
        }
    }
    @objc private func refresh() {
        let selection = selectedIDs
        let query = search.stringValue.lowercased(), kind = filter.indexOfSelectedItem
        let forms = Dictionary(uniqueKeysWithValues: graph.forms.map { ($0.id, $0) })
        let names = Dictionary(grouping: graph.names, by: \.concept_id)
        let codes = Dictionary(grouping: graph.bindings, by: \.name_id)
        visible = graph.concepts.filter { c in
            let ns = names[c.id] ?? [], fs = ns.compactMap { forms[$0.form_id] }
            let kinds: Set<String> = kind == 1 ? ["zh"] : kind == 2 ? ["en"] : kind == 3 ? ["abbreviation", "symbol"] : []
            let text = ([c.definition,c.domain] + fs.map(\.text) + ns.flatMap { codes[$0.id] ?? [] }.map(\.code)).joined(separator: " ")
            return (kinds.isEmpty || fs.contains { kinds.contains($0.kind) }) && (query.isEmpty || text.lowercased().contains(query))
        }
        table.reloadData()
        table.selectRowIndexes(IndexSet(visible.indices.filter { selection.contains(visible[$0].id) }), byExtendingSelection: false)
        tableSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
        if modelTask == nil { message(tr(dirty ? "Draft changes are not active" : "Approved vocabulary; legacy files remain unchanged") + " · \(graph.concepts.count) " + tr("cards")) }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let c = visible[row], names = graph.names.filter { $0.concept_id == c.id }.compactMap { n in graph.forms.first { $0.id == n.form_id }?.text }
        return NSTextField(labelWithString: c.definition + "   " + names.joined(separator: " / "))
    }
    func tableViewSelectionDidChange(_ notification: Notification) { tableSelectionDidChange(notification) }
    private func tableSelectionDidChange(_ notification: Notification) {
        guard let c = selected else { details.string = tr("Select a card to view its names and input rules"); return }
        var lines = [c.definition + " [" + c.domain + "]"]
        for n in graph.names where n.concept_id == c.id {
            guard let f = graph.forms.first(where: { $0.id == n.form_id }) else { continue }
            let codes = graph.bindings.filter { $0.name_id == n.id }.map(\.code).joined(separator: " / ")
            lines.append("\(tr(f.kind))  \(f.text)    \(tr("Input")): \(codes)    [\(n.source)]")
        }
        for r in graph.relations where r.source_id == c.id || r.target_id == c.id {
            let other = r.source_id == c.id ? r.target_id : r.source_id
            lines.append("\(tr(r.kind)) → \(graph.concepts.first { $0.id == other }?.definition ?? other)")
        }
        if graph.legacy_links.contains(where: { $0.source_id == c.id || $0.target_id == c.id }) { lines.append(tr("Legacy links retained; shared meaning has not been confirmed")) }
        let subjects = Set(graph.names.filter { $0.concept_id == c.id }.map(\.id) + [c.id])
        for origin in graph.origins where subjects.contains(origin.subject_id) { lines.append("[\(origin.source)] \(origin.reference)") }
        details.string = lines.joined(separator: "\n\n")
    }
    private func fields(_ title: String, labels: [String], values: [String], done: @escaping ([String]) -> Void) {
        guard allowed(), let window else { return }
        let alert = NSAlert(); alert.messageText = tr(title); alert.addButton(withTitle: tr("Continue")); alert.addButton(withTitle: tr("Cancel"))
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading
        let inputs = values.map { NSTextField(string: $0) }
        for (label,input) in zip(labels,inputs) { stack.addArrangedSubview(NSTextField(labelWithString: tr(label))); stack.addArrangedSubview(input); input.widthAnchor.constraint(equalToConstant: 520).isActive = true }
        stack.frame = NSRect(x: 0,y: 0,width: 540,height: labels.count * 52); alert.accessoryView = stack
        alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { done(inputs.map(\.stringValue)) } }
    }
    private func confirm(_ title: String, text: String, done: @escaping () -> Void) {
        guard allowed(), let window else { return }
        let a = NSAlert(); a.messageText = tr(title); if text.count > 1200 {
            let view = NSTextView(frame: NSRect(x: 0,y: 0,width: 680,height: 360)); view.isEditable = false; view.isRichText = false; view.string = text
            let scroll = NSScrollView(frame: view.frame); scroll.documentView = view; scroll.hasVerticalScroller = true; a.accessoryView = scroll
        } else { a.informativeText = text }; a.addButton(withTitle: tr("Confirm")); a.addButton(withTitle: tr("Cancel"))
        a.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { done() } }
    }
    @objc private func addCard() { fields("New Card…", labels: ["Meaning", "Domain"], values: ["", ""]) { [self] values in
        var next = graph; next.concepts.append(.init(definition: values[0], domain: values[1])); change(next)
    } }
    @objc private func editMeaning() { guard let c = selected else { return }; fields("Edit Meaning…", labels: ["Meaning", "Domain"], values: [c.definition,c.domain]) { [self] values in
        var next = graph; if let i = next.concepts.firstIndex(where: { $0.id == c.id }) { next.concepts[i].definition = values[0]; next.concepts[i].domain = values[1] }; change(next)
    } }
    private func change(_ value: CardGraph) {
        guard !validating else { return }; validating = true
        Task { do {
            try await Task.detached(priority: .utility) { try value.validated() }.value
            graph = value; dirty = graph != baseline; validating = false; refresh()
        } catch { validating = false; message(error.localizedDescription) } }
    }
    private func performEdit(_ edit: @escaping @Sendable (inout CardGraph) throws -> Void) {
        guard allowed() else { return }; validating = true; let original = graph
        Task { do {
            let next = try await Task.detached(priority: .utility) { var next = original; try edit(&next); try next.validated(); return next }.value
            graph = next; dirty = graph != baseline; validating = false; refresh()
        } catch { validating = false; message(error.localizedDescription) } }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if validating { return false }
        if dirty {
            confirm("Discard Changes", text: tr("Unsaved card edits will be discarded.")) { [self] in dirty = false; sender.close(); modelTask?.cancel() }
            return false
        }
        modelTask?.cancel(); return true
    }
    @objc private func addName() { nameDialog(nil) }
    @objc private func editName() { chooseName { [self] in nameDialog($0) } }
    @objc private func removeName() { chooseName { [self] n in performEdit { try $0.removeName(n.id) } } }
    private func chooseName(_ done: @escaping (ConceptForm) -> Void) {
        guard allowed(), let c = selected, let window else { return }
        let ns = graph.names.filter { $0.concept_id == c.id }; guard !ns.isEmpty else { return }
        let picker = NSPopUpButton(frame: NSRect(x: 0,y: 0,width: 500,height: 28))
        picker.addItems(withTitles: ns.map { n in graph.forms.first { $0.id == n.form_id }?.text ?? "" })
        let a = NSAlert(); a.messageText = tr("Choose a name"); a.accessoryView = picker; a.addButton(withTitle: tr("Continue")); a.addButton(withTitle: tr("Cancel"))
        a.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn, ns.indices.contains(picker.indexOfSelectedItem) { done(ns[picker.indexOfSelectedItem]) } }
    }
    private func nameDialog(_ name: ConceptForm?) {
        guard allowed(), let c = selected, let window else { return }
        let f = name.flatMap { n in graph.forms.first { $0.id == n.form_id } }
        let text = NSTextField(string: f?.text ?? ""), reading = NSTextField(string: name.map { n in graph.bindings.filter { $0.name_id == n.id && $0.term_type == .zhPhrase }.map(\.code).joined(separator: ";") } ?? "")
        let code = NSTextField(string: name.map { n in graph.bindings.filter { $0.name_id == n.id && $0.term_type != .zhPhrase }.map(\.code).joined(separator: ";") } ?? "")
        let kind = NSPopUpButton(); let kinds = ["zh","en","abbreviation","symbol"]; kind.addItems(withTitles: kinds.map(tr)); kind.selectItem(at: kinds.firstIndex(of: f?.kind ?? "zh") ?? 0)
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading
        for view in [NSTextField(labelWithString: tr("Name")),text,kind,NSTextField(labelWithString: tr("Bopomofo: hyphens between syllables; semicolons between readings")),reading,NSTextField(labelWithString: tr("English input codes: separate with semicolons; empty means display only")),code] { stack.addArrangedSubview(view) }
        stack.frame = NSRect(x: 0,y: 0,width: 560,height: 230); text.widthAnchor.constraint(equalToConstant: 540).isActive = true; reading.widthAnchor.constraint(equalToConstant: 540).isActive = true; code.widthAnchor.constraint(equalToConstant: 540).isActive = true
        let a = NSAlert(); a.messageText = tr(name == nil ? "Add Name…" : "Edit Name…"); a.accessoryView = stack; a.addButton(withTitle: tr("Continue")); a.addButton(withTitle: tr("Cancel"))
        a.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn, allowed() else { return }
            func parts(_ s: String) -> [String] { s.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            let output = text.stringValue, selectedKind = kinds[kind.indexOfSelectedItem], codes = parts(code.stringValue), readings = parts(reading.stringValue)
            performEdit { try $0.editName(concept: c.id, nameID: name?.id, text: output, kind: selectedKind, codes: codes, readings: readings) }
        }
    }
    private func chooseTarget(_ done: @escaping (LexiconConcept, LexiconConcept) -> Void) {
        guard allowed(), let source = selected, let window else { return }
        let candidates = graph.concepts.filter { $0.id != source.id }; guard !candidates.isEmpty else { return }
        let picker = NSPopUpButton(frame: NSRect(x: 0,y: 0,width: 500,height: 28)); picker.addItems(withTitles: candidates.map { $0.definition + " [" + $0.domain + "]" })
        let a = NSAlert(); a.messageText = tr("Choose a target meaning"); a.informativeText = source.definition; a.accessoryView = picker; a.addButton(withTitle: tr("Continue")); a.addButton(withTitle: tr("Cancel"))
        a.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn, candidates.indices.contains(picker.indexOfSelectedItem) { done(source, candidates[picker.indexOfSelectedItem]) } }
    }
    @objc private func mergeCards() { chooseTarget { [self] source, target in
        confirm("Merge Cards…", text: source.definition + " → " + target.definition + "\n" + tr("Names and input rules move to the target meaning. Review the resulting draft before saving.")) { [self] in
            performEdit { try $0.mergeConcept(source.id, into: target.id) }
        }
    } }
    @objc private func linkCards() { chooseTarget { [self] source, target in
        guard let window else { return }
        let picker = NSPopUpButton(frame: NSRect(x: 0,y: 0,width: 500,height: 28)); picker.addItems(withTitles: [tr("Target is the broader meaning"),tr("Related meanings")])
        let a = NSAlert(); a.messageText = tr("Link Cards…"); a.informativeText = source.definition + " → " + target.definition; a.accessoryView = picker; a.addButton(withTitle: tr("Continue")); a.addButton(withTitle: tr("Cancel"))
        a.beginSheetModal(for: window) { [self] response in if response == .alertFirstButtonReturn { var next = graph; next.relations.append(.init(from: source.id, to: target.id, kind: picker.indexOfSelectedItem == 0 ? "broader" : "related")); change(next) } }
    } }
    @objc private func splitName() { chooseName { [self] name in
        fields("Split Name…", labels: ["Meaning", "Domain"], values: ["", ""]) { [self] values in
            var next = graph; let c = LexiconConcept(definition: values[0], domain: values[1]); next.concepts.append(c)
            if let i = next.names.firstIndex(where: { $0.id == name.id }) { next.names[i].concept_id = c.id }; change(next)
        }
    } }
    @objc private func removeRelation() {
        guard allowed(), let c = selected, let window else { return }
        let relations = graph.relations.filter { $0.source_id == c.id || $0.target_id == c.id }; guard !relations.isEmpty else { return }
        let picker = NSPopUpButton(frame: NSRect(x: 0,y: 0,width: 500,height: 28))
        picker.addItems(withTitles: relations.map { r in tr(r.kind) + ": " + (graph.concepts.first { $0.id == r.source_id }?.definition ?? "") + " → " + (graph.concepts.first { $0.id == r.target_id }?.definition ?? "") })
        let a = NSAlert(); a.messageText = tr("Remove Relationship…"); a.accessoryView = picker; a.addButton(withTitle: tr("Continue")); a.addButton(withTitle: tr("Cancel"))
        a.beginSheetModal(for: window) { [self] response in
            if response == .alertFirstButtonReturn, relations.indices.contains(picker.indexOfSelectedItem) { var next = graph; next.relations.removeAll { $0.id == relations[picker.indexOfSelectedItem].id }; next.pruneOrigins(); change(next) }
        }
    }
    @objc private func deleteCard() {
        let ids = selectedIDs; guard !ids.isEmpty else { return }
        confirm("Delete selected cards?", text: tr("Other sources may still provide the same words. Changes remain a draft until saved.")) { [self] in change(graph.selecting(Set(graph.concepts.map(\.id)).subtracting(ids))) }
    }
    @objc private func discard() { confirm("Discard Changes", text: tr("Unsaved card edits will be discarded.")) { [self] in graph = baseline; dirty = false; refresh() } }
    @objc private func save() {
        guard allowed(), dirty else { return }
        let draft = graph, base = revision
        let text = tr("Save these changes as a new approved version?") + "\n" + summary(from: baseline, to: draft)
        confirm("Save and Apply…", text: text) { [self] in
            Task { do {
                guard allowed(), let store = LearningRuntime.shared.deployment else { return }
                let preview = try await store.previewCards(draft, expectedRevision: base)
                guard allowed() else { await store.cancel(preview.token); return }
                await LearningRuntime.shared.publish(try await store.approve(preview.token)); reload()
            } catch { message(error.localizedDescription) } }
        }
    }
    private func summary(from old: CardGraph, to new: CardGraph) -> String {
        let ids = Set(old.concepts.map(\.id)), next = Set(new.concepts.map(\.id))
        var lines = ["\(tr("Added")): \(next.subtracting(ids).count) · \(tr("Removed")): \(ids.subtracting(next).count)", "\(tr("Names")): \(old.names.count) → \(new.names.count) · \(tr("Input rules")): \(old.bindings.count) → \(new.bindings.count)"]
        let prior = Dictionary(uniqueKeysWithValues: old.concepts.map { ($0.id, $0) })
        for c in new.concepts where prior[c.id] != c {
            lines.append("\(prior[c.id]?.definition ?? "∅") → \(c.definition) [\(c.domain)]")
        }
        let oldForms = Dictionary(uniqueKeysWithValues: old.forms.map { ($0.id, $0.text) })
        for f in new.forms where oldForms[f.id] != f.text { lines.append("\(oldForms[f.id] ?? "∅") → \(f.text)") }
        for r in new.relations where !old.relations.contains(r) {
            lines.append("\(tr(r.kind)): \(new.concepts.first { $0.id == r.source_id }?.definition ?? "") → \(new.concepts.first { $0.id == r.target_id }?.definition ?? "")")
        }
        for c in old.concepts where !next.contains(c.id) { lines.append("− " + c.definition) }
        let previousBindings = Dictionary(uniqueKeysWithValues: old.bindings.map { ($0.id, $0) }), nextBindings = Dictionary(uniqueKeysWithValues: new.bindings.map { ($0.id, $0) })
        func outputs(_ graph: CardGraph) -> [String: String] {
            let fs = Dictionary(uniqueKeysWithValues: graph.forms.map { ($0.id,$0.text) })
            return Dictionary(uniqueKeysWithValues: graph.names.map { ($0.id,fs[$0.form_id] ?? "") })
        }
        let oldOutputs = outputs(old), newOutputs = outputs(new)
        for b in old.bindings where nextBindings[b.id] != b { lines.append("− \(b.code) → \(oldOutputs[b.name_id] ?? "")") }
        for b in new.bindings where previousBindings[b.id] != b { lines.append("+ \(b.code) → \(newOutputs[b.name_id] ?? "")") }
        return lines.joined(separator: "\n")
    }
    func beginImport() { importFile() }
    @objc private func importFile() {
        guard allowed(), !dirty else { message(tr("Save or discard your draft first")); return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.data, .json]; panel.allowsMultipleSelection = false
        panel.begin { [self] response in guard response == .OK, let url = panel.url else { return }; Task { do {
            let incoming = try await Task.detached(priority: .utility) { () -> CardGraph in
                let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }; let bytes = try h.read(upToCount: 16*1024*1024+1) ?? Data()
                guard bytes.count <= 16*1024*1024 else { throw LexiconError.invalid("詞庫超過 16 MiB") }
                let value = UnifiedSQLite.isSQLite(bytes) ? try UnifiedSQLite.decode(bytes) : UnifiedLexicon(document: try LexiconDocument.decode(bytes))
                return try CardGraph.migrating(value)
            }.value
            guard allowed() else { return }; let base = graph
            let merged = try await Task.detached(priority: .utility) { try base.merging(incoming) }.value
            guard graph == base, allowed() else { return }
            confirm("Import Preview", text: summary(from: graph, to: merged) + "\n" + tr("Imported approval flags do not activate entries. Review the draft, then Save and Apply.")) { [self] in change(merged) }
        } catch { message(error.localizedDescription) } } }
    }
    private func importEntries(_ entries: [LexiconEntry], note: String) {
        guard allowed() else { return }; let base = graph; validating = true
        Task { do {
            let next = try await Task.detached(priority: .utility) {
                let incoming = try CardGraph.migrating(UnifiedLexicon(document: LexiconDocument(entries: entries)))
                return try base.merging(incoming)
            }.value
            validating = false
            confirm("Import Preview", text: note + "\n" + summary(from: base, to: next)) { [self] in change(next) }
        } catch { validating = false; message(error.localizedDescription) } }
    }
    @objc private func importObserved() {
        guard allowed() else { return }
        Task { do {
            guard let store = LearningRuntime.shared.store else { return }
            let entries = try await store.entries(limit: 20_000)
            guard allowed() else { return }
            importEntries(entries, note: tr("Observed words become draft cards only. Review and remove unwanted cards before saving; FM can organize selected drafts."))
        } catch { message(error.localizedDescription) } }
    }
    @objc private func importBundled() {
        guard allowed() else { return }
        Task { do {
            let entries = try await Task.detached(priority: .utility) { () -> [LexiconEntry] in
                var result: [LexiconEntry] = [], seen = Set<String>()
                for term in EngineeringLexicon.bundled.terms { for alias in term.aliases { for text in term.outputs {
                    var entry = LexiconEntry(type: .unicode, reading: alias, text: text, source: "bundled-engineering", annotation: term.annotation)
                    entry.category = term.category; entry.sources = term.sources; try entry.validated()
                    if seen.insert(entry.entry_id).inserted { result.append(entry) }
                } } }; return result
            }.value
            guard allowed() else { return }; importEntries(entries, note: tr("A personal copy is created. Built-in vocabulary remains unchanged; annotations are not verified readings."))
        } catch { message(error.localizedDescription) } }
    }
    @objc private func importLegacy() {
        guard allowed() else { return }
        let path = LanguageModelManager.userPhrasesDataPathMcBopomofo, excluded = LanguageModelManager.excludedPhrasesDataPathMcBopomofo
        Task { do {
            let imported = try await Task.detached(priority: .utility) {
                func read(_ path: String, optional: Bool = false) throws -> String {
                    if optional && !FileManager.default.fileExists(atPath: path) { return "" }
                    let h = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)); defer { try? h.close() }
                    let bytes = try h.read(upToCount: 4*1024*1024+1) ?? Data()
                    guard bytes.count <= 4*1024*1024, let text = String(data: bytes, encoding: .utf8) else { throw LexiconError.invalid("舊詞庫過大或格式不合法") }; return text
                }
                return try LegacyTermImport(phrases: read(path), excluded: read(excluded, optional: true))
            }.value
            guard allowed() else { return }
            importEntries(imported.entries, note: String(format: tr("LegacyImportSkipped"), imported.excludedCount, imported.rejectedLines.map(String.init).joined(separator: ", ")))
        } catch { message(error.localizedDescription) } }
    }
    @objc private func exportAll() { export(selectedOnly: false) }
    @objc private func exportSelected() { export(selectedOnly: true) }
    private func export(selectedOnly: Bool) {
        guard allowed(), !dirty else { message(tr("Save or discard your draft first")); return }
        if selectedOnly && selectedIDs.isEmpty { return }
        let value = selectedOnly ? baseline.selecting(selectedIDs) : baseline
        let panel = NSSavePanel(); panel.nameFieldStringValue = "vocabulary-cards.sqlite"
        panel.message = tr("Only selected cards and their internal links are exported; links to other cards are omitted.")
        panel.begin { [self] response in guard response == .OK, let url = panel.url, allowed() else { return }; Task { do {
            try await Task.detached(priority: .utility) { let data = try UnifiedSQLite.encode(value.exchange()); try data.write(to: url, options: .atomic) }.value
            message(tr("Export completed"))
        } catch { message(error.localizedDescription) } } }
    }
    @objc private func rollback() {
        guard allowed(), !dirty else { message(tr("Save or discard your draft first")); return }
        confirm("Restore Previous Version…", text: tr("The previous approved snapshot will become active at the next safe composition boundary.")) { [self] in Task { do {
            guard allowed(), let store = LearningRuntime.shared.deployment else { return }
            await LearningRuntime.shared.publish(try await store.rollback()); reload()
        } catch { message(error.localizedDescription) } } }
    }
    @objc private func restoreOriginal() {
        guard allowed(), !dirty else { message(tr("Save or discard your draft first")); return }
        confirm("Restore Original Legacy Version…", text: tr("Restore the approved vocabulary from before its first v2 migration. Native user dictionary files are not modified.")) { [self] in Task { do {
            guard allowed(), let store = LearningRuntime.shared.deployment else { return }
            await LearningRuntime.shared.publish(try await store.restoreOriginalV1()); reload()
        } catch { message(error.localizedDescription) } } }
    }
    @objc private func organize() {
        guard allowed() else { return }
        guard modelTask == nil else { message(tr("FM is already organizing these cards. Wait or cancel the request.")); return }
        guard Preferences.lexiconOrganizerEnabled else { message(tr("Enable FM background organization first; one request at a time")); return }
        let ids = selectedIDs
        guard !ids.isEmpty else { message(tr("Select at least one vocabulary card before asking FM.")); return }
        let draft = graph
        let request = CardOrganizationRequest(revision: revision, graph: draft.selecting(ids))
        message(tr("FM is organizing the selected cards (up to 60 seconds). Approved vocabulary is unchanged."))
        modelTask = Task { [weak self] in
            guard let self else { return }; defer { modelTask = nil }
            do {
                let data = try await Task.detached(priority: .utility) { try request.encoded() }.value
                let result = try await ModelServiceClient.shared.organizeCards(data)
                let response = try await Task.detached(priority: .utility) { try request.validateServiceResponse(result) }.value
                var batch = CardProposalBatch(base: request.base_revision, changes: response.changes)
                try Task.checkCancellation()
                guard allowed() else { return }
                guard graph == draft, revision == request.base_revision else { message(tr("Suggestions are stale; organize again")); return }
                guard Preferences.lexiconOrganizerEnabled else { throw ModelServiceFailure.cancelled }
                batch.graph_digest = try draft.digest()
                let session = CardReviewSession(graph: draft, proposal: batch)
                let path = LearningRuntime.shared.root.appendingPathComponent("card-proposals.json")
                let saved = try await Task.detached(priority: .utility) {
                    let bytes = try JSONEncoder().encode(session)
                    try CardProposalPersistence.write(bytes, to: path); return bytes
                }.value
                // 儲存期間若使用者取消或草稿改變，不能在下次開啟視窗時復活舊建議。
                if Task.isCancelled || IsSecureEventInputEnabled() || graph != draft || revision != request.base_revision || !Preferences.lexiconOrganizerEnabled {
                    _ = try await Task.detached(priority: .utility) { try CardProposalPersistence.discard(saved, at: path) }.value
                }
                try Task.checkCancellation()
                guard allowed() else { return }
                guard graph == draft, revision == request.base_revision else { message(tr("Suggestions are stale; organize again")); return }
                guard Preferences.lexiconOrganizerEnabled else { throw ModelServiceFailure.cancelled }
                pending = session
                if response.rejected.isEmpty {
                    message(tr(batch.changes.isEmpty ? "FM completed without new suggestions. Try adding a meaning or domain to the card." : "Suggestions are ready for individual review"))
                } else {
                    let summary = String(format: tr("FM returned %d valid suggestions; %d invalid suggestions were excluded. Nothing has been applied."), batch.changes.count, response.rejected.count)
                    let reasons = response.rejected.map { item in
                        let key: String
                        switch item.reason {
                        case .reading: key = "Chinese name or Bopomofo reading is invalid."
                        case .reference: key = "Card or name reference is invalid, duplicated or self-referential."
                        case .fields: key = "Name, input code or other fields failed validation."
                        }
                        return String(format: tr("Suggestion %d: %@"), item.index, tr(key))
                    }
                    message(([summary] + reasons).joined(separator: "\n"))
                }
            } catch let error as ModelServiceFailure { message(tr(error.messageKey)) }
              catch is CancellationError { message(tr(ModelServiceFailure.cancelled.messageKey)) }
              catch { message(tr("Card organization failed validation or could not save suggestions. Approved vocabulary is unchanged.") + "\n" + error.localizedDescription) }
        }
    }
    @objc private func cancelCardOrganization() {
        guard modelTask != nil else { message(tr("No card organization is running.")); return }
        modelTask?.cancel()
    }
    @objc private func reviewSuggestions() {
        guard allowed(), let window else { return }
        guard let session = pending, !session.proposal.changes.isEmpty else { message(tr("No suggestions to review. Select a card and ask FM first.")); return }
        let batch = session.proposal
        guard graph == session.graph else { message(tr("Suggestions are stale; organize again")); return }
        guard batch.base_revision == revision else { message(tr("Suggestions are stale; organize again")); return }
        let a = NSAlert(); a.messageText = tr("Review Suggestions…"); a.informativeText = tr("Select only the changes you want. They become a draft; Save and Apply confirms deployment.")
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading
        let buttons = batch.changes.map { c -> NSButton in
            let from = session.graph.concepts.first { $0.id == c.concept_id }?.definition ?? ""
            let target = session.graph.concepts.first { $0.id == c.target_id }?.definition
                ?? session.graph.names.first { $0.id == c.target_id }.flatMap { n in session.graph.forms.first { $0.id == n.form_id }?.text } ?? ""
            let label = "\(tr(c.operation)): \(from) → \(target) \(c.text) \(c.reading) \(c.code) — \(c.reason)"
            let b = NSButton(checkboxWithTitle: label, target: nil, action: nil); b.state = .off; return b
        }
        for b in buttons { stack.addArrangedSubview(b) }; stack.frame = NSRect(x: 0,y: 0,width: 720,height: max(40,buttons.count * 36)); a.accessoryView = stack
        a.addButton(withTitle: tr("Apply Selected to Draft")); a.addButton(withTitle: tr("Cancel"))
        a.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn, allowed() else { return }
            let ids = Set(zip(batch.changes,buttons).filter { $0.1.state == .on }.map { $0.0.id }), base = revision
            performEdit { $0 = try batch.applying(selected: ids, to: session.graph, revision: base) }
        }
    }
}
