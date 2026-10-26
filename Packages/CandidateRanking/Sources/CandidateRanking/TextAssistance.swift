// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

public enum AssistanceMode: String, Codable, Sendable { case correction, prediction }
public struct CorrectionRequest: Sendable {
    public let revision: UInt64
    public let text: String
    public let mode: AssistanceMode
    public let isEnglish: Bool
    public let protectedWords: [String]
    public init(revision: UInt64, text: String, mode: AssistanceMode = .correction,
                isEnglish: Bool = false, protectedWords: [String] = []) {
        self.revision = revision; self.text = text; self.mode = mode
        self.isEnglish = isEnglish; self.protectedWords = protectedWords
    }
    public var isValid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && text.count <= 256 && text.utf8.count <= 1024
        && !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        // The existing dictionary supports 5000 custom entries plus built-in terms.
        && protectedWords.count <= 8192
        && (mode != .prediction || (isEnglish && TextProtection.canPredict(text, words: protectedWords)))
    }
    public func validated(_ suggestions: [String]) -> [String] {
        guard isValid else { return [] }
        let signature = TextProtection.signature(text, words: protectedWords)
        var accepted: [String] = []
        for value in suggestions.prefix(16) {
            guard value != text, !value.isEmpty, value.count <= 256, value.utf8.count <= 1024,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  !accepted.contains(value) else { continue }
            if mode == .prediction {
                guard value.hasPrefix(text) else { continue }
                let suffix = String(value.dropFirst(text.count))
                guard !suffix.isEmpty, suffix.count <= 32,
                      suffix.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || $0 == 32 }),
                      suffix.contains(where: { !$0.isWhitespace }),
                      suffix.split(separator: " ").count <= 4 else { continue }
            } else {
                guard TextProtection.signature(value, words: protectedWords) == signature,
                      value.filter(\.isWhitespace) == text.filter(\.isWhitespace) else { continue }
            }
            if isEnglish && !value.unicodeScalars.allSatisfy({ (32...126).contains($0.value) || $0.value == 176 }) { continue }
            accepted.append(value)
            if accepted.count == (mode == .prediction ? 1 : 3) { break }
        }
        return accepted
    }
}

public enum TextProtection {
    // Code (including an unclosed backtick), URLs, paths, identifiers, acronyms, mixed case and numbers.
    private static let patterns = [
        #"`[^`]*(?:`|$)"#, #"https?://[^\s]+|www\.[^\s]+|[\w.+-]+@[\w.-]+"#,
        #"(?:[A-Za-z0-9_.~:-]+[/\\])+[A-Za-z0-9_.~:/\\-]*"#,
        #"\b[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+\b|--?[A-Za-z][A-Za-z0-9-]*"#,
        #"\b[A-Za-z0-9]*_[A-Za-z0-9_]+\b"#, #"\b[A-Za-z]*[0-9][A-Za-z0-9]*\b"#,
        #"\b[A-Za-z]*[a-z][A-Z][A-Za-z]*\b|\b[A-Z]{2,}[A-Za-z]*\b"#,
        #"[0-9]+(?:\.[0-9]+)*"#, #"[^\p{L}\s]"#
    ]
    public static func ranges(_ text: String, words: [String]) -> [NSRange] {
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        var ranges = patterns.flatMap { pattern in
            (try? NSRegularExpression(pattern: pattern).matches(in: text, range: full).map(\.range)) ?? []
        }
        let source = text as NSString
        for word in words where !word.isEmpty {
            var remaining = full
            while remaining.length > 0 {
                let found = source.range(of: word, options: .caseInsensitive, range: remaining)
                if found.location == NSNotFound { break }
                // Do not protect an ordinary word merely because a custom term is a substring.
                let before = found.location == 0 ? nil : UnicodeScalar(source.character(at: found.location - 1))
                let after = NSMaxRange(found) == source.length ? nil : UnicodeScalar(source.character(at: NSMaxRange(found)))
                let letters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
                if !(before.map(letters.contains) ?? false) && !(after.map(letters.contains) ?? false) { ranges.append(found) }
                remaining = NSRange(location: NSMaxRange(found), length: source.length - NSMaxRange(found))
            }
        }
        var merged: [NSRange] = []
        for range in ranges.sorted(by: { $0.location == $1.location ? $0.length > $1.length : $0.location < $1.location }) {
            if let last = merged.last, range.location < NSMaxRange(last) {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else { merged.append(range) }
        }
        return merged
    }
    public static func signature(_ text: String, words: [String]) -> [String] {
        ranges(text, words: words).map { (text as NSString).substring(with: $0) }
    }
    public static func canPredict(_ text: String, words: [String]) -> Bool {
        guard text.count >= 3, text.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || $0 == 32 }),
              signature(text, words: words).isEmpty else { return false }
        return true
    }
}

public protocol CorrectionProvider: Sendable {
    func suggest(_ request: CorrectionRequest) async throws -> [String]
}
public enum AssistanceError: Error { case unavailable, invalidRequest }
public enum AssistanceStatus: Sendable, Equatable { case ready, unavailable, timedOut, busy }
public struct AssistanceResult: Sendable {
    public let suggestions: [String]
    public let status: AssistanceStatus
}

/// One shared instance in the app bounds actual model execution across all input controllers.
@MainActor
public final class AssistanceCoordinator {
    private let provider: any CorrectionProvider
    private let timeout: Duration
    private var pending: (id: UUID, owner: UUID)?
    private var task: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    public private(set) var isRunning = false
    public init(provider: any CorrectionProvider, timeout: Duration = .seconds(5)) {
        self.provider = provider; self.timeout = timeout
    }
    public func invalidate(owner: UUID) {
        guard pending?.owner == owner else { return }
        pending = nil; timer?.cancel(); timer = nil; task?.cancel()
    }
    public func submit(owner: UUID, request: CorrectionRequest, fallback: [String] = [],
                       isCurrent: @escaping @MainActor @Sendable () -> Bool,
                       completion: @escaping @MainActor @Sendable (AssistanceResult) -> Void) {
        invalidate(owner: owner)
        guard request.isValid else {
            if isCurrent() { completion(.init(suggestions: [], status: .unavailable)) }; return
        }
        let fallback = request.validated(fallback)
        guard !isRunning else {
            if isCurrent() { completion(.init(suggestions: fallback, status: .busy)) }; return
        }
        let id = UUID(), clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: timeout)
        pending = (id, owner); isRunning = true
        let provider = provider
        task = Task.detached(priority: .utility) { [weak self] in
            let values = try? await provider.suggest(request)
            await self?.finish(id: id, request: request, values: values, fallback: fallback,
                               deadline: deadline, isCurrent: isCurrent, completion: completion)
        }
        timer = Task { [weak self] in
            do { try await clock.sleep(until: deadline) } catch { return }
            guard let self, self.pending?.id == id else { return }
            self.invalidate(owner: owner)
            if isCurrent() { completion(.init(suggestions: fallback, status: .timedOut)) }
        }
    }
    private func finish(id: UUID, request: CorrectionRequest, values: [String]?, fallback: [String],
                        deadline: ContinuousClock.Instant, isCurrent: @MainActor () -> Bool,
                        completion: @MainActor (AssistanceResult) -> Void) {
        isRunning = false; task = nil
        guard pending?.id == id else { return }
        pending = nil; timer?.cancel(); timer = nil
        guard isCurrent() else { return }
        guard ContinuousClock.now < deadline else {
            completion(.init(suggestions: fallback, status: .timedOut)); return
        }
        completion(.init(suggestions: request.validated((values ?? []) + fallback),
                         status: values == nil ? .unavailable : .ready))
    }
    deinit { task?.cancel(); timer?.cancel() }
}
