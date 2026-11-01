// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.

/// Shift 英文的明確狀態：首字母暫存、英文單字、連續大寫。
/// 不依賴計時；第二個新的 Shift 字母才確認使用者要連續輸入大寫。
public struct ShiftLetterSession: Sendable {
    public enum Mode: Sendable { case initial, word, uppercase }
    public let composition: ASCIIComposition
    public let mode: Mode

    public init(composition: ASCIIComposition, mode: Mode = .initial) {
        self.composition = composition
        self.mode = mode
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
        case .initial: return .updated(Self(composition: composition, mode: .word))
        case .word: return .updated(self)
        case .uppercase: return .commit(composition.display)
        }
    }

    public func applying(_ action: ASCIIComposition.Action, shiftHeld: Bool,
                         repeating: Bool = false, lexicon: TechnicalLexicon = TechnicalLexicon()) -> Result {
        if case .escape = action { return .cancel }
        if case .shortcut = action { return .passThrough(composition.display) }
        if case .enter = action { return .commit(composition.display) }

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
            return .updated(Self(composition: edited, mode: nextMode))
        case .commit(let text): return .commit(text)
        case .passThrough(let text): return .passThrough(text)
        case .cancel: return .cancel
        case .rejected: return .rejected
        }
    }
}
