// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Cocoa
import Carbon
import LearningCore
import LexiconDeployment

/// 在背景建好的不可變 Foundation 索引；跨執行緒傳遞後不再修改。
@objc(ApprovedLearningIndex)
final class ApprovedLearningIndex: NSObject, @unchecked Sendable {
    @objc let entries: NSDictionary
    init(_ entries: [String: [String]] = [:]) { self.entries = entries as NSDictionary }
}

/// 只描述目前組字中可可靠對應的單一詞；不是逐鍵或整句歷史。
@objc(LearningTermSnapshot)
final class LearningTermSnapshot: NSObject {
    @objc let reading: String
    @objc let text: String
    @objc let location: Int
    @objc let manual: Bool
    @objc init(reading: String, text: String, location: Int, manual: Bool) {
        self.reading = reading; self.text = text; self.location = location; self.manual = manual
    }
}
@objc(LearningInputtingState)
final class LearningInputtingState: InputState.Inputting {
    let terms: [LearningTermSnapshot]
    @objc init(composingBuffer: String, cursorIndex: UInt, terms: [LearningTermSnapshot]) {
        self.terms = terms; super.init(composingBuffer: composingBuffer, cursorIndex: cursorIndex)
    }
    override var learningTerms: [LearningTermSnapshot] { terms }
}
@objc(LearningChoosingState)
final class LearningChoosingState: InputState.ChoosingCandidate {
    let terms: [LearningTermSnapshot]
    @objc init(inputting: InputState.Inputting, candidates: [InputState.Candidate], useVerticalMode: Bool) {
        terms = inputting.learningTerms
        super.init(composingBuffer: inputting.composingBuffer, cursorIndex: inputting.cursorIndex,
                   candidates: candidates, useVerticalMode: useVerticalMode)
    }
    override var learningTerms: [LearningTermSnapshot] { terms }
}

@objc(ApprovedLearningCandidate)
final class ApprovedLearningCandidate: InputState.Candidate {
    @objc let start: UInt
    @objc let length: UInt
    @objc init(reading: String, value: String, start: UInt, length: UInt) {
        self.start = start; self.length = length
        super.init(reading: reading, value: value, displayText: value, rawValue: value)
    }
}

@MainActor extension McBopomofoInputMethodController {
    /// 已核准版本只在新組字邊界取得；在途組字與 F 狀態保留原本的快照。
    func refreshLearningSnapshotIfIdle() {
        guard state is InputState.Empty || state is InputState.EmptyIgnoringPreviousState else { return }
        let runtime = LearningRuntime.shared
        let desired = Preferences.approvedLexiconEnabled ? runtime.snapshot.version : ""
        let token = "\(Preferences.approvedLexiconEnabled):\(desired)"
        guard learningAppliedToken != token else { return }
        learningAppliedToken = token
        learningSnapshot = Preferences.approvedLexiconEnabled ? runtime.snapshot : LexiconSnapshot()
        keyHandler.setApprovedLearningIndex(Preferences.approvedLexiconEnabled ? runtime.chineseIndex : nil)
        MixedInputHandler.setApprovedTerms(Preferences.approvedLexiconEnabled ? runtime.engineeringTerms : nil)
    }

    func observeCommitted(_ text: String, previous: InputState, manuallySelectedASCII: Bool = false) {
        guard Preferences.lexiconObservationEnabled, !IsSecureEventInputEnabled(),
              !Preferences.chineseConversionEnabled, !Preferences.phraseReplacementEnabled else { return }
        if let ascii = previous as? InputState.ASCII {
            let raw = ascii.composition.raw
            let output = text.hasSuffix(" ") ? String(text.dropLast()) : text
            guard output == ascii.composition.display,
                  !raw.contains(where: \.isWhitespace), raw.utf8.count <= 64 else { return }
            // 任意原始 ASCII 文字不自動收錄；只觀察來自已知詞庫的候選。
            let selected = ascii.composition.selectedIndex
            let known = ascii.composition.candidateItems.indices.contains(selected)
                && ascii.composition.candidateItems[selected].source != .original
            guard known else { return }
            let entry = LexiconEntry(type: .technical, reading: raw, text: output)
            LearningRuntime.shared.offer(entry, kind: manuallySelectedASCII || selected > 0 ? .manualSelected : .autoCommitted)
            return
        }
        let buffer = (previous as? InputState.NotEmpty)?.composingBuffer ?? ""
        let spans = previous.learningTerms.prefix(64).map {
            TermSpan(reading: $0.reading, text: $0.text, location: $0.location, manual: $0.manual)
        }
        for term in CommitProjection.terms(committed: text, composition: buffer, spans: spans) {
            LearningRuntime.shared.offer(LexiconEntry(type: .zhPhrase, reading: term.reading, text: term.text),
                                         kind: term.manual ? .manualSelected : .autoCommitted)
        }
    }
}

final class LearningCommittingState: InputState.Committing {
    let origin: InputState
    init(text: String, origin: InputState) { self.origin = origin; super.init(poppedText: text) }
}
