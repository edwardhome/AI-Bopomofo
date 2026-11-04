// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

/// 自動建議只附在完整組字旁；既有候選、游標編輯及不完整音節優先。
public enum AutomaticAssistancePolicy {
    public static func mode(text: String, english: Bool, cursorAtEnd: Bool,
                            hasCandidates: Bool = false, suppressed: Bool = false) -> AssistanceMode? {
        guard cursorAtEnd, !suppressed else { return nil }
        if english {
            guard !hasCandidates, TechnicalNotation.isInput(text) else { return nil }
            return .technical
        }
        return TextProtection.hanCount(text) >= 2 ? .correction : nil
    }
}

/// 同一份組字不反覆提示；暫停或失敗也不在背景自動重試相同內容。
public struct AutomaticAssistanceGate {
    private var attempted: String?
    private var lastStarted = -Double.infinity
    public init() {}
    public func delay(now: Double) -> Double { max(0.7, 2 - (now - lastStarted)) }
    public mutating func resetComposition() { attempted = nil }
    public mutating func begin(key: String, now: Double) -> Bool {
        guard attempted != key, now - lastStarted >= 2 else { return false }
        attempted = key; lastStarted = now; return true
    }
}

public enum AutomaticSuggestionKey { case tab, backTab, enter, escape, ordinary }
public enum AutomaticSuggestionAction: Equatable {
    case select(Int), accept(Int), dismiss, replayOriginal
}
public enum AutomaticSuggestionInteraction {
    public static func action(key: AutomaticSuggestionKey, selected: Int, count: Int,
                              shortcut: Bool = false) -> AutomaticSuggestionAction {
        guard !shortcut, count > 1 else { return .replayOriginal }
        switch key {
        case .tab: return .select((selected + 1) % count)
        case .backTab: return .select((selected + count - 1) % count)
        case .enter: return selected > 0 ? .accept(selected) : .replayOriginal
        case .escape: return .dismiss
        case .ordinary: return .replayOriginal
        }
    }
}

/// 模型可提議拼字及排版；不能把公式的數值、元素或電荷改成另一個式子。
public enum TechnicalNotation {
    private static let greek: [String: String] = [
        "alpha":"α", "beta":"β", "gamma":"γ", "delta":"δ", "epsilon":"ε",
        "zeta":"ζ", "eta":"η", "theta":"θ", "iota":"ι", "kappa":"κ",
        "lambda":"λ", "mu":"μ", "nu":"ν", "xi":"ξ", "omicron":"ο",
        "pi":"π", "rho":"ρ", "sigma":"σ", "tau":"τ", "upsilon":"υ",
        "phi":"φ", "chi":"χ", "psi":"ψ", "omega":"ω"
    ]
    public static func isInput(_ text: String) -> Bool {
        (3...64).contains(text.utf8.count)
            && text.range(of: "^[A-Za-z][A-Za-z0-9()+^=\\-]*$", options: .regularExpression) != nil
    }
    public static func accepts(_ value: String, for text: String) -> Bool {
        guard isInput(text), !value.isEmpty, value.utf16.count <= 128,
              value.unicodeScalars.allSatisfy({
                  CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
                  || "()+-=⁺⁻₊₋⁽⁾₍₎¹²³".unicodeScalars.contains($0)
                  || (0x2070...0x209f).contains($0.value)
              }) else { return false }
        if greek[text.lowercased()] == value { return true }
        // NFKC 僅用來比對，實際候選仍保留模型提供的 Unicode。
        return value.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: "−", with: "-").lowercased() == text.lowercased()
    }
}
