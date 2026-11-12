// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.

/// Physical ANSI key positions copied from the supplied Kanata number layer.
/// No runtime dependency on Kanata or synthetic keyboard events.
public enum QuickSymbolLayer {
    public struct Entry: Sendable, Equatable {
        public let keyCode: UInt16
        public let label: String
        public let output: String
    }

    public static let entries: [Entry] = [
        .init(keyCode: 16, label: "Y", output: "7"),
        .init(keyCode: 32, label: "U", output: "8"),
        .init(keyCode: 34, label: "I", output: "9"),
        .init(keyCode: 4, label: "H", output: "4"),
        .init(keyCode: 38, label: "J", output: "5"),
        .init(keyCode: 40, label: "K", output: "6"),
        .init(keyCode: 45, label: "N", output: "1"),
        .init(keyCode: 46, label: "M", output: "2"),
        .init(keyCode: 43, label: ",", output: "3"),
        .init(keyCode: 49, label: "Space", output: "0"),
        .init(keyCode: 47, label: ".", output: "."),
        .init(keyCode: 12, label: "Q", output: "/"),
        .init(keyCode: 13, label: "W", output: "*"),
        .init(keyCode: 14, label: "E", output: "-"),
        .init(keyCode: 15, label: "R", output: "+"),
        .init(keyCode: 31, label: "O", output: "{"),
        .init(keyCode: 35, label: "P", output: "}"),
        .init(keyCode: 33, label: "[", output: "["),
        .init(keyCode: 30, label: "]", output: "]"),
        .init(keyCode: 42, label: "\\", output: "\\"),
        .init(keyCode: 50, label: "`", output: "`"),
        .init(keyCode: 53, label: "Esc", output: "`"),
        .init(keyCode: 18, label: "1", output: "!"),
        .init(keyCode: 19, label: "2", output: "@"),
        .init(keyCode: 20, label: "3", output: "#"),
        .init(keyCode: 21, label: "4", output: "$"),
        .init(keyCode: 23, label: "5", output: "%"),
        .init(keyCode: 22, label: "6", output: "^"),
        .init(keyCode: 26, label: "7", output: "&"),
        .init(keyCode: 28, label: "8", output: "~"),
        .init(keyCode: 25, label: "9", output: "("),
        .init(keyCode: 29, label: "0", output: ")"),
        .init(keyCode: 27, label: "-", output: "_"),
        .init(keyCode: 24, label: "=", output: "'"),
        .init(keyCode: 0, label: "A", output: "<"),
        .init(keyCode: 1, label: "S", output: ">"),
        .init(keyCode: 2, label: "D", output: "="),
        .init(keyCode: 5, label: "G", output: ">"),
        .init(keyCode: 37, label: "L", output: ":"),
        .init(keyCode: 41, label: ";", output: ";"),
        .init(keyCode: 39, label: "'", output: "\""),
        .init(keyCode: 6, label: "Z", output: "'"),
        .init(keyCode: 7, label: "X", output: "|"),
        .init(keyCode: 11, label: "B", output: "°"),
        .init(keyCode: 44, label: "/", output: "?"),
    ]

    /// 固定 ANSI 實體位置；F、退格與 Enter 保留為分層／編輯控制鍵。
    public static let keyboardRows: [[Entry]] = [
        [(53, "Esc"), (50, "`"), (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"), (22, "6"), (26, "7"), (28, "8"), (25, "9"), (29, "0"), (27, "-"), (24, "=")],
        [(12, "Q"), (13, "W"), (14, "E"), (15, "R"), (17, "T"), (16, "Y"), (32, "U"), (34, "I"), (31, "O"), (35, "P"), (33, "["), (30, "]"), (42, "\\")],
        [(0, "A"), (1, "S"), (2, "D"), (3, "F"), (5, "G"), (4, "H"), (38, "J"), (40, "K"), (37, "L"), (41, ";"), (39, "'")],
        [(6, "Z"), (7, "X"), (8, "C"), (9, "V"), (11, "B"), (45, "N"), (46, "M"), (43, ","), (47, "."), (44, "/")],
        [(49, "Space")]
    ].map { row in row.map { Entry(keyCode: UInt16($0.0), label: $0.1, output: "") } }

    public static func validOutput(_ text: String) -> Bool {
        text.count <= 16 && !text.unicodeScalars.contains {
            $0.properties.generalCategory == .control || $0.properties.generalCategory == .format
        }
    }

    /// 空字串停用該鍵；無效或未知的設定回退預設，不能改寫控制鍵。
    public static func configuredEntries(overrides: [String: String]) -> [Entry] {
        keyboardRows.flatMap { $0 }.filter { $0.keyCode != 3 }.compactMap { key in
            let custom = overrides[String(key.keyCode)]
            let value = custom.flatMap { validOutput($0) ? $0 : nil } ?? output(for: key.keyCode) ?? ""
            return value.isEmpty ? nil : Entry(keyCode: key.keyCode, label: key.label, output: value)
        }
    }

    public static func output(for keyCode: UInt16, entries: [Entry] = Self.entries) -> String? {
        entries.first { $0.keyCode == keyCode }?.output
    }

    /// Applies editing inside a held layer without committing text to the client.
    public static func edit(keyCode: UInt16, composition: ASCIIComposition, entries: [Entry] = Self.entries) -> ASCIIComposition.Result? {
        if keyCode == 51 { return composition.applying(.backspace) }
        if keyCode == 117 { return composition.applying(.delete) }
        guard let text = output(for: keyCode, entries: entries) else { return nil }
        return composition.insertingSymbol(text)
    }

}

/// A local input-method gesture. The adapter owns the timer and original key event.
public struct FHoldGesture {
    public static let defaultDelayMilliseconds = 150
    public static let delayRangeMilliseconds = 100...1000

    public static func clampedDelayMilliseconds(_ value: Int) -> Int {
        min(max(value, delayRangeMilliseconds.lowerBound), delayRangeMilliseconds.upperBound)
    }

    /// Fixed for one gesture so a preference change cannot shorten an active press.
    public let delay: Double
    public enum Phase: Equatable { case idle, pending, held }
    public enum Event {
        case press(eligible: Bool, repeating: Bool)
        case release
        case observedRelease
        case otherKey
        case timeout
        case cancel
        case elapsed(Double)
    }
    public enum Effect: Equatable { case schedule, invalidate, replayTap, beginLayer, endLayer, consume }
    public private(set) var phase: Phase = .idle
    // The passive tap may finish the gesture before IMK receives the same key-up.
    private var ownsKeyUp = false
    public init(delayMilliseconds: Int = Self.defaultDelayMilliseconds) {
        delay = Double(Self.clampedDelayMilliseconds(delayMilliseconds)) / 1000
    }

    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .press(let eligible, let repeating):
            if phase != .idle || (repeating && ownsKeyUp) { return [.consume] }
            guard eligible && !repeating else { return [] }
            phase = .pending
            ownsKeyUp = true
            return [.schedule, .consume]
        case .observedRelease:
            let owned = ownsKeyUp
            let effects = handle(.release)
            ownsKeyUp = owned
            return effects
        case .release:
            let owned = ownsKeyUp
            ownsKeyUp = false
            let previous = phase
            phase = .idle
            switch previous {
            case .pending: return [.invalidate, .replayTap, .consume]
            case .held: return [.invalidate, .endLayer, .consume]
            case .idle: return owned ? [.consume] : []
            }
        case .otherKey:
            guard phase == .pending else { return [] }
            // 門檻內任何下一鍵都屬正常打字；只能由 elapsed 判斷長按。
            phase = .idle
            return [.invalidate, .replayTap]
        case .elapsed(let seconds):
            guard phase == .pending, seconds > delay else { return [] }
            return handle(.timeout)
        case .timeout:
            guard phase == .pending else { return [] }
            phase = .held
            return [.beginLayer]
        case .cancel:
            ownsKeyUp = false
            let previous = phase
            phase = .idle
            return previous == .held ? [.invalidate, .endLayer] : [.invalidate]
        }
    }
}


/// Only mapped symbol keys belong to the layer after F is released. Editing keys
/// must keep their native repeat behavior, even when IMK omits their key-up.
public struct SymbolKeyOwnership {
    private var keys: Set<UInt16> = []
    public init() {}
    public mutating func reset() { keys.removeAll() }
    public mutating func keyUp(_ code: UInt16) -> Bool { keys.remove(code) != nil }
    public mutating func keyDown(_ code: UInt16, repeating: Bool,
                                 layerActive: Bool, shortcut: Bool, mapped: Bool? = nil) -> Bool {
        if !repeating || shortcut { keys.remove(code) }
        if repeating && keys.contains(code) && !layerActive { return true }
        if layerActive && !shortcut && (mapped ?? (QuickSymbolLayer.output(for: code) != nil)) {
            keys.insert(code)
        }
        return false
    }
}
