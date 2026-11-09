// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

/// 只追蹤目前英文組字的首字母；不依賴系統的按鍵 repeat 延遲。
public struct InitialLetterHoldGesture: Sendable {
    public static let defaultDelayMilliseconds = 250
    public static func clampedDelayMilliseconds(_ value: Int) -> Int { min(1000, max(100, value)) }
    public private(set) var keyCode: UInt16?
    private var deadline: TimeInterval = 0
    public init() {}
    public mutating func begin(keyCode: UInt16, at time: TimeInterval, delayMilliseconds: Int) {
        self.keyCode = keyCode
        deadline = time + Double(Self.clampedDelayMilliseconds(delayMilliseconds)) / 1000
    }
    public mutating func cancel() { keyCode = nil }
    public func remaining(at time: TimeInterval) -> TimeInterval {
        max(0.001, deadline - time)
    }
    /// keyIsDown 由當次事件或目前字母的實體狀態提供；遺漏 key-up 時保留大寫。
    public mutating func advance(to time: TimeInterval, keyIsDown: Bool) -> Bool {
        guard keyCode != nil else { return false }
        guard keyIsDown else { cancel(); return false }
        guard time >= deadline else { return false }
        cancel(); return true
    }
    /// Quartz 狀態表與 IMK 事件來源可能不同。單次查不到按住只能略過 Timer，
    /// 不可把它當成可靠 key-up，否則後來的實際 repeat 也無法補判。
    public mutating func probe(to time: TimeInterval, sessionKeyDown: Bool, hardwareKeyDown: Bool) -> Bool {
        guard sessionKeyDown || hardwareKeyDown else { return false }
        return advance(to: time, keyIsDown: true)
    }
    /// Timer 被主執行緒延後時，仍可依 key-up 的事件時間正確決定本次長按。
    public mutating func release(at time: TimeInterval) -> Bool {
        let reached = advance(to: time, keyIsDown: true)
        cancel(); return reached
    }
}

/// 只保留當次手勢的輸入接收者；以代次取消舊回呼，不比對 IMK 代理物件位址。
/// Target 可以是 UI 接收者，因此不宣告跨執行緒 Sendable。
public struct InitialLetterHoldContext<Target> {
    public private(set) var token: UUID?
    private var receiver: Target?
    public init() {}
    @discardableResult public mutating func begin(receiver: Target) -> UUID {
        let token = UUID(); self.token = token; self.receiver = receiver
        return token
    }
    public func resolve(_ token: UUID) -> Target? { self.token == token ? receiver : nil }
    public mutating func cancel() { token = nil; receiver = nil }
}
