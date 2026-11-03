// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

public enum ObservationKind: String, Codable, Sendable { case autoCommitted = "auto_committed", manualSelected = "manual_selected", explicitRemember = "explicit_remember" }
public struct Observation: Sendable {
    public let id: UUID
    public let entry: LexiconEntry
    public let kind: ObservationKind
    public let at: Date
    public init(entry: LexiconEntry, kind: ObservationKind, id: UUID = UUID(), at: Date = Date()) {
        self.id = id; self.entry = entry; self.kind = kind; self.at = at
    }
}
public struct TermSpan: Sendable {
    public let reading: String, text: String
    public let location: Int
    public let manual: Bool
    public init(reading: String, text: String, location: Int, manual: Bool) {
        self.reading = reading; self.text = text; self.location = location; self.manual = manual
    }
}
public enum CommitProjection {
    /// 只投影已送出前綴內的完整詞；不猜測剩餘音節，不跨提交事件串接。
    public static func terms(committed: String, composition: String, spans: [TermSpan]) -> [TermSpan] {
        guard !committed.isEmpty, !composition.isEmpty, composition.hasPrefix(committed) else { return [] }
        return spans.prefix(64).filter { term in
            guard term.location >= 0, term.text.utf16.count <= 128,
                  term.location <= committed.utf16.count,
                  term.text.utf16.count <= committed.utf16.count - term.location else { return false }
            let range = NSRange(location: term.location, length: term.text.utf16.count)
            guard let valid = Range(range, in: committed) else { return false }
            return committed[valid] == term.text
        }
    }
}

/// 生產者只使用 try-lock；消費者或管理工作佔用時直接略過，不等待鎖。
public final class ObservationQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var ring: [Observation?]
    private var head = 0, count = 0
    public init(capacity: Int = 512) { ring = Array(repeating: nil, count: max(1, capacity)) }
    @discardableResult public func offer(_ event: Observation) -> Bool {
        guard event.entry.text.utf8.count + event.entry.reading.utf8.count <= 8192, lock.try() else { return false }
        defer { lock.unlock() }
        guard count < ring.count else { return false }
        ring[(head + count) % ring.count] = event; count += 1; return true
    }
    public func drain(limit: Int = 128) -> [Observation] {
        lock.lock(); defer { lock.unlock() }
        var result: [Observation] = []; result.reserveCapacity(min(limit, count))
        while count > 0 && result.count < limit {
            if let item = ring[head] { result.append(item) }; ring[head] = nil
            head = (head + 1) % ring.count; count -= 1
        }
        return result
    }
    public func clear() { while !drain().isEmpty {} }
}

public struct LearningState: Sendable, Equatable {
    public enum Worker: String, Sendable { case disabled, collecting, organizing, unavailable, paused }
    public var observationEnabled = true
    public var organizerEnabled = true
    public var storageAvailable = true
    public var modelAvailable = false
    public var isOrganizing = false
    public init() {}
    public var worker: Worker {
        if !storageAvailable { return .unavailable }
        if isOrganizing { return .organizing }
        return observationEnabled ? .collecting : .disabled
    }
    public func canOrganize(secure: Bool, idle: Bool, hasPending: Bool) -> Bool {
        organizerEnabled && storageAvailable && modelAvailable && !isOrganizing && !secure && idle && hasPending
    }
}
