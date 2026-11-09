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
    /// Timer 被主執行緒延後時，仍可依 key-up 的事件時間正確決定本次長按。
    public mutating func release(at time: TimeInterval) -> Bool {
        let reached = advance(to: time, keyIsDown: true)
        cancel(); return reached
    }
}
