// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Cocoa

enum InputFeedback {
    static func beep() {
        // Hosted tests must never play sound, independent of persisted preferences.
        guard ProcessInfo.processInfo.environment["AI_BOPOMOFO_SILENT_TESTS"] != "1",
              NSClassFromString("XCTestCase") == nil else { return }
        NSSound.beep()
    }
}

import MixedInputCore
import CandidateRanking
import UniformTypeIdentifiers

extension InputState {
    /// A temporary marked composition, never committed as text. Keeping a nonempty
    /// mark tells clients such as iTerm2 that the deferred key belongs to the IME.
    class PendingF: InputState {
        let original: InputState
        init(original: InputState) { self.original = original; super.init() }
    }

    static func fHoldMarkedText(original: Inputting?) -> NSAttributedString {
        if let original, !original.composingBuffer.isEmpty { return original.attributedString }
        return NSAttributedString(string: "·")
    }

    @objc(InputStateQuickSymbols)
    class QuickSymbols: InputState, CandidateProvider {
        @objc let held: Bool
        @objc let originalASCII: InputState.ASCII?
        let heldBuffer: ASCIIComposition?
        var editingComposition: ASCIIComposition? { originalASCII?.composition ?? heldBuffer }
        var markedComposition: InputState.ASCII? {
            originalASCII ?? heldBuffer.map { InputState.ASCII(composition: $0, predictionSuppressed: true) }
        }
        @objc init(held: Bool) {
            self.held = held; originalASCII = nil
            heldBuffer = held ? ASCIIComposition() : nil
            super.init()
        }
        init(heldBuffer: ASCIIComposition) {
            held = true; originalASCII = nil; self.heldBuffer = heldBuffer; super.init()
        }
        @objc init(held: Bool, originalASCII: InputState.ASCII) {
            self.held = held; self.originalASCII = originalASCII; heldBuffer = nil; super.init()
        }
        var candidateCount: Int { QuickSymbolLayer.entries.count }
        func candidate(at index: Int) -> String {
            guard QuickSymbolLayer.entries.indices.contains(index) else { return "" }
            let entry = QuickSymbolLayer.entries[index]
            return entry.label + " → " + entry.output
        }
        func reading(at index: Int) -> String? { nil }
    }

    @objc(InputStateASCII)
    class ASCII: Inputting, CandidateProvider {
        let composition: ASCIIComposition
        let sessionLexicon: TechnicalLexicon
        let prediction: String?
        let predictionSuppressed: Bool

        @objc init(text: String, cursor: UInt) {
            sessionLexicon = MixedInputHandler.lexicon
            composition = ASCIIComposition(raw: text, cursor: Int(cursor), lexicon: MixedInputHandler.lexicon)
            prediction = nil
            predictionSuppressed = false
            super.init(composingBuffer: composition.display, cursorIndex: UInt(composition.displayCursor))
            tooltip = NSLocalizedString("ASCII: Tab selects, Enter commits, Esc restores or cancels", comment: "")
        }

        init(composition: ASCIIComposition, prediction: String? = nil, predictionSuppressed: Bool = false, sessionLexicon: TechnicalLexicon = MixedInputHandler.lexicon) {
            self.sessionLexicon = sessionLexicon
            self.composition = composition
            self.prediction = prediction
            self.predictionSuppressed = predictionSuppressed
            super.init(composingBuffer: composition.display, cursorIndex: UInt(composition.displayCursor))
            tooltip = NSLocalizedString("ASCII: Tab selects, Enter commits, Esc restores or cancels", comment: "")
            if prediction != nil { tooltip = NSLocalizedString("Prediction: Tab accepts; Esc dismisses; Enter sends only your text", comment: "") }
        }

        /// 所有編輯／預測都經由這裡複製，避免把 Shift 啟動方式遺失。
        func replacing(composition: ASCIIComposition, prediction: String? = nil,
                       predictionSuppressed: Bool = false, sessionLexicon: TechnicalLexicon? = nil) -> ASCII {
            if let shifted = self as? ShiftASCII {
                return ShiftASCII(session: shifted.session.replacing(composition: composition),
                    prediction: prediction, predictionSuppressed: predictionSuppressed, sessionLexicon: sessionLexicon ?? self.sessionLexicon)
            }
            return ASCII(composition: composition, prediction: prediction,
                         predictionSuppressed: predictionSuppressed, sessionLexicon: sessionLexicon ?? self.sessionLexicon)
        }

        var candidateCount: Int { prediction == nil ? composition.candidates.count : 2 }
        func candidate(at index: Int) -> String {
            if let prediction { return index == 1 ? prediction : composition.raw }
            return composition.candidates.indices.contains(index) ? composition.candidates[index] : ""
        }
        func reading(at index: Int) -> String? {
            guard prediction == nil, composition.candidateItems.indices.contains(index) else { return nil }
            return composition.candidateItems[index].annotation
        }
        override var description: String { "<InputState.ASCII>" }
    }

    /// 與選單啟動的 ASCII 分開，Shift 放開不會影響手動英文或雙 Shift 模式。
    @objc(InputStateShiftASCII)
    class ShiftASCII: ASCII {
        let session: ShiftLetterSession
        var mode: ShiftLetterSession.Mode { session.mode }
        @objc convenience init(shiftText: String, cursor: UInt) {
            self.init(composition: ASCIIComposition(raw: shiftText, cursor: Int(cursor), lexicon: MixedInputHandler.lexicon), mode: .initial)
        }
        init(composition: ASCIIComposition, mode: ShiftLetterSession.Mode,
             prediction: String? = nil, predictionSuppressed: Bool = false, sessionLexicon: TechnicalLexicon = MixedInputHandler.lexicon) {
            session = ShiftLetterSession(composition: composition, mode: mode,
                holdStartedAt: ProcessInfo.processInfo.systemUptime,
                holdDelayMilliseconds: Preferences.initialLetterHoldDelayMilliseconds)
            super.init(composition: composition, prediction: prediction,
                       predictionSuppressed: predictionSuppressed || mode != .word, sessionLexicon: sessionLexicon)
            tooltip = NSLocalizedString("Shift English: Space or Enter commits; Esc cancels", comment: "")
        }
        init(session: ShiftLetterSession, prediction: String? = nil, predictionSuppressed: Bool = false,
             sessionLexicon: TechnicalLexicon = MixedInputHandler.lexicon) {
            self.session = session
            super.init(composition: session.composition, prediction: prediction,
                       predictionSuppressed: predictionSuppressed || session.mode != .word,
                       sessionLexicon: sessionLexicon)
            tooltip = NSLocalizedString("Shift English: Space or Enter commits; Esc cancels", comment: "")
        }
    }

}

@objc class QuickSymbolHandler: NSObject {
    @objc static func end(state: InputState.QuickSymbols, stateCallback: (InputState) -> Void) {
        if let buffer = state.heldBuffer, !buffer.raw.isEmpty {
            stateCallback(InputState.Committing(poppedText: buffer.raw))
        }
        if let original = state.originalASCII as? InputState.ShiftASCII, original.mode == .uppercase {
            // F 放開只送出符號，仍按住 Shift 時繼續保留連續大寫模式。
            if !original.composingBuffer.isEmpty { stateCallback(InputState.Committing(poppedText: original.composingBuffer)) }
            stateCallback(original.replacing(composition: ASCIIComposition()))
        } else {
            stateCallback(state.originalASCII ?? InputState.EmptyIgnoringPreviousState())
        }
    }
    private static func update(_ composition: ASCIIComposition, state: InputState.QuickSymbols,
                               stateCallback: (InputState) -> Void) {
        if let original = state.originalASCII {
            stateCallback(InputState.QuickSymbols(held: state.held,
                originalASCII: original.replacing(composition: composition, predictionSuppressed: true)))
        } else {
            stateCallback(InputState.QuickSymbols(heldBuffer: composition))
        }
    }
    private static func insert(_ text: String, state: InputState.QuickSymbols,
                               stateCallback: (InputState) -> Void) {
        if let original = state.editingComposition {
            if case .updated(let composition) = original.applying(.insert(text), lexicon: state.originalASCII?.sessionLexicon ?? MixedInputHandler.lexicon) {
                update(composition, state: state, stateCallback: stateCallback)
            }
        } else {
            stateCallback(InputState.Committing(poppedText: text))
            stateCallback(InputState.QuickSymbols(held: state.held))
        }
    }

    @objc static func select(index: Int, state: InputState.QuickSymbols,
                             stateCallback: (InputState) -> Void) {
        guard QuickSymbolLayer.entries.indices.contains(index) else { return }
        insert(QuickSymbolLayer.entries[index].output, state: state, stateCallback: stateCallback)
    }
    @objc static func handle(input: KeyHandlerInput, state: InputState.QuickSymbols,
                             stateCallback: (InputState) -> Void) -> Bool {
        if input.isCommandHold || input.isOptionHold || input.isControlHold {
            if let original = state.editingComposition, !original.display.isEmpty {
                stateCallback(InputState.Committing(poppedText: original.display))
            }
            stateCallback(InputState.EmptyIgnoringPreviousState())
            return false
        }
        if (input.charCode == 27 && !state.held) || input.charCode == 13 || input.isEnter {
            end(state: state, stateCallback: stateCallback)
            return true
        }
        let code: UInt16 = input.charCode == 8 ? 51 : UInt16(input.keyCode)
        if let original = state.editingComposition,
           case .updated(let composition) = QuickSymbolLayer.edit(keyCode: code, composition: original) {
            update(composition, state: state, stateCallback: stateCallback)
        } else if let value = QuickSymbolLayer.output(for: code) {
            insert(value, state: state, stateCallback: stateCallback)
        } else if code == 51 || code == 117 {
            end(state: state, stateCallback: stateCallback)
            return false
        }
        return true
    }
}

@objc class MixedInputHandler: NSObject {
    static var lexicon = TechnicalLexicon(engineeringEnabled: Preferences.engineeringLexiconEnabled)
    static private(set) var lexiconRevision: UInt64 = 0

    @objc static func withPrediction(_ text: String, state: InputState.ASCII) -> InputState.ASCII {
        guard !state.composition.hasEngineeringCandidates, state.composition.selectedIndex == 0, !state.predictionSuppressed,
              state.composition.cursor == state.composition.raw.utf16.count else { return state }
        let request = CorrectionRequest(revision: 0, text: state.composition.raw, mode: .prediction,
                                        isEnglish: true, protectedWords: lexicon.words)
        let prediction = request.validated([text]).first
        return state.replacing(composition: state.composition, prediction: prediction)
    }

    @objc static func acceptPrediction(state: InputState.ASCII, stateCallback: (InputState) -> Void) {
        guard let prediction = state.prediction else { return }
        stateCallback(state.replacing(composition: ASCIIComposition(raw: prediction, lexicon: state.sessionLexicon)))
    }

    /// 只轉換 Shift 英文來源。F 等待／分層是外層包裝，不能在放開 Shift 時取消 F。
    private static func afterShiftRelease(_ state: InputState) -> (String?, InputState)? {
        if let shifted = state as? InputState.ShiftASCII {
            guard shifted.mode != .word else { return nil }
            switch shifted.session.releasingShift() {
            case .updated(let next):
                return (nil, InputState.ShiftASCII(session: next, sessionLexicon: shifted.sessionLexicon))
            case .commit(let text): return (text, InputState.EmptyIgnoringPreviousState())
            default: return nil
            }
        }
        if let pending = state as? InputState.PendingF,
           let (text, next) = afterShiftRelease(pending.original) {
            return (text, InputState.PendingF(original: next))
        }
        if let symbols = state as? InputState.QuickSymbols, let original = symbols.originalASCII,
           let (text, next) = afterShiftRelease(original) {
            if let ascii = next as? InputState.ASCII {
                return (text, InputState.QuickSymbols(held: symbols.held, originalASCII: ascii))
            }
            return (text, InputState.QuickSymbols(held: symbols.held))
        }
        if let assistance = state as? InputState.Assistance {
            return afterShiftRelease(assistance.original)
        }
        return nil
    }

    @objc static func releaseShift(state: InputState, stateCallback: (InputState) -> Void) -> Bool {
        guard let (text, next) = afterShiftRelease(state) else { return false }
        if let text, !text.isEmpty { stateCallback(InputState.Committing(poppedText: text)) }
        stateCallback(next)
        return true
    }

    static func reloadingLexicon(state: InputState) -> InputState {
        if let ascii = state as? InputState.ASCII {
            return ascii.replacing(composition: ascii.composition.rebuilding(lexicon: lexicon), predictionSuppressed: true, sessionLexicon: lexicon)
        }
        if let pending = state as? InputState.PendingF {
            return InputState.PendingF(original: reloadingLexicon(state: pending.original))
        }
        if let symbols = state as? InputState.QuickSymbols, let original = symbols.originalASCII,
           let refreshed = reloadingLexicon(state: original) as? InputState.ASCII {
            return InputState.QuickSymbols(held: symbols.held, originalASCII: refreshed)
        }
        if let assistance = state as? InputState.Assistance {
            return reloadingLexicon(state: assistance.original)
        }
        return state
    }

    private static var approvedTerms: EngineeringLexicon?
    static func setApprovedTerms(_ terms: EngineeringLexicon?) {
        approvedTerms = terms; lexicon = lexicon.withApproved(terms); lexiconRevision &+= 1
    }
    static func reloadUserTerms() {
        defer { lexicon = lexicon.withApproved(approvedTerms) }
        lexiconRevision &+= 1
        let path = LanguageModelManager.userPhrasesDataPathMcBopomofo
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber,
              size.intValue <= 4 * 1024 * 1024,
              let phrases = try? String(contentsOfFile: path, encoding: .utf8) else {
            lexicon = TechnicalLexicon(engineeringEnabled: Preferences.engineeringLexiconEnabled)
            return
        }
        lexicon = TechnicalLexicon(custom: TechnicalLexicon.userTerms(from: phrases),
                                   engineeringEnabled: Preferences.engineeringLexiconEnabled)
    }

    @objc static func handle(
        input: KeyHandlerInput, state: InputState.ASCII,
        stateCallback: (InputState) -> Void, errorCallback: () -> Void
    ) -> Bool {
        if !(state is InputState.ShiftASCII && input.charCode == 27), state.prediction != nil && !(input.isCommandHold || input.isOptionHold || input.isControlHold) {
            if input.charCode == 27 {
                stateCallback(state.replacing(composition: state.composition, predictionSuppressed: true))
                return true
            }
            if input.isTab && !input.isShiftHold {
                acceptPrediction(state: state, stateCallback: stateCallback)
                return true
            }
        }
        let action: ASCIIComposition.Action
        if input.charCode == 27 { action = .escape }
        else if input.isCommandHold || input.isOptionHold || input.isControlHold { action = .shortcut }
        else if input.charCode == 13 || input.isEnter { action = .enter }
        else if input.isTab { action = .cycle(input.isShiftHold ? -1 : 1) }
        else if input.isDown { action = .cycle(1) }
        else if input.isUp { action = .cycle(-1) }
        else if input.charCode == 8 { action = .backspace }
        else if input.isDelete { action = .delete }
        else if input.isLeft { action = .left }
        else if input.isRight { action = .right }
        else if input.isHome { action = .home }
        else if input.isEnd { action = .end }
        else { action = .insert(input.inputText ?? "") }

        if let shifted = state as? InputState.ShiftASCII {
            switch shifted.session.applying(action, shiftHeld: input.isShiftHold,
                repeating: input.isARepeat, now: ProcessInfo.processInfo.systemUptime, lexicon: state.sessionLexicon) {
            case .updated(let next):
                stateCallback(InputState.ShiftASCII(session: next,
                    predictionSuppressed: input.isTab || input.isUp || input.isDown || input.isLeft || input.isRight, sessionLexicon: shifted.sessionLexicon))
            case .commitAndContinue(let text, let next):
                stateCallback(InputState.Committing(poppedText: text))
                stateCallback(InputState.ShiftASCII(session: next, sessionLexicon: shifted.sessionLexicon))
            case .commit(let text):
                stateCallback(InputState.Committing(poppedText: text))
                stateCallback(InputState.EmptyIgnoringPreviousState())
            case .passThrough(let text):
                stateCallback(InputState.Committing(poppedText: text))
                stateCallback(InputState.EmptyIgnoringPreviousState())
                return false
            case .forward: return false
            case .cancel: stateCallback(InputState.EmptyIgnoringPreviousState())
            case .rejected: errorCallback()
            }
            return true
        }

        switch state.composition.applying(action, lexicon: state.sessionLexicon) {
        case .updated(let composition):
            let navigated = input.isTab || input.isUp || input.isDown || input.isLeft || input.isRight || input.isHome || input.isEnd
            stateCallback(state.replacing(composition: composition, predictionSuppressed: navigated))
        case .commit(let value):
            stateCallback(InputState.Committing(poppedText: value))
            stateCallback(InputState.Empty())
        case .passThrough(let value):
            stateCallback(InputState.Committing(poppedText: value))
            stateCallback(InputState.Empty())
            return false
        case .cancel: stateCallback(InputState.EmptyIgnoringPreviousState())
        case .rejected: errorCallback()
        }
        return true
    }
}

extension AppDelegate {
    @objc func importTechnicalTerms(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_048_576 else { throw DictionaryError.invalid }
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.split(whereSeparator: \.isNewline).map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
            guard lines.count <= 5000, lines.allSatisfy(TechnicalLexicon.isValid) else {
                throw DictionaryError.invalid
            }
            let phrasePath = LanguageModelManager.userPhrasesDataPathMcBopomofo
            let existing = (try? String(contentsOfFile: phrasePath, encoding: .utf8)) ?? ""
            let existingTerms = Set(TechnicalLexicon.userTerms(from: existing))
            let additions = Set(lines).subtracting(existingTerms)
            guard existingTerms.count + additions.count <= 5000 else { throw DictionaryError.invalid }
            if !additions.isEmpty, FileManager.default.fileExists(atPath: phrasePath) {
                try FileManager.default.copyItem(
                    atPath: phrasePath, toPath: phrasePath + ".backup-" + UUID().uuidString)
            }
            // One storage system: append to the existing user phrase file via its bridge.
            for word in additions.sorted() {
                guard LanguageModelManager.writeUserPhrase(word + " _english_" + word.lowercased()) else {
                    throw DictionaryError.writeFailed
                }
            }
            updateUserPhrases()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func exportTechnicalTerms(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "technical-terms.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let path = LanguageModelManager.userPhrasesDataPathMcBopomofo
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let terms = Set(TechnicalLexicon.userTerms(from: source)).sorted()
            try (terms.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private enum DictionaryError: Error, LocalizedError {
        case invalid, writeFailed
        var errorDescription: String? {
            switch self {
            case .invalid: return NSLocalizedString("Invalid technical dictionary: use one ASCII term per line, up to 5000 terms of 64 characters.", comment: "")
            case .writeFailed: return NSLocalizedString("Unable to write user phrases. Some terms may have been imported; retry safely after checking the file.", comment: "")
            }
        }
    }
}
