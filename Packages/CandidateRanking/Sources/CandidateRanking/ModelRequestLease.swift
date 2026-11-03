// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

/// 取消 UI 等待不等於推論已停止；必須收到同一請求的結束或連線中斷才釋放名額。
public struct ModelRequestLease: Sendable {
    public enum State: Sendable, Equatable { case idle, running(UUID), cancelling(UUID) }
    public private(set) var state: State = .idle
    public init() {}
    public var canStart: Bool { state == .idle }
    public mutating func begin(_ id: UUID) -> Bool {
        guard canStart else { return false }; state = .running(id); return true
    }
    public mutating func cancel() {
        if case .running(let id) = state { state = .cancelling(id) }
    }
    public mutating func finish(_ id: UUID) -> Bool {
        guard state == .running(id) || state == .cancelling(id) else { return false }
        state = .idle; return true
    }
    public mutating func disconnect() { state = .idle }
}
