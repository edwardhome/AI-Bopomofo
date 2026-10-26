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

    public static func output(for keyCode: UInt16) -> String? {
        entries.first { $0.keyCode == keyCode }?.output
    }
}

/// A local input-method gesture. The adapter owns the timer and original key event.
public struct FHoldGesture {
    public static let delay: Double = 0.2
    public enum Phase: Equatable { case idle, pending, held }
    public enum Event { case press(eligible: Bool, repeating: Bool), release, otherKey, timeout, cancel }
    public enum Effect: Equatable { case schedule, invalidate, replayTap, beginLayer, endLayer, consume }
    public private(set) var phase: Phase = .idle
    public init() {}

    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .press(let eligible, let repeating):
            if phase != .idle { return [.consume] }
            guard eligible && !repeating else { return [] }
            phase = .pending
            return [.schedule, .consume]
        case .release:
            let previous = phase
            phase = .idle
            switch previous {
            case .pending: return [.invalidate, .replayTap, .consume]
            case .held: return [.endLayer, .consume]
            case .idle: return []
            }
        case .otherKey:
            guard phase == .pending else { return [] }
            phase = .idle
            return [.invalidate, .replayTap]
        case .timeout:
            guard phase == .pending else { return [] }
            phase = .held
            return [.beginLayer]
        case .cancel:
            let previous = phase
            phase = .idle
            return previous == .held ? [.invalidate, .endLayer] : [.invalidate]
        }
    }
}
