// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import AppKit

public struct SpellingReplacement: Sendable {
    public let range: NSRange
    public let text: String
    public init(range: NSRange, text: String) { self.range = range; self.text = text }
}

/// Background system spelling is a baseline/fallback, not an Apple Foundation Models result.
@MainActor
public enum SystemSpelling {
    private static var isRunning = false
    @MainActor private final class Completion {
        var continuation: CheckedContinuation<[String], Never>?
        var timer: Task<Void, Never>?
        init(_ continuation: CheckedContinuation<[String], Never>) { self.continuation = continuation }
        func finish(_ result: [String]) {
            guard let continuation else { return }
            self.continuation = nil; timer?.cancel(); timer = nil
            continuation.resume(returning: result)
        }
    }
    public nonisolated static func apply(_ replacements: [SpellingReplacement], to request: CorrectionRequest) -> [String] {
        guard request.isValid else { return [] }
        let protected = TextProtection.ranges(request.text, words: request.protectedWords)
        let boundaries = Set(request.text.indices).union([request.text.endIndex])
        let values = replacements.prefix(16).compactMap { replacement -> String? in
            guard let range = Range(replacement.range, in: request.text),
                  boundaries.contains(range.lowerBound), boundaries.contains(range.upperBound),
                  !protected.contains(where: { NSIntersectionRange($0, replacement.range).length > 0 }) else { return nil }
            // Candidate generation can append an automatic space outside the selected word.
            // Correction preserves the original document spacing; prediction may append spaces.
            let text = request.mode == .correction
                ? replacement.text.trimmingCharacters(in: .whitespacesAndNewlines) : replacement.text
            return request.text.replacingCharacters(in: range, with: text)
        }
        return request.validated(values)
    }
    public static func suggestions(for request: CorrectionRequest) async -> [String] {
        guard request.isValid, request.isEnglish, !isRunning else { return [] }
        isRunning = true
        let checker = NSSpellChecker.shared, tag = NSSpellChecker.uniqueSpellDocumentTag()
        return await withCheckedContinuation { continuation in
            let completion = Completion(continuation)
            completion.timer = Task {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                completion.finish([])
                // Keep the single spelling slot until its actual callback; never accumulate requests.
            }
            let received: @Sendable ([NSTextCheckingResult]) -> Void = { results in
                let replacements = results.compactMap { item -> SpellingReplacement? in
                    guard let text = item.replacementString else { return nil }
                    return SpellingReplacement(range: item.range, text: text)
                }
                Task { @MainActor in
                    NSSpellChecker.shared.closeSpellDocument(withTag: tag)
                    isRunning = false
                    completion.finish(apply(replacements, to: request))
                }
            }
            let full = NSRange(request.text.startIndex..<request.text.endIndex, in: request.text)
            var options: [NSSpellChecker.OptionKey: Any] = [
                .orthography: NSOrthography.defaultOrthography(forLanguage: "en_US")
            ]
            if request.mode == .prediction {
                if #available(macOS 14.0, *) { options[.generateInlinePredictionsKey] = true }
                checker.requestCandidates(forSelectedRange: NSRange(location: full.length, length: 0),
                    in: request.text, types: NSTextCheckingResult.CheckingType.correction.rawValue,
                    options: options, inSpellDocumentWithTag: tag) { @Sendable _, results in received(results) }
            } else {
                checker.requestChecking(of: request.text, range: full,
                    types: NSTextCheckingResult.CheckingType.spelling.rawValue,
                    options: options, inSpellDocumentWithTag: tag) { @Sendable _, results, _, _ in
                        let ranges = results.filter { $0.resultType == .spelling }.map(\.range)
                        Task { @MainActor in
                            let protected = TextProtection.ranges(request.text, words: request.protectedWords)
                            guard completion.continuation != nil,
                                  let word = ranges.first(where: { range in
                                      !protected.contains { NSIntersectionRange($0, range).length > 0 }
                                  }) else {
                                NSSpellChecker.shared.closeSpellDocument(withTag: tag)
                                isRunning = false
                                completion.finish([])
                                return
                            }
                            NSSpellChecker.shared.requestCandidates(forSelectedRange: word,
                                in: request.text, types: NSTextCheckingResult.CheckingType.correction.rawValue,
                                options: [.orthography: NSOrthography.defaultOrthography(forLanguage: "en_US")],
                                inSpellDocumentWithTag: tag) { @Sendable _, candidates in received(candidates) }
                        }
                    }
            }
        }
    }
}
