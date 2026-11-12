// Copyright (c) 2022 and onwards The McBopomofo Authors.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

import CandidateUI
import Carbon
import CoreGraphics
import MixedInputCore
import LexiconDeployment
import CandidateRanking
import Cocoa
import InputMethodKit
import InputSourceHelper
import NotifierUI
import OpenCCBridge
import SystemCharacterInfo
import TooltipUI

extension Bool {
    fileprivate var state: NSControl.StateValue {
        self ? .on : .off
    }
}

private let kMinKeyLabelSize: CGFloat = 10

internal var gCurrentCandidateController: CandidateController?

extension CandidateController {
    static let horizontal = HorizontalCandidateController()
    static let vertical = VerticalCandidateController()
}

@objc(McBopomofoInputMethodController)
class McBopomofoInputMethodController: IMKInputController {

    private static let tooltipController = TooltipController()

    // MARK: -

    var currentClient: Any?
    var keyHandler: KeyHandler = KeyHandler()
    var state: InputState = InputState.Empty()
    let textAssistant = TextAssistant()
    var allowsAutomaticAssistance: Bool {
        !directEnglish && fHoldGesture.phase == .idle
            && (lastInputModifiers ?? []).intersection([.shift, .command, .control, .option, .function, .capsLock]).isEmpty
    }
    var learningSnapshot = LexiconSnapshot()
    var learningAppliedToken: String?
    private var shiftGesture = DoubleShiftGesture()
    private var lastInputModifiers: NSEvent.ModifierFlags?
    // Explicitly enabled, bounded diagnostics. Never record text or key codes.
    private static var shiftDiagnosticLines: [String] = []
    private static var shiftDiagnosticDeadline: TimeInterval = 0
    private static var shiftDiagnosticRemaining = 0
    private enum ShiftDiagnosticEvent: String {
        case start, expired, limit, secureStop, activate, deactivate, setValue
        case recognizedEvents, missingEvent, flags, keyDownReset, matched, toggle
    }
    private var directEnglish = false
    private var modeIndicator: TooltipController?
    private var modeIndicatorTimer: Timer?
    private var fHoldGesture = FHoldGesture()
    private let fReleaseMonitor = FReleaseMonitor()
    private static var didRequestFMonitoring = false
    private var fHoldTimer: Timer?
    private var pendingFEvent: NSEvent?
    private var fHoldStartedAt: TimeInterval?
    private var symbolKeysDown = SymbolKeyOwnership()
    private var initialLetterHold = InitialLetterHoldGesture()
    private var initialLetterTimer: Timer?
    private var initialLetterContext = InitialLetterHoldContext<AnyObject>()

    // Share the stored issues, so a set of issues is shown as notification only once.
    static var latestUserFileIssues: [String] = []

    // MARK: - IMKInputController methods

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        keyHandler.delegate = self
    }

    private var toolsMenu: NSMenu?
    private var toolsWindow: NSPanel?

    /// 系統 IMK 子選單曾無法派送 action；工具改用一般 AppKit 視窗。
    @objc private func showInputTools(_ sender: Any?) {
        guard let toolsMenu else { return }
        toolsWindow?.close()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = NSLocalizedString("Tools and Dictionaries…", comment: "")
        panel.isReleasedWhenClosed = false
        var commands: [NSMenuItem] = []
        func append(_ menu: NSMenu) {
            for item in menu.items where !item.isSeparatorItem {
                commands.append(item)
                if let submenu = item.submenu { append(submenu) }
            }
        }
        append(toolsMenu)
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: commands.count * 34 + 20))
        for (index, item) in commands.enumerated() {
            let y = document.frame.height - CGFloat((index + 1) * 34) - 10
            if item.action != nil {
                let button = InputToolButton(command: item, receiver: self)
                button.frame = NSRect(x: 16, y: y, width: 418, height: 28)
                document.addSubview(button)
            } else {
                let label = NSTextField(labelWithString: item.title)
                label.font = .boldSystemFont(ofSize: 12)
                label.frame = NSRect(x: 16, y: y, width: 418, height: 24)
                document.addSubview(label)
            }
        }
        let scroll = NSScrollView(frame: panel.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.documentView = document
        panel.contentView?.addSubview(scroll)
        document.scroll(NSPoint(x: 0, y: document.frame.height))
        toolsWindow = panel
        panel.center(); panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func menu() -> NSMenu! {
        // IMK 可為刷新內容而查詢選單；查詢不可取消正在輸入的手勢。
        let menu = NSMenu(title: "Input Method Menu")
        menu.autoenablesItems = false
        let directItem = menu.addItem(withTitle: NSLocalizedString("Direct English (Double Shift)", comment: ""),
                                      action: #selector(toggleDirectEnglish(_:)), keyEquivalent: "")
        directItem.state = directEnglish.state

        menu.addItem(
            withTitle: NSLocalizedString("English / ASCII", comment: ""),
            action: #selector(beginASCII(_:)), keyEquivalent: "")
        let mixedItem = menu.addItem(
            withTitle: NSLocalizedString("Shift + Letter Starts English", comment: ""),
            action: #selector(toggleMixedEnglish(_:)), keyEquivalent: "")
        mixedItem.state = Preferences.mixedEnglishEnabled.state
        let delayItem = menu.addItem(withTitle: String(format: NSLocalizedString("Initial Letter Lowercase Delay (%d ms)…", comment: ""),
            Preferences.initialLetterHoldDelayMilliseconds), action: #selector(setInitialLetterHoldDelay(_:)), keyEquivalent: "")
        delayItem.target = self
        if Thread.isMainThread { MainActor.assumeIsolated { addLearningMenu(to: menu) } }
        let engineeringItem = menu.addItem(withTitle: NSLocalizedString("Engineering and Science Lexicon", comment: ""),
                                          action: #selector(toggleEngineeringLexicon(_:)), keyEquivalent: "")
        engineeringItem.state = Preferences.engineeringLexiconEnabled.state
        let checkItem = menu.addItem(withTitle: NSLocalizedString("Check Spelling / Chinese Typos", comment: ""),
                                    action: #selector(checkTextAssistance(_:)), keyEquivalent: "")
        checkItem.isEnabled = keyHandler.canBeginAssistance(with: (state as? InputState.AutomaticAssistance)?.original ?? state)
        let automaticItem = menu.addItem(withTitle: NSLocalizedString("Automatic Suggestions After Pausing", comment: ""),
                                         action: #selector(toggleAutomaticTextAssistance(_:)), keyEquivalent: "")
        automaticItem.state = Preferences.automaticTextAssistanceEnabled.state
        let predictionItem = menu.addItem(withTitle: NSLocalizedString("English Prediction (Tab to Accept)", comment: ""),
                                         action: #selector(toggleEnglishPrediction(_:)), keyEquivalent: "")
        predictionItem.state = Preferences.englishPredictionEnabled.state

        menu.addItem(withTitle: NSLocalizedString("Quick Numbers / Symbols", comment: ""),
                     action: #selector(beginQuickSymbols(_:)), keyEquivalent: "")
        let holdItem = menu.addItem(withTitle: NSLocalizedString("Hold F for Numbers / Symbols", comment: ""),
                                    action: #selector(toggleFHoldSymbols(_:)), keyEquivalent: "")
        holdItem.state = Preferences.fHoldSymbolsEnabled.state
        let permissionTitle = CGPreflightListenEventAccess()
            ? "F Layer Input Monitoring: Allowed" : "Allow Input Monitoring for F Layer"
        menu.addItem(withTitle: NSLocalizedString(permissionTitle, comment: ""),
                     action: #selector(requestFMonitoring(_:)), keyEquivalent: "")

        // Keep these IMK commands at the root of the input menu.
        // Nested commands were visible but did not invoke their actions on the user's system.
        menu.addItem(NSMenuItem.separator())
        let advancedHeading = menu.addItem(
            withTitle: NSLocalizedString("Advanced Tools", comment: ""), action: nil, keyEquivalent: "")
        advancedHeading.isEnabled = false
        menu.addItem(
            withTitle: NSLocalizedString("Diagnose Double Shift (20 Seconds)", comment: ""),
            action: #selector(startShiftDiagnostic(_:)), keyEquivalent: "")
        let legacyItem = menu.addItem(withTitle: NSLocalizedString("Backtick Opens Punctuation List", comment: ""),
                                          action: #selector(toggleBacktickMenu(_:)), keyEquivalent: "")
        legacyItem.state = Preferences.backtickOpensPunctuationList.state

        let chineseConversionItem = menu.addItem(
            withTitle: NSLocalizedString("Convert to Simplified Chinese", comment: ""),
            action: #selector(toggleChineseConverter(_:)), keyEquivalent: "g")
        chineseConversionItem.keyEquivalentModifierMask = [.command, .control]
        chineseConversionItem.state = Preferences.chineseConversionEnabled.state

        let halfWidthPunctuationItem = menu.addItem(
            withTitle: NSLocalizedString("Use Half-Width Punctuations", comment: ""),
            action: #selector(toggleHalfWidthPunctuation(_:)), keyEquivalent: "h")
        halfWidthPunctuationItem.keyEquivalentModifierMask = [.command, .control]
        halfWidthPunctuationItem.state = Preferences.halfWidthPunctuationEnabled.state
        let associatedPhrasesItem = menu.addItem(
            withTitle: NSLocalizedString("Associated Phrases", comment: ""),
            action: #selector(toggleAssociatedPhrasesEnabled(_:)), keyEquivalent: "")
        associatedPhrasesItem.state = Preferences.associatedPhrasesEnabled.state

        let inputMode = keyHandler.inputMode

        // Only Bopomofo mode supports Bopomofo Font Annotation. If support is
        // on, ensure that the user has a way to disable it. Otherwise, only
        // show the item when it is set to show in the input menu.
        if inputMode == .bopomofo
            && (Preferences.showBopomofoFontAnnotationSupportItemInInputMenu
                || Preferences.bopomofoFontAnnotationSupportEnabled)
        {
            let bopomofoFontAnnotationSupportItem = menu.addItem(
                withTitle: NSLocalizedString("Bopomofo Font Annotation Support", comment: ""),
                action: #selector(toggleBopomofoFontAnnotationSupport(_:)), keyEquivalent: "")
            bopomofoFontAnnotationSupportItem.state =
                Preferences.bopomofoFontAnnotationSupportEnabled.state
        }

        let optionKeyPressed = NSEvent.modifierFlags.contains(.option)
        if inputMode == .bopomofo && optionKeyPressed {
            let phaseReplacementItem = menu.addItem(
                withTitle: NSLocalizedString("Use Phrase Replacement", comment: ""),
                action: #selector(togglePhraseReplacement(_:)), keyEquivalent: "")
            phaseReplacementItem.state = Preferences.phraseReplacementEnabled.state
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: NSLocalizedString("User Phrases", comment: ""), action: nil,
            keyEquivalent: "")

        if inputMode == .plainBopomofo {
            if Preferences.enableUserPhrasesInPlainBopomofo {
                menu.addItem(
                    withTitle: NSLocalizedString("Edit User Phrases", comment: ""),
                    action: #selector(openUserPhrasesPlainBopomofo(_:)), keyEquivalent: "")
            }
            menu.addItem(
                withTitle: NSLocalizedString("Edit Excluded Phrases", comment: ""),
                action: #selector(openExcludedPhrasesPlainBopomofo(_:)), keyEquivalent: "")
        } else {
            menu.addItem(
                withTitle: NSLocalizedString("Edit User Phrases", comment: ""),
                action: #selector(openUserPhrases(_:)), keyEquivalent: "")
            menu.addItem(
                withTitle: NSLocalizedString("Edit Excluded Phrases", comment: ""),
                action: #selector(openExcludedPhrasesMcBopomofo(_:)), keyEquivalent: "")
            if optionKeyPressed {
                menu.addItem(
                    withTitle: NSLocalizedString("Edit Phrase Replacement Table", comment: ""),
                    action: #selector(openPhraseReplacementMcBopomofo(_:)), keyEquivalent: "")
            }
        }

        menu.addItem(
            withTitle: NSLocalizedString("Reload User Phrases", comment: ""),
            action: #selector(reloadUserPhrases(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("Import Technical Terms…", comment: ""),
            action: #selector(importTechnicalTerms(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("Export Technical Terms…", comment: ""),
            action: #selector(exportTechnicalTerms(_:)), keyEquivalent: "")

        if !McBopomofoInputMethodController.latestUserFileIssues.isEmpty {
            // Setting menuItem.image does not work in input method menus even on macOS 26,
            // so we just use the alert emoji in the menu item title.
            let menuItem = NSMenuItem(
                title: NSLocalizedString("Show Issues in User Files ⚠️", comment: ""),
                action: #selector(showUserFileIssues(_:)), keyEquivalent: "")
            menu.addItem(menuItem)
        }

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: NSLocalizedString("McBopomofo Preferences", comment: ""),
            action: #selector(showPreferences(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("Check for Updates…", comment: ""),
            action: #selector(checkForUpdate(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("About McBopomofo…", comment: ""),
            action: #selector(showAbout(_:)), keyEquivalent: "")
        // 第一層保留實際輸入操作；其餘設定與維護指令集中到工具視窗。
        let primary: Set<Selector> = [#selector(toggleDirectEnglish(_:)), #selector(beginASCII(_:)),
            #selector(checkTextAssistance(_:)), #selector(beginQuickSymbols(_:)),
            #selector(toggleChineseConverter(_:)), #selector(toggleHalfWidthPunctuation(_:)),
            #selector(showPreferences(_:)), #selector(checkForUpdate(_:)), #selector(showAbout(_:))]
        let compact = NSMenu(title: menu.title)
        compact.autoenablesItems = false
        for item in menu.items where item.action.map({ primary.contains($0) }) == true {
            menu.removeItem(item); compact.addItem(item)
        }
        compact.insertItem(NSMenuItem.separator(), at: 4)
        let tools = NSMenuItem(title: NSLocalizedString("Tools and Dictionaries…", comment: ""),
                              action: #selector(showInputTools(_:)), keyEquivalent: "")
        tools.target = self
        compact.insertItem(tools, at: 5)
        toolsMenu = menu
        return compact
    }

    // MARK: - IMKStateSetting protocol methods

    override func activateServer(_ client: Any!) {
        cancelInitialLetterHold()
        recordShiftDiagnostic(.activate)
        hideInputModeIndicator()
        shiftGesture.reset()
        lastInputModifiers = nil
        directEnglish = false
        textAssistant.cancel()
        cancelFHold(client: client)
        symbolKeysDown.reset()
        UserDefaults.standard.synchronize()

        // Override the keyboard layout. Use US if not set.
        (client as? IMKTextInput)?.overrideKeyboard(
            withKeyboardNamed: Preferences.basisKeyboardLayout)
        // reset the state
        currentClient = client
        if Preferences.fHoldSymbolsEnabled, !CGPreflightListenEventAccess(),
           !Self.didRequestFMonitoring {
            Self.didRequestFMonitoring = true
            _ = CGRequestListenEventAccess()
        }

        keyHandler.clear()
        keyHandler.syncWithPreferences()

        (NSApp.delegate as? AppDelegate)?.checkForUpdate()
    }

    override func deactivateServer(_ client: Any!) {
        cancelInitialLetterHold()
        recordShiftDiagnostic(.deactivate)
        hideInputModeIndicator()
        shiftGesture.reset()
        if let assistance = state as? InputState.Assistance { state = assistance.original }
        textAssistant.cancel()
        if fHoldGesture.phase == .pending { _ = applyFHold(.otherKey, client: client) }
        cancelFHold(client: client)
        symbolKeysDown.reset()
        currentClient = nil
        keyHandler.clear()
        self.handle(state: .Deactivated(), client: client)
    }

    override func setValue(_ value: Any!, forTag tag: Int, client: Any!) {
        cancelInitialLetterHold()
        recordShiftDiagnostic(.setValue)
        hideInputModeIndicator()
        if let assistance = state as? InputState.Assistance {
            handle(state: assistance.original, client: client)
        }
        textAssistant.cancel()
        cancelFHold(client: client)
        let rawMode = value as? String ?? InputMode.bopomofo.rawValue
        if directEnglish {
            commitComposition(client)
            keyHandler.clear()
            handle(state: .EmptyIgnoringPreviousState(), client: client)
        }
        directEnglish = false
        shiftGesture.reset()
        // A cached, retired mode must still use a valid language model after upgrading.
        let newInputMode: InputMode = rawMode == InputMode.plainBopomofo.rawValue
            ? .plainBopomofo : .bopomofo
        LanguageModelManager.loadDataModel(newInputMode)
        // Restore the client layout even when the internal input mode is unchanged.
        (client as? IMKTextInput)?.overrideKeyboard(
            withKeyboardNamed: Preferences.basisKeyboardLayout)
        if keyHandler.inputMode != newInputMode {
            UserDefaults.standard.synchronize()
            // Remember to override the keyboard layout again -- treat this as an activate event.
            keyHandler.clear()
            keyHandler.inputMode = newInputMode
            self.handle(state: .Empty(), client: client)
        }

        // Since setValue is called after activateServer, show user file issues here, if any.
        checkUserFileIssues()
    }

    // MARK: - IMKServerInput protocol methods

    override func commitComposition(_ client: Any!) {
        cancelInitialLetterHold()
        if let assistance = state as? InputState.Assistance { state = assistance.original }
        textAssistant.cancel()
        if fHoldGesture.phase == .pending {
            _ = applyFHold(.otherKey, client: client)
        }
        cancelFHold(client: client)
        if state is InputState.QuickSymbols {
            keyHandler.endQuickSymbols(with: state) { self.handle(state: $0, client: client) }
            if !(state is InputState.ASCII) { return }
        }
        if let ascii = state as? InputState.ASCII {
            keyHandler.clear()
            handle(state: .Committing(poppedText: ascii.composingBuffer), client: client)
            handle(state: .Empty(), client: client)
            return
        }
        keyHandler.handleForceCommit(stateCallback: { newState in
            self.handle(state: newState, client: client)
        })
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        recordShiftDiagnostic(.recognizedEvents)
        let events: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        return Int(events.rawValue)
    }

    @objc private func startShiftDiagnostic(_ sender: Any?) {
        guard !IsSecureEventInputEnabled() else {
            NotifierController.notify(message: NSLocalizedString("Shift Diagnostic Unavailable During Secure Input", comment: ""))
            return
        }
        Self.shiftDiagnosticLines.removeAll()
        Self.shiftDiagnosticDeadline = ProcessInfo.processInfo.systemUptime + 20
        Self.shiftDiagnosticRemaining = 80
        recordShiftDiagnostic(.start)
        let message = Self.shiftDiagnosticDeadline > 0
            ? "Shift Diagnostic Started (20 Seconds)" : "Could Not Create Shift Diagnostic Report"
        NotifierController.notify(message: NSLocalizedString(message, comment: ""))
    }

    private func recordShiftDiagnostic(_ event: ShiftDiagnosticEvent, flags: UInt = 0) {
        guard Self.shiftDiagnosticDeadline > 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let recordedEvent: ShiftDiagnosticEvent
        if IsSecureEventInputEnabled() {
            recordedEvent = .secureStop
        } else if now >= Self.shiftDiagnosticDeadline {
            recordedEvent = .expired
        } else if Self.shiftDiagnosticRemaining <= 0 {
            recordedEvent = .limit
        } else {
            recordedEvent = event
        }
        let stopped = recordedEvent == .secureStop || recordedEvent == .expired || recordedEvent == .limit
        if stopped { Self.shiftDiagnosticDeadline = 0 }
        Self.shiftDiagnosticRemaining -= 1
        let controller = ObjectIdentifier(self).hashValue
        let safeFlags = stopped ? 0 : flags
        Self.shiftDiagnosticLines.append(
            "event=\(recordedEvent.rawValue) controller=\(controller) uptime=\(now) modifiers=\(safeFlags) english=\(directEnglish)")
        do {
            let cache = try FileManager.default.url(
                for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = cache.appendingPathComponent("org.aibopomofo.inputmethod.AIBopomofo", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let report = directory.appendingPathComponent("shift-diagnostic.log")
            let data = Data((Self.shiftDiagnosticLines.joined(separator: "\n") + "\n").utf8)
            try data.write(to: report, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: report.path)
        } catch {
            // A diagnostic write failure must never interfere with ordinary input.
            Self.shiftDiagnosticDeadline = 0
            Self.shiftDiagnosticLines.removeAll()
        }
    }

    @objc private func toggleDirectEnglish(_ sender: Any?) {
        guard !IsSecureEventInputEnabled() else { return }
        commitComposition(currentClient)
        keyHandler.clear()
        handle(state: .EmptyIgnoringPreviousState(), client: currentClient)
        directEnglish.toggle()
        recordShiftDiagnostic(.toggle)
        shiftGesture.reset()
        showInputModeIndicator(client: currentClient)
    }

    @objc private func beginASCII(_ sender: Any?) {
        directEnglish = false
        keyHandler.beginASCII(with: state, stateCallback: { newState in
            self.handle(state: newState, client: self.currentClient)
        }, errorCallback: {
            if Preferences.beepUponInputError { InputFeedback.beep() }
        })
    }

    @objc private func toggleMixedEnglish(_ sender: Any?) {
        cancelInitialLetterHold()
        Preferences.mixedEnglishEnabled.toggle()
    }

    @objc private func setInitialLetterHoldDelay(_ sender: Any?) {
        guard !IsSecureEventInputEnabled() else { return }
        cancelInitialLetterHold()
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Initial Letter Lowercase Delay", comment: "")
        alert.informativeText = NSLocalizedString("Hold the first letter, not Shift. Enter 100–1000 milliseconds; default 250. F layer timing is separate.", comment: "")
        let field = NSTextField(string: String(Preferences.initialLetterHoldDelayMilliseconds))
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: NSLocalizedString("Save", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let value = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              (100...1000).contains(value) else {
            NotifierController.notify(message: NSLocalizedString("Enter a whole number from 100 to 1000 milliseconds.", comment: ""))
            return
        }
        Preferences.initialLetterHoldDelayMilliseconds = value
    }

    private func cancelInitialLetterHold() {
        initialLetterTimer?.invalidate(); initialLetterTimer = nil
        initialLetterHold.cancel(); initialLetterContext.cancel()
    }

    private func lowercaseInitialLetter(client: Any?) {
        guard let shifted = state as? InputState.ShiftASCII,
              let next = shifted.session.lowercasingInitialLetter(lexicon: shifted.sessionLexicon) else { return }
        handle(state: InputState.ShiftASCII(session: next, sessionLexicon: shifted.sessionLexicon), client: client)
    }

    private func scheduleInitialLetterTimer() {
        initialLetterTimer?.invalidate()
        guard let token = initialLetterContext.token else { return }
        let timer = Timer(timeInterval: initialLetterHold.remaining(at: ProcessInfo.processInfo.systemUptime), repeats: false) { [weak self] timer in
            guard let self, let receiver = self.initialLetterContext.resolve(token) else { return }
            self.initialLetterTimer = nil
            guard !IsSecureEventInputEnabled(), !self.directEnglish,
                  let keyCode = self.initialLetterHold.keyCode,
                  (self.state as? InputState.ShiftASCII)?.session.canLowercaseInitialLetter == true else {
                self.cancelInitialLetterHold(); return
            }
            // 只查本次首字母是否仍按住，不建立全域事件監聽，也不記錄按鍵。
            let sessionDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
            let hardwareDown = CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keyCode))
            if self.initialLetterHold.probe(to: ProcessInfo.processInfo.systemUptime,
                sessionKeyDown: sessionDown, hardwareKeyDown: hardwareDown) {
                self.lowercaseInitialLetter(client: receiver)
                self.cancelInitialLetterHold()
            } else if sessionDown || hardwareDown { self.scheduleInitialLetterTimer() }
            // 無法確認按住時不改字、不忙等，保留手勢交給實際 repeat／key-up 結算。
        }
        initialLetterTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateInitialLetterHold(for event: NSEvent, client: Any?) {
        guard let keyCode = initialLetterHold.keyCode else { return }
        guard !IsSecureEventInputEnabled(), initialLetterContext.token != nil,
              event.modifierFlags.intersection([.command, .control, .option, .function, .capsLock]).isEmpty else {
            cancelInitialLetterHold(); return
        }
        if event.type == .keyUp, event.keyCode == keyCode {
            if initialLetterHold.release(at: event.timestamp) { lowercaseInitialLetter(client: client) }
            cancelInitialLetterHold()
        } else if event.type == .keyDown {
            if event.keyCode == keyCode && !event.isARepeat {
                // 同鍵重新按下代表上一按已結束，即使 IMK 遺漏 key-up 也不可補判長按。
                cancelInitialLetterHold(); return
            }
            // 不同新按鍵到達時，先依時間與實體狀態結算，再交給既有英文流程。
            let down = event.keyCode == keyCode && event.isARepeat
                || CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
                || CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keyCode))
            if initialLetterHold.advance(to: event.timestamp, keyIsDown: down) { lowercaseInitialLetter(client: client) }
            if !event.isARepeat || event.keyCode != keyCode || initialLetterHold.keyCode == nil { cancelInitialLetterHold() }
        }
    }

    private func beginInitialLetterHold(after event: NSEvent, client: Any?) {
        guard !event.isARepeat, !IsSecureEventInputEnabled(), Preferences.mixedEnglishEnabled,
              event.modifierFlags.contains(.shift),
              event.modifierFlags.intersection([.command, .control, .option, .function, .capsLock]).isEmpty,
              let shifted = state as? InputState.ShiftASCII, shifted.session.canLowercaseInitialLetter,
              event.characters == shifted.composition.raw, let receiver = client as? IMKTextInput else { return }
        initialLetterContext.begin(receiver: receiver as AnyObject)
        initialLetterHold.begin(keyCode: event.keyCode, at: shifted.session.holdStartedAt ?? event.timestamp,
            delayMilliseconds: shifted.session.holdDelayMilliseconds)
        scheduleInitialLetterTimer()
    }

    @objc func toggleEngineeringLexicon(_ sender: Any?) {
        guard !IsSecureEventInputEnabled() else { return }
        Preferences.engineeringLexiconEnabled.toggle()
        textAssistant.cancel()
        MixedInputHandler.reloadUserTerms()
        // 不提交預覽候選，也不停止 F 放開監聽；只重建當前組字的候選。
        handle(state: MixedInputHandler.reloadingLexicon(state: state), client: currentClient)
    }

    @objc private func toggleBacktickMenu(_ sender: Any?) {
        Preferences.backtickOpensPunctuationList.toggle()
    }

    @objc private func beginQuickSymbols(_ sender: Any?) {
        cancelFHold(client: currentClient)
        keyHandler.beginQuickSymbols(with: state, held: false) {
            self.handle(state: $0, client: self.currentClient)
        }
    }

    @objc private func requestFMonitoring(_ sender: Any?) {
        Self.didRequestFMonitoring = true
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleFHoldSymbols(_ sender: Any?) {
        if fHoldGesture.phase == .pending { _ = applyFHold(.otherKey, client: currentClient) }
        cancelFHold(client: currentClient)
        Preferences.fHoldSymbolsEnabled.toggle()
        if Preferences.fHoldSymbolsEnabled, !CGPreflightListenEventAccess() {
            requestFMonitoring(sender)
        }
    }

    private func cancelFHold(client: Any?) {
        _ = applyFHold(.cancel, client: client)
        pendingFEvent = nil
    }

    @discardableResult
    private func applyFHold(_ gestureEvent: FHoldGesture.Event, client: Any?) -> Bool {
        let effects = fHoldGesture.handle(gestureEvent)
        for effect in effects {
            switch effect {
            case .schedule:
                // Key-down 立即顯示可撤回的原字；引擎直到短按確定才接收一次事件。
                fHoldTimer?.invalidate()
                let started = pendingFEvent?.timestamp ?? ProcessInfo.processInfo.systemUptime
                fHoldStartedAt = started
                let literal = pendingFEvent?.characters ?? "f"
                let preview: String
                if directEnglish || state is InputState.ASCII {
                    preview = literal
                } else if let key = literal.utf16.first {
                    preview = keyHandler.fHoldPreview(key: key) ?? literal
                } else { preview = literal }
                handle(state: InputState.PendingF(original: state, preview: preview), client: client)
                guard fReleaseMonitor.start(onRelease: { [weak self] releasedAt in
                    guard let self else { return }
                    self.advanceFHold(to: releasedAt, client: self.currentClient)
                    self.applyFHold(.observedRelease, client: self.currentClient)
                }) else {
                    // Permission denial or tap failure must never swallow the original F.
                    _ = applyFHold(.release, client: client)
                    continue
                }
                let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] timer in
                    guard let self else { timer.invalidate(); return }
                    guard !IsSecureEventInputEnabled(), self.currentClient != nil else {
                        self.cancelFHold(client: self.currentClient)
                        return
                    }
                    guard self.fReleaseMonitor.isEnabled, CGPreflightListenEventAccess() else {
                        self.applyFHold(.release, client: self.currentClient)
                        return
                    }
                    self.applyFHold(.elapsed(ProcessInfo.processInfo.systemUptime - started),
                                    client: self.currentClient)
                }
                fHoldTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            case .invalidate:
                // 只在手勢結束或取消時清理；提前進入分層不能走這個分支。
                restorePendingF(client: client)
                fHoldStartedAt = nil
                fReleaseMonitor.stop()
                fHoldTimer?.invalidate()
                fHoldTimer = nil
            case .replayTap:
                if let pending = pendingFEvent {
                    pendingFEvent = nil
                    if directEnglish {
                        handle(state: .Committing(poppedText: pending.characters ?? "f"), client: client)
                        handle(state: .Empty(), client: client)
                    } else {
                        _ = handleTextEvent(pending, client: client)
                    }
                }
            case .beginLayer:
                // 撤回的只有本次 marked preview，不刪除使用者已提交的文字。
                // 保留放開監聽，直到真正放開 F 才退出分層。
                restorePendingF(client: client)
                let began = keyHandler.beginQuickSymbols(with: state, held: true) {
                    self.handle(state: $0, client: client)
                }
                if !began, let pending = pendingFEvent {
                    if directEnglish {
                        handle(state: .Committing(poppedText: pending.characters ?? "f"), client: client)
                        handle(state: .Empty(), client: client)
                    } else { _ = handleTextEvent(pending, client: client) }
                }
                pendingFEvent = nil
            case .endLayer:
                if let symbols = state as? InputState.QuickSymbols, symbols.held {
                    keyHandler.endQuickSymbols(with: state) { self.handle(state: $0, client: client) }
                }
            case .consume: break
            }
        }
        // F 的放開可能先由被動監聽器送達；套用最近觀察到的 Shift 狀態，
        // 原組字若來自 Shift 英文，避免包裝狀態留下過期模式。
        releaseShiftCompositionIfNeeded(client: client)
        return effects.contains(.consume)
    }

    private func releaseShiftCompositionIfNeeded(client: Any?) {
        guard let modifiers = lastInputModifiers, !modifiers.contains(.shift),
              !directEnglish, !IsSecureEventInputEnabled() else { return }
        if keyHandler.releaseShift(with: state, stateCallback: { self.handle(state: $0, client: client) }) {
            // 組詞的 Shift 放開不算雙擊 Shift 的第一下。
            shiftGesture.reset()
        }
    }

    private func restorePendingF(client: Any?) {
        if let pending = state as? InputState.PendingF {
            handle(state: pending.original, client: client)
        }
    }

    // An event can arrive after the deadline but before a busy run loop fires the timer.
    private func advanceFHold(to timestamp: TimeInterval, client: Any?) {
        guard let started = fHoldStartedAt else { return }
        _ = applyFHold(.elapsed(timestamp - started), client: client)
    }

    @objc private func importTechnicalTerms(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.importTechnicalTerms(sender)
    }

    @objc private func exportTechnicalTerms(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.exportTechnicalTerms(sender)
    }

    override func handle(_ maybeEvent: NSEvent!, client: Any!) -> Bool {
        if Thread.isMainThread { MainActor.assumeIsolated {
            LearningRuntime.shared.noteActivity(secure: IsSecureEventInputEnabled())
            refreshLearningSnapshotIfIdle()
        } }
        // nil may be passed, applefeedback://FB11472618
        guard let event = maybeEvent else {
            recordShiftDiagnostic(.missingEvent)
            hideInputModeIndicator()
            commitComposition(client)
            return false
        }
        updateInitialLetterHold(for: event, client: client)

        // 副駕駛提示不得攔住 F 手勢或快捷鍵；先恢復原組字再走既有流程。
        if let automatic = state as? InputState.AutomaticAssistance {
            let shortcut = !event.modifierFlags.intersection([.command, .control, .option, .function]).isEmpty
            let key: AutomaticSuggestionKey = event.keyCode == 48 ? (event.modifierFlags.contains(.shift) ? .backTab : .tab)
                : (event.keyCode == 36 || event.keyCode == 76) ? .enter : event.keyCode == 53 ? .escape : .ordinary
            if IsSecureEventInputEnabled() || event.type == .flagsChanged
                || (event.type == .keyDown && AutomaticSuggestionInteraction.action(key: key,
                    selected: automatic.selectedIndex, count: automatic.candidateCount, shortcut: shortcut) == .replayOriginal) {
                handle(state: automatic.original, client: client)
            }
        }

        if event.type == .keyDown || event.type == .keyUp || event.type == .flagsChanged {
            lastInputModifiers = event.modifierFlags
            releaseShiftCompositionIfNeeded(client: client)
        }
        if event.type == .keyDown || IsSecureEventInputEnabled() {
            hideInputModeIndicator()
        }
        if IsSecureEventInputEnabled() {
            recordShiftDiagnostic(.secureStop)
            shiftGesture.reset()
            cancelFHold(client: client)
        }
        else if event.type == .flagsChanged {
            recordShiftDiagnostic(.flags, flags: event.modifierFlags.rawValue)
            let other = !event.modifierFlags.intersection([.command, .control, .option, .function, .capsLock]).isEmpty
            if shiftGesture.update(shiftDown: event.modifierFlags.contains(.shift),
                                   otherModifiers: other, time: ProcessInfo.processInfo.systemUptime) {
                recordShiftDiagnostic(.matched)
                toggleDirectEnglish(nil)
                return true
            }
        } else if event.type == .keyDown {
            recordShiftDiagnostic(.keyDownReset)
            shiftGesture.reset()
        }
        if event.type == .keyDown || event.type == .keyUp {
            advanceFHold(to: event.timestamp, client: client)
        }
        // Keep ownership until key-up even when F was released before a symbol key.
        if event.type == .keyUp, symbolKeysDown.keyUp(event.keyCode) { return true }

        if event.keyCode == UInt16(kVK_ANSI_F), event.type == .keyUp {
            if applyFHold(.release, client: client) { return true }
        } else if event.keyCode == UInt16(kVK_ANSI_F), event.type == .keyDown {
            let forbidden: NSEvent.ModifierFlags = [.shift, .command, .control, .option, .capsLock, .function]
            let eligible = Preferences.fHoldSymbolsEnabled
                && CGPreflightListenEventAccess() && !IsSecureEventInputEnabled()
                && event.modifierFlags.intersection(forbidden).isEmpty
                && keyHandler.canBeginQuickSymbols(with: state)
            if fHoldGesture.phase == .idle && eligible && !event.isARepeat {
                fHoldGesture = FHoldGesture(delayMilliseconds: Preferences.fHoldDelayMilliseconds)
                pendingFEvent = event
            }
            if applyFHold(.press(eligible: eligible, repeating: event.isARepeat), client: client) { return true }
        } else if event.type == .keyDown {
            // 先前已按事件時間結算長按；仍在等待時就先送回 F，再處理本鍵。
            _ = applyFHold(.otherKey, client: client)
        } else if event.type == .flagsChanged &&
                    event.keyCode != UInt16(kVK_Shift) && event.keyCode != UInt16(kVK_RightShift) {
            _ = applyFHold(.otherKey, client: client)
        }

        // The first chord key must acquire ownership after it activates the layer,
        // before normal text routing handles that same key exactly once.
        if event.type == .keyDown,
           symbolKeysDown.keyDown(event.keyCode, repeating: event.isARepeat,
               layerActive: state is InputState.QuickSymbols,
               shortcut: !event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               mapped: (state as? InputState.QuickSymbols).map { QuickSymbolLayer.output(for: event.keyCode, entries: $0.entries) != nil }) {
            return true
        }

        // Preserve F's momentary layer in direct English; other keys pass through literally.
        if directEnglish && !(state is InputState.QuickSymbols) { return false }

        let kind: InputEventKind
        switch event.type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .modifiers
        default: kind = .other
        }
        let hasComposition = !(state is InputState.Empty || state is InputState.EmptyIgnoringPreviousState
            || state is InputState.Committing || state is InputState.Deactivated)
        switch InputEventRouting.route(kind, hasComposition: hasComposition) {
        case .consume: return true
        case .passThrough: return false
        case .text: break
        case .modifiers:
            textAssistant.cancel()
            if let assistance = state as? InputState.Assistance, assistance.isChecking {
                handle(state: assistance.selecting(assistance.selectedIndex), client: client)
            }
            if Preferences.switchInputSourceUponCommandKeyPressEnabled,
               (event.keyCode == UInt16(kVK_Command) || event.keyCode == UInt16(kVK_RightCommand)),
               event.modifierFlags.contains(.command) {
                keyHandler.clear()
                handle(state: InputState.SwitchingInputSource(sourceID: Preferences.switchInputSourceUponCommandKeyPressInputSourceID), client: client)
                return false
            }
            let functionLayout = Preferences.functionKeyboardLayout
            let basisLayout = Preferences.basisKeyboardLayout
            guard functionLayout != basisLayout else { return false }
            let functionModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]
            let useFunctionLayout = !event.modifierFlags.intersection(functionModifiers).isEmpty
                || (event.modifierFlags.contains(.shift)
                    && Preferences.functionKeyKeyboardLayoutOverrideIncludeShiftKey)
            (client as? IMKTextInput)?.overrideKeyboard(
                withKeyboardNamed: useFunctionLayout ? functionLayout : basisLayout)
            return false
        }

        let handled = handleTextEvent(event, client: client)
        if handled { beginInitialLetterHold(after: event, client: client) }
        return handled
    }

    private func handleTextEvent(_ event: NSEvent, client: Any?) -> Bool {
        textAssistant.cancel()
        var textFrame = NSRect.zero
        let attributes: [AnyHashable: Any]? = (client as? IMKTextInput)?.attributes(
            forCharacterIndex: 0, lineHeightRectangle: &textFrame)
        let useVerticalMode =
            (attributes?["IMKTextOrientation"] as? NSNumber)?.intValue == 0 || false
        let input = KeyHandlerInput(event: event, isVerticalMode: useVerticalMode)

        let result = keyHandler.handle(input: input, state: state) { newState in
            self.handle(state: newState, client: client)
        } errorCallback: {
            if Preferences.beepUponInputError {
                InputFeedback.beep()
            }
        }
        releaseShiftCompositionIfNeeded(client: client)
        return result
    }

    // MARK: - Menu Items

    @objc override func showPreferences(_ sender: Any?) {
        super.showPreferences(sender)
    }

    @objc func toggleChineseConverter(_ sender: Any?) {
        let enabled = Preferences.toggleChineseConversionEnabled()
        NotifierController.notify(
            message: enabled
                ? NSLocalizedString("Chinese Conversion On", comment: "")
                : NSLocalizedString("Chinese Conversion Off", comment: ""))
        if let currentClient = currentClient {
            keyHandler.clear()
            self.handle(state: InputState.Empty(), client: currentClient)
        }
    }

    @objc func toggleHalfWidthPunctuation(_ sender: Any?) {
        let enabled = Preferences.toggleHalfWidthPunctuationEnabled()
        NotifierController.notify(
            message: enabled
                ? NSLocalizedString("Half-Width Punctuation On", comment: "")
                : NSLocalizedString("Half-Width Punctuation Off", comment: ""))
        if let currentClient = currentClient {
            keyHandler.clear()
            self.handle(state: InputState.Empty(), client: currentClient)
        }
    }

    @objc func toggleAssociatedPhrasesEnabled(_ sender: Any?) {
        _ = Preferences.toggleAssociatedPhrasesEnabled()
    }

    @objc func toggleBopomofoFontAnnotationSupport(_ sender: Any?) {
        let enabled = Preferences.toggleBopomofoFontAnnotationSupportEnabled()
        NotifierController.notify(
            message: enabled
                ? NSLocalizedString("Bopomofo Font Annotation Support On", comment: "")
                : NSLocalizedString("Bopomofo Font Annotation Support Off", comment: ""))
    }

    @objc func togglePhraseReplacement(_ sender: Any?) {
        let enabled = Preferences.togglePhraseReplacementEnabled()
        LanguageModelManager.phraseReplacementEnabled = enabled
    }

    @objc func checkForUpdate(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.checkForUpdate(forced: true)
    }

    @objc func openUserPhrases(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openUserPhrases(sender)
    }

    @objc func openUserPhrasesPlainBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openUserPhrasesPlainBopomofo(sender)
    }

    @objc func openExcludedPhrasesPlainBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openExcludedPhrasesPlainBopomofo(sender)
    }

    @objc func openExcludedPhrasesMcBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openExcludedPhrasesMcBopomofo(sender)
    }

    @objc func openPhraseReplacementMcBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openPhraseReplacementMcBopomofo(sender)
    }

    @objc func reloadUserPhrases(_ sender: Any?) {
        LanguageModelManager.loadUserPhrases(
            enableForPlainBopomofo: Preferences.enableUserPhrasesInPlainBopomofo)
        LanguageModelManager.loadUserPhraseReplacement()

        // Empty the issues so that if there are still the same issues, a
        // notification will be shown.
        McBopomofoInputMethodController.latestUserFileIssues = []
        checkUserFileIssues()
    }

    @objc func showUserFileIssues(_ sender: Any?) {
        let header = NSLocalizedString(
            "Issues were found in the following user phrase files:", comment: "")
        let report =
            header + "\n\n"
            + McBopomofoInputMethodController.latestUserFileIssues.joined(separator: "\n")
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss.SSS"
        let dateString = formatter.string(from: now)
        let fileName = "UserFileIssues-\(dateString).txt"
        let fileURL = tempDir.appendingPathComponent(fileName)
        do {
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(fileURL)
        } catch {
            NSLog("Failed to write report to temporary file: \(error)")
            return
        }
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

}

// MARK: - State Handling

extension McBopomofoInputMethodController {

    func handle(state newState: InputState, client: Any?) {
        if (newState as? InputState.ShiftASCII)?.session.canLowercaseInitialLetter != true {
            cancelInitialLetterHold()
        }
        hideInputModeIndicator()
        textAssistant.cancel()
        let previous = state
        state = newState
        if let symbols = previous as? InputState.QuickSymbols, symbols.held,
           fHoldGesture.phase == .held,
           !(newState is InputState.QuickSymbols) && !(newState is InputState.Committing) {
            cancelFHold(client: client)
        }

        switch newState {
        case let pending as InputState.PendingF:
            (client as? IMKTextInput)?.setMarkedText(
                pending.markedText,
                selectionRange: NSRange(location: pending.markedCursor, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        case let assistance as InputState.Assistance:
            gCurrentCandidateController?.visible = false
            hideTooltip()
            (client as? IMKTextInput)?.setMarkedText(assistance.original.attributedString,
                selectionRange: NSRange(location: Int(assistance.original.cursorIndex), length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            show(candidateWindowWith: assistance, client: client)
            gCurrentCandidateController?.selectedCandidateIndex = UInt(assistance.selectedIndex)
        case let newState as InputState.Deactivated:
            handle(state: newState, previous: previous, client: client)
            state = .Empty()
        case let newState as InputState.SwitchingInputSource:
            handle(state: newState, previous: previous, client: client)
            state = .Empty()
            if !InputSourceHelper.selectInputSource(withID: newState.sourceID) {
                NSLog("Unable to switch to input source: %@", newState.sourceID)
            }
        case let newState as InputState.Empty:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.EmptyIgnoringPreviousState:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Committing:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Inputting:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Marking:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.ChoosingCandidate:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.AssociatedPhrases:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.AssociatedPhrasesPlain:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.SelectingFeature:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.QuickSymbols:
            if newState.held {
                gCurrentCandidateController?.visible = false
                hideTooltip()
                // A held layer maps physical keys without presenting a selection UI.
                (client as? IMKTextInput)?.setMarkedText(InputState.fHoldMarkedText(original: newState.markedComposition),
                    selectionRange: NSRange(location: Int(newState.markedComposition?.cursorIndex ?? 0), length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            } else {
                handleStateWithSimpleCandidateWindow(state: newState, previous: previous, client: client)
            }
        case let newState as InputState.SelectingDateMacro:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Number:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.IcuTransform:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Big5:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.SelectingDictionary:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.ShowingCharInfo:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.CustomMenu:
            handle(state: newState, previous: previous, client: client)
        default:
            break
        }
        textAssistant.schedule(state: state, controller: self)
    }

    private func commit(text: String, client: Any!, observationState: InputState? = nil) {

        func convertToSimplifiedChineseIfRequired(_ text: String) -> String {
            if !Preferences.chineseConversionEnabled {
                return text
            }
            if Preferences.chineseConversionStyle == .model {
                return text
            }
            return OpenCCBridge.shared.convertToSimplified(text) ?? ""
        }

        let buffer = convertToSimplifiedChineseIfRequired(text)
        if buffer.isEmpty {
            return
        }
        guard let receiver = client as? IMKTextInput else { return }
        receiver.insertText(buffer, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        if buffer == text, let observationState, Thread.isMainThread {
            MainActor.assumeIsolated { observeCommitted(text, previous: observationState) }
        }
    }

    private func handle(state: InputState.Deactivated, previous: InputState, client: Any?) {
        currentClient = nil

        gCurrentCandidateController?.delegate = nil
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        switch previous {
        case let previous as InputState.NotEmpty:
            commit(text: previous.composingBuffer, client: client, observationState: previous)
        case is InputState.Big5,
            is InputState.Number,
            is InputState.IcuTransform:
            client.setMarkedText(
                "", selectionRange: NSMakeRange(0, 0), replacementRange: NSMakeRange(0, 0))
        default:
            break
        }

        // Unlike the Empty state handler, we don't call client.setMarkedText() here:
        // there's no point calling setMarkedText() with an empty string as the session
        // is being deactivated anyway, and we have found issues with how certains app
        // could not handle setMarkedText() at this point (see GitHub issue #346).
    }

    private func handle(state: InputState.Empty, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client, observationState: previous)
        }
        client.setMarkedText(
            "", selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handle(
        state: InputState.EmptyIgnoringPreviousState, previous: InputState, client: Any!
    ) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        client.setMarkedText(
            "", selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handle(state: InputState.Committing, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        let poppedText = state.poppedText
        if !poppedText.isEmpty {
            commit(text: poppedText, client: client, observationState: (state as? LearningCommittingState)?.origin ?? previous)
        }
        client.setMarkedText(
            "", selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handle(state: InputState.Inputting, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        client.setMarkedText(
            state.attributedString, selectionRange: NSMakeRange(Int(state.cursorIndex), 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        if !state.tooltip.isEmpty {
            show(
                tooltip: state.tooltip, composingBuffer: state.composingBuffer,
                cursorIndex: state.cursorIndex, client: client)
        }
        if let ascii = state as? InputState.ASCII, ascii.candidateCount > 1 {
            show(candidateWindowWith: ascii, client: client)
            gCurrentCandidateController?.selectedCandidateIndex = UInt(ascii.composition.selectedIndex)
        }
    }

    private func handle(state: InputState.Marking, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        guard let client = client as? IMKTextInput else {
            hideTooltip()
            return
        }

        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        client.setMarkedText(
            state.attributedString, selectionRange: NSMakeRange(Int(state.cursorIndex), 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))

        if state.tooltip.isEmpty {
            hideTooltip()
        } else {
            show(
                tooltip: state.tooltip, composingBuffer: state.composingBuffer,
                cursorIndex: state.markerIndex, client: client)
        }
    }

    private func handle(state: InputState.ChoosingCandidate, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }

        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        client.setMarkedText(
            state.attributedString, selectionRange: NSMakeRange(Int(state.cursorIndex), 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.AssociatedPhrases, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }

        let previousState = state.previousState
        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        switch previousState {
        case let previousState as InputState.ChoosingCandidate:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        case let previousState as InputState.Inputting:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        default:
            break
        }
        show(candidateWindowWith: state, client: client)
    }

    private func handle(
        state: InputState.AssociatedPhrasesPlain, previous: InputState, client: Any?
    ) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        client.setMarkedText(
            "", selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.SelectingFeature, previous: InputState, client: Any?) {
        handleStateWithSimpleCandidateWindow(state: state, previous: previous, client: client)
    }

    private func handle(state: InputState.SelectingDateMacro, previous: InputState, client: Any?) {
        handleStateWithSimpleCandidateWindow(state: state, previous: previous, client: client)
    }

    private func handleSpecialInputWithCandidateWindow(state: InputState, composingBuffer: String, candidateCount: Int, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        client.setMarkedText(
            composingBuffer,
            selectionRange: NSMakeRange(
                (composingBuffer as NSString).length,
                0
            ),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound)
        )
        if candidateCount > 0 {
            show(candidateWindowWith: state, client: client)
        }
    }


    private func handle(state: InputState.Number, previous: InputState, client: Any?) {
        handleSpecialInputWithCandidateWindow(state: state, composingBuffer: state.composingBuffer, candidateCount: state.candidateCount, client: client)
    }

    private func handle(state: InputState.IcuTransform, previous: InputState, client: Any?) {
        handleSpecialInputWithCandidateWindow(state: state, composingBuffer: state.composingBuffer, candidateCount: state.candidateCount, client: client)
    }

    private func handle(state: InputState.Big5, previous: InputState, client: Any?) {
        handleStateForCustomInput(
            composingBuffer: state.composingBuffer, previous: previous, client: client)
    }

    private func handle(state: InputState.SelectingDictionary, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        let previousState = state.previousState
        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer

        switch previousState {
        case let previousState as InputState.ChoosingCandidate:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        case let previousState as InputState.Marking:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        default:
            break
        }
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.ShowingCharInfo, previous: InputState, client: Any?) {

        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        let previousState = state.previousState.previousState
        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        switch previousState {
        case let previousState as InputState.ChoosingCandidate:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        case let previousState as InputState.Marking:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        default:
            break
        }
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.CustomMenu, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        show(candidateWindowWith: state, client: client)
    }
}

// MARK: -

extension McBopomofoInputMethodController {
    private func handleStateForCustomInput(
        composingBuffer: String, previous: InputState, client: Any?
    ) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client, observationState: previous)
        }
        client.setMarkedText(
            composingBuffer, selectionRange: NSMakeRange(composingBuffer.utf16.count, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handleStateWithSimpleCandidateWindow(
        state: InputState, previous: InputState, client: Any?
    ) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client, observationState: previous)
        }
        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        client.setMarkedText(
            "", selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        show(candidateWindowWith: state, client: client)
    }

    private func show(candidateWindowWith state: InputState, client: Any!) {
        let useVerticalMode: Bool = {
            var useVerticalMode = false
            var candidates: [InputState.Candidate] = []
            switch state {
            case let state as InputState.ChoosingCandidate:
                useVerticalMode = state.useVerticalMode
                candidates = state.candidates
            case let state as InputState.AssociatedPhrasesPlain:
                useVerticalMode = state.useVerticalMode
                candidates = state.candidates
            case let state as InputState.AssociatedPhrases:
                useVerticalMode = state.useVerticalMode
                candidates = state.candidates
            case is InputState.SelectingFeature,
                is InputState.Assistance,
                is InputState.QuickSymbols,
                is InputState.SelectingDateMacro,
                is InputState.SelectingDictionary,
                is InputState.ShowingCharInfo,
                is InputState.Number,
                is InputState.IcuTransform:
                return true
            default:
                break
            }

            if useVerticalMode == true {
                return true
            }
            candidates.sort {
                return $0.displayText.count > $1.displayText.count
            }
            // If there is a candidate which is too long, we use the vertical
            // candidate list window automatically.
            if candidates.first?.displayText.count ?? 0 > 8 {
                return true
            }
            return false
        }()

        gCurrentCandidateController?.delegate = nil
        gCurrentCandidateController?.visible = false

        if useVerticalMode {
            gCurrentCandidateController = .vertical
        } else if Preferences.useHorizontalCandidateList {
            gCurrentCandidateController = .horizontal
        } else {
            gCurrentCandidateController = .vertical
        }

        gCurrentCandidateController?.tooltip =
            switch state {
            case let assistance as InputState.Assistance:
                assistance.message
            case let ascii as InputState.ASCII where ascii.prediction != nil:
                NSLocalizedString("Tab accepts prediction; Esc dismisses", comment: "")
            case let symbols as InputState.QuickSymbols:
                NSLocalizedString(symbols.held ? "Release F to return; Esc cancels" : "Press a mapped key; Esc returns", comment: "")
            case let state as InputState.SelectingDictionary:
                String(format: NSLocalizedString("Look up %@", comment: ""), state.selectedPhrase)
            case let state as InputState.AssociatedPhrases:
                String(format: NSLocalizedString("%@…", comment: ""), state.prefixValue)
            case let state as InputState.CustomMenu:
                state.title
            default:
                ""
            }

        // set the attributes for the candidate panel (which uses NSAttributedString)
        let textSize = Preferences.candidateListTextSize
        let keyLabelSize = max(textSize / 2, kMinKeyLabelSize)

        func font(name: String?, size: CGFloat) -> NSFont {
            if let name = name {
                return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
            }
            return NSFont.systemFont(ofSize: size)
        }

        gCurrentCandidateController?.keyLabelFont = font(
            name: Preferences.candidateKeyLabelFontName, size: keyLabelSize)
        gCurrentCandidateController?.candidateFont = font(
            name: Preferences.candidateTextFontName, size: textSize)

        let candidateKeys = Preferences.candidateKeys
        let keyLabels =
            candidateKeys.count >= 4
            ? Array(candidateKeys) : Array(Preferences.defaultCandidateKeys)

        let keyLabelFormat: (String)->String = switch state {
        case let state as InputState.AssociatedPhrases where state.autoTriggered:
            { _ in "⇧ ⏎" }
        case is InputState.AssociatedPhrasesPlain,
            is InputState.Number,
            is InputState.IcuTransform:
            { "⇧ " + $0 }
        default:
            { $0 }
        }
        gCurrentCandidateController?.keyLabels = keyLabels.map {
            CandidateKeyLabel(key: String($0), displayedText: keyLabelFormat(String($0)))
        }
        if state is InputState.ASCII || state is InputState.QuickSymbols || state is InputState.AutomaticAssistance {
            // Digits remain literal; selection uses Tab/arrows or a pointer.
            gCurrentCandidateController?.keyLabels = keyLabels.map { _ in
                CandidateKeyLabel(key: "", displayedText: "")
            }
        }

        gCurrentCandidateController?.delegate = self
        gCurrentCandidateController?.reloadData()
        currentClient = client

        var lineHeightRect = NSMakeRect(0.0, 0.0, 16.0, 16.0)
        var cursor: Int = 0

        if let automatic = state as? InputState.AutomaticAssistance {
            cursor = Int(automatic.original.cursorIndex)
            if cursor == automatic.original.composingBuffer.utf16.count && cursor > 0 { cursor -= 1 }
        } else if let state = state as? InputState.NotEmpty {
            cursor = Int(state.cursorIndex)
            if cursor == state.composingBuffer.count && cursor != 0 {
                cursor -= 1
            }
        }

        while lineHeightRect.origin.x == 0 && lineHeightRect.origin.y == 0 && cursor >= 0 {
            (client as? IMKTextInput)?.attributes(
                forCharacterIndex: cursor, lineHeightRectangle: &lineHeightRect)
            cursor -= 1
        }

        if useVerticalMode {
            gCurrentCandidateController?.set(
                windowTopLeftPoint: NSMakePoint(
                    lineHeightRect.origin.x + lineHeightRect.size.width + 4.0,
                    lineHeightRect.origin.y - 4.0),
                bottomOutOfScreenAdjustmentHeight: lineHeightRect.size.height + 4.0)
        } else {
            gCurrentCandidateController?.set(
                windowTopLeftPoint: NSMakePoint(
                    lineHeightRect.origin.x, lineHeightRect.origin.y - 4.0),
                bottomOutOfScreenAdjustmentHeight: lineHeightRect.size.height + 4.0)
        }

        gCurrentCandidateController?.visible = true
    }

    private func show(tooltip: String, composingBuffer: String, cursorIndex: UInt, client: Any!) {
        var lineHeightRect = NSMakeRect(0.0, 0.0, 16.0, 16.0)
        var cursor: Int = Int(cursorIndex)
        if cursor == composingBuffer.count && cursor != 0 {
            cursor -= 1
        }

        var isVerticalMode = false
        while lineHeightRect.origin.x == 0 && lineHeightRect.origin.y == 0 && cursor >= 0 {
            let attributes: [AnyHashable: Any]? = (client as? IMKTextInput)?.attributes(
                forCharacterIndex: cursor, lineHeightRectangle: &lineHeightRect)
            let useVerticalMode =
                (attributes?["IMKTextOrientation"] as? NSNumber)?.intValue == 0 || false
            isVerticalMode = isVerticalMode || useVerticalMode
            cursor -= 1
        }

        // Make sure that tooltip hovers next to the vertical text.
        if isVerticalMode && lineHeightRect.size.height > 0 {
            lineHeightRect.origin.x += (lineHeightRect.size.width + 1.0)
        }

        McBopomofoInputMethodController.tooltipController.show(
            tooltip: tooltip, at: lineHeightRect.origin)
    }

    private func hideTooltip() {
        McBopomofoInputMethodController.tooltipController.hide()
    }

    private func showInputModeIndicator(client: Any?) {
        hideInputModeIndicator()
        guard !IsSecureEventInputEnabled(), let client = client as? IMKTextInput else { return }
        var rect = NSRect.zero
        let attributes = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        // Some clients cannot report a caret. Do not display at an unrelated screen corner.
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width > 0 || rect.height > 0 else { return }
        let vertical = (attributes?["IMKTextOrientation"] as? NSNumber)?.intValue == 0
        let point = NSPoint(x: rect.origin.x + (vertical ? rect.width + 4 : 0),
                            y: rect.origin.y - 4)
        let indicator = modeIndicator ?? TooltipController()
        modeIndicator = indicator
        indicator.show(tooltip: directEnglish
            ? NSLocalizedString("Input Mode: English", comment: "Brief caret indicator after switching input mode")
            : NSLocalizedString("Input Mode: Bopomofo", comment: "Brief caret indicator after switching input mode"),
            at: point)
        let timer = Timer(timeInterval: 0.8, repeats: false) { [weak self] _ in
            // This timer is installed only on the main run loop.
            MainActor.assumeIsolated { self?.hideInputModeIndicator() }
        }
        modeIndicatorTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func hideInputModeIndicator() {
        modeIndicatorTimer?.invalidate()
        modeIndicatorTimer = nil
        modeIndicator?.hide()
    }

    private func checkUserFileIssues() {
        let issues: [String] = keyHandler.collectUserFileIssues()

        // McBopomofoLM caps the maximum number of issues collected, and so
        // we'll just do this O(n) comparison since n is small.
        if McBopomofoInputMethodController.latestUserFileIssues != issues {
            McBopomofoInputMethodController.latestUserFileIssues = issues

            if !McBopomofoInputMethodController.latestUserFileIssues.isEmpty {
                NotifierController.notify(
                    message: NSLocalizedString(
                        "Check McBopomofo menu for user file issues", comment: ""), stay: true)
            }
        }
    }
}

// Only alive during an IMK-originated F gesture. The system delivers key-up codes;
// the callback immediately discards every code except F and never reads text.
// Passive listening neither modifies nor suppresses events from other apps.
private final class FReleaseMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var onRelease: ((TimeInterval) -> Void)?
    var isEnabled: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start(onRelease: @escaping (TimeInterval) -> Void) -> Bool {
        stop()
        guard CGPreflightListenEventAccess(), !IsSecureEventInputEnabled() else { return false }
        self.onRelease = onRelease
        let mask = CGEventMask(1) << CGEventType.keyUp.rawValue
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<FReleaseMonitor>.fromOpaque(info).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    monitor.onRelease?(ProcessInfo.processInfo.systemUptime)
                } else if type == .keyUp,
                          event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_F) {
                    monitor.onRelease?(Double(event.timestamp) / 1_000_000_000)
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            self.onRelease = nil
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap); self.onRelease = nil; return false
        }
        self.tap = tap; self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return isEnabled
    }

    func stop() {
        onRelease = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil
    }
    deinit { stop() }
}

/// 明確持有原指令與接收者，避免 IMK 子選單無法傳遞 selector。
private final class InputToolButton: NSButton {
    private let command: NSMenuItem
    private weak var receiver: AnyObject?
    init(command: NSMenuItem, receiver: AnyObject) {
        self.command = command; self.receiver = receiver
        super.init(frame: .zero)
        title = (command.state == .on ? "✓ " : "") + command.title
        bezelStyle = .rounded
        isEnabled = command.isEnabled
        target = self; action = #selector(invokeCommand)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invokeCommand() {
        guard let action = command.action else { return }
        window?.close()
        NSApp.sendAction(action, to: command.target ?? receiver, from: command)
    }
}
