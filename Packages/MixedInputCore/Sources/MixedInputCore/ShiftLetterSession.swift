// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.

/// Shift 英文的明確狀態：首字母暫存、英文單字、連續大寫。
/// 首字母的系統重複事件代表長按；第二個新字母仍沿用連續大寫規則。
public struct ShiftLetterSession: Sendable {
    public enum Mode: Sendable { case initial, word, uppercase }
    public let composition: ASCIIComposition
    public let mode: Mode
    /// 只追蹤本次起始字母，任何後續編輯／新按鍵都會解除。
    public let heldInitialLetter: String?

    public init(composition: ASCIIComposition, mode: Mode = .initial,
                heldInitialLetter: String? = nil, trackInitialLetter: Bool = true) {
        self.composition = composition
        self.mode = mode
        let bytes = composition.raw.utf8
        self.heldInitialLetter = heldInitialLetter ?? (trackInitialLetter && mode == .initial
            && bytes.count == 1 && bytes.first.map({ (65...90).contains($0) }) == true
            ? composition.raw : nil)
    }

    public func replacing(composition: ASCIIComposition) -> Self {
        Self(composition: composition, mode: mode,
             heldInitialLetter: composition.raw == self.composition.raw && composition.selectedIndex == 0
                ? heldInitialLetter : nil, trackInitialLetter: false)
    }

    public enum Result: Sendable {
        case updated(ShiftLetterSession)
        case commit(String)
        case commitAndContinue(String, ShiftLetterSession)
        case passThrough(String)
        case forward, cancel, rejected
    }

    public func releasingShift() -> Result {
        switch mode {
        case .initial: return .updated(Self(composition: composition, mode: .word, heldInitialLetter: heldInitialLetter, trackInitialLetter: false))
        case .word: return .updated(self)
        case .uppercase: return .commit(composition.display)
        }
    }

    public func applying(_ action: ASCIIComposition.Action, shiftHeld: Bool,
                         repeating: Bool = false, lexicon: TechnicalLexicon = TechnicalLexicon()) -> Result {
        if case .escape = action { return .cancel }
        if case .shortcut = action { return .passThrough(composition.display) }
        if case .enter = action { return .commit(composition.display) }

        // 按住首字母時，只修改尚未提交的原文一次；後續 repeat 一律消耗，
        // 不接受候選、不改已送出的文字，也不產生一串 ssss。
        if repeating, let heldInitialLetter, case .insert(let text) = action,
           text.lowercased() == heldInitialLetter.lowercased(),
           composition.selectedIndex == 0, composition.raw.count == 1,
           composition.raw.lowercased() == heldInitialLetter.lowercased() {
            return .updated(Self(composition: ASCIIComposition(raw: heldInitialLetter.lowercased(), lexicon: lexicon),
                mode: mode, heldInitialLetter: heldInitialLetter, trackInitialLetter: false))
        }

        // 連續大寫只暫存當次要送出的內容；刪除與方向鍵交回原應用程式。
        if mode == .uppercase {
            if case .insert(let text) = action,
               !text.isEmpty, text.unicodeScalars.allSatisfy({ (32...126).contains($0.value) }) {
                return .commitAndContinue(composition.display + text,
                    Self(composition: ASCIIComposition(), mode: .uppercase))
            }
            return .forward
        }

        if mode == .initial, shiftHeld, !repeating, case .insert(let text) = action,
           text.utf8.count == 1, let byte = text.utf8.first, (65...90).contains(byte) {
            return .commitAndContinue(composition.display + text,
                Self(composition: ASCIIComposition(), mode: .uppercase))
        }

        // 只在 Shift 啟動的單字模式以空白送出；選單開啟的 ASCII 仍可輸入整句。
        if case .insert(" ") = action { return .commit(composition.display + " ") }
        let nextMode: Mode = mode == .initial && shiftHeld ? .initial : .word
        switch composition.applying(action, lexicon: lexicon) {
        case .updated(let edited):
            // 刪到空白仍留在英文，因此可以刪除 M，再輸入小寫 mm。
            return .updated(Self(composition: edited, mode: nextMode, trackInitialLetter: false))
        case .commit(let text): return .commit(text)
        case .passThrough(let text): return .passThrough(text)
        case .cancel: return .cancel
        case .rejected: return .rejected
        }
    }
}
