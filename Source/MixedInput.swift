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
import UniformTypeIdentifiers

extension InputState {
    @objc(InputStateASCII)
    class ASCII: Inputting, CandidateProvider {
        let composition: ASCIIComposition

        @objc init(text: String, cursor: UInt) {
            composition = ASCIIComposition(raw: text, cursor: Int(cursor), lexicon: MixedInputHandler.lexicon)
            super.init(composingBuffer: composition.display, cursorIndex: UInt(composition.displayCursor))
            tooltip = NSLocalizedString("ASCII: Tab selects, Enter commits, Esc restores or cancels", comment: "")
        }

        init(composition: ASCIIComposition) {
            self.composition = composition
            super.init(composingBuffer: composition.display, cursorIndex: UInt(composition.displayCursor))
            tooltip = NSLocalizedString("ASCII: Tab selects, Enter commits, Esc restores or cancels", comment: "")
        }

        var candidateCount: Int { composition.candidates.count }
        func candidate(at index: Int) -> String {
            composition.candidates.indices.contains(index) ? composition.candidates[index] : ""
        }
        func reading(at index: Int) -> String? { nil }
        override var description: String { "<InputState.ASCII>" }
    }
}

@objc class MixedInputHandler: NSObject {
    static var lexicon = TechnicalLexicon()

    static func reloadUserTerms() {
        let path = LanguageModelManager.userPhrasesDataPathMcBopomofo
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber,
              size.intValue <= 4 * 1024 * 1024,
              let phrases = try? String(contentsOfFile: path, encoding: .utf8) else {
            lexicon = TechnicalLexicon()
            return
        }
        lexicon = TechnicalLexicon(custom: TechnicalLexicon.userTerms(from: phrases))
    }

    @objc static func handle(
        input: KeyHandlerInput, state: InputState.ASCII,
        stateCallback: (InputState) -> Void, errorCallback: () -> Void
    ) -> Bool {
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

        switch state.composition.applying(action, lexicon: lexicon) {
        case .updated(let composition): stateCallback(InputState.ASCII(composition: composition))
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
