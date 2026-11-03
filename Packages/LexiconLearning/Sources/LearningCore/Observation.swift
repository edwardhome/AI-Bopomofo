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
