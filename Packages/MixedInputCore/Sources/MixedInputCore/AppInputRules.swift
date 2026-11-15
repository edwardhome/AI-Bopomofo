// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

public enum AppInputMode: String, Codable, CaseIterable, Sendable {
    case english, bopomofo
}

public struct AppInputRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String { bundleIdentifier }
    public let bundleIdentifier: String
    public var displayName: String
    public var mode: AppInputMode
    public init(bundleIdentifier: String, displayName: String, mode: AppInputMode) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.mode = mode
    }
}

/// 偏好設定使用版本化 JSON；不支援或損毀的資料一律回退為空規則。
public struct AppInputRuleSettings: Codable, Equatable, Sendable {
    public let version: Int
    public private(set) var rules: [AppInputRule]
    public init(rules: [AppInputRule] = []) {
        version = 1
        var seen = Set<String>()
        self.rules = rules.filter {
            !$0.bundleIdentifier.isEmpty && $0.bundleIdentifier.utf8.count <= 255
                && !$0.bundleIdentifier.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) })
                && !$0.displayName.isEmpty && $0.displayName.count <= 256
                && seen.insert($0.bundleIdentifier).inserted
        }.prefix(256).map { $0 }
    }
    public static func decode(_ string: String) -> Self {
        guard string.utf8.count <= 1_048_576, let data = string.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Self.self, from: data), decoded.version == 1 else { return Self() }
        return Self(rules: decoded.rules)
    }
    public func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    public mutating func upsert(_ rule: AppInputRule, replacingExisting: Bool = true) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            if replacingExisting { rules[index] = rule }
        } else { rules.append(rule) }
        self = Self(rules: rules)
    }
    public mutating func remove(bundleIdentifier: String) {
        rules.removeAll { $0.bundleIdentifier == bundleIdentifier }
    }
}

/// 每次進入前景 App 建立一份規則快照。不同欄位共享手動選擇，不共享組字。
public struct AppInputModeSession: Sendable {
    public struct Application: Equatable, Sendable {
        public let bundleIdentifier: String
        public let processIdentifier: Int32
        public init(bundleIdentifier: String, processIdentifier: Int32) {
            self.bundleIdentifier = bundleIdentifier
            self.processIdentifier = processIdentifier
        }
    }
    public private(set) var application: Application?
    public private(set) var generation: UInt64 = 0
    public private(set) var mode: AppInputMode?
    public init() {}

    @discardableResult
    public mutating func enter(_ app: Application?, enabled: Bool, settings: AppInputRuleSettings) -> Bool {
        guard app != application else { return false }
        application = app
        generation &+= 1
        mode = enabled ? settings.rules.first(where: { $0.id == app?.bundleIdentifier })?.mode : nil
        return true
    }
    public mutating func selectManually(_ selected: AppInputMode, clientBundleIdentifier: String?, generation: UInt64) {
        guard self.generation == generation, mode != nil,
              let clientBundleIdentifier, application?.bundleIdentifier == clientBundleIdentifier else { return }
        mode = selected
    }
    /// 回傳目標而非切換命令：重複 activate／setValue 可冪等套用到新的連線。
    public func target(clientBundleIdentifier: String?, generation: UInt64, inputActive: Bool,
                       secureInput: Bool, safeToSwitch: Bool) -> AppInputMode? {
        guard self.generation == generation, inputActive, !secureInput, safeToSwitch,
              let clientBundleIdentifier, application?.bundleIdentifier == clientBundleIdentifier else { return nil }
        return mode
    }
}
