// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import FoundationModels
import CandidateRanking

struct Example: Codable {
    let id: String; let category: String; let text: String; let expected: [String]
    let isEnglish: Bool; let protectedWords: [String]
}
struct Row: Codable {
    let id: String; let category: String; let source: String; let expected: [String]
    let suggestions: [String]; let baseline: [String]; let raw: [String]
    let status: String; let milliseconds: Double; let baselineMilliseconds: Double; let totalRequestMilliseconds: Double
}
actor RecordingProvider: CorrectionProvider {
    private var raw: [String] = []
    func suggest(_ request: CorrectionRequest) async throws -> [String] {
        raw = []
        let result = try await AppleTextAssistance().suggest(request)
        raw = result
        return result
    }
    func latest() -> [String] { raw }
    func reset() { raw = [] }
}
struct Report: Codable {
    let model: String; let availability: String; let completed: Bool
    let notes: String; let rows: [Row]
}
let arguments = CommandLine.arguments
if arguments.count != 3 { fatalError("Usage: Probe corpus.json output.json") }
let examples = try JSONDecoder().decode([Example].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
let model = SystemLanguageModel.default
let provider = RecordingProvider()
struct NoModel: CorrectionProvider {
    func suggest(_ request: CorrectionRequest) async throws -> [String] { throw AssistanceError.unavailable }
}
let systemOnly = ProcessInfo.processInfo.environment["AI_BOPOMOFO_PROBE_SYSTEM_ONLY"] == "1"
let coordinator = AssistanceCoordinator(provider: systemOnly ? NoModel() : provider)
var rows: [Row] = []
var completed = true
for (index, example) in examples.enumerated() {
    let mode: AssistanceMode = example.category == "prediction" ? .prediction : .correction
    let request = CorrectionRequest(revision: UInt64(index), text: example.text, mode: mode,
        isEnglish: example.isEnglish, protectedWords: example.protectedWords)
    let totalStart = ContinuousClock.now
    let baseline = await SystemSpelling.suggestions(for: request)
    let baselineTime = totalStart.duration(to: .now).components
    let baselineMilliseconds = Double(baselineTime.seconds) * 1000 + Double(baselineTime.attoseconds) / 1e15
    await provider.reset()
    let start = ContinuousClock.now
    let result: AssistanceResult = await withCheckedContinuation { continuation in
        coordinator.submit(owner: UUID(), request: request, fallback: baseline, isCurrent: { true }) {
            continuation.resume(returning: $0)
        }
    }
    let duration = start.duration(to: .now).components
    let raw = await provider.latest()
    rows.append(.init(id: example.id, category: example.category, source: example.text,
        expected: example.expected, suggestions: result.suggestions, baseline: baseline, raw: raw,
        status: String(describing: result.status),
        milliseconds: Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15,
        baselineMilliseconds: baselineMilliseconds,
        totalRequestMilliseconds: baselineMilliseconds + Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15))
    // Never pile new inference on top of a timed-out uncooperative task.
    let drainDeadline = ContinuousClock.now.advanced(by: .seconds(5))
    while coordinator.isRunning && ContinuousClock.now < drainDeadline { try await Task.sleep(for: .milliseconds(20)) }
    if coordinator.isRunning { completed = false; break }
    if (index + 1) % 25 == 0 { FileHandle.standardError.write(Data("Evaluated \(index + 1)/\(examples.count)\n".utf8)) }
}
let report = Report(model: systemOnly ? "NSSpellChecker only" : "SystemLanguageModel.default (on-device)", availability: String(describing: model.availability),
    completed: completed, notes: "Synthetic individually authored corpus, not independently human-reviewed. milliseconds measures provider time; totalRequestMilliseconds includes asynchronous system-spelling baseline. Excludes typing debounce, IMK, and candidate rendering. No typing or GUI tests.", rows: rows)
let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(report).write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
print("Saved \(rows.count) rows; completed=\(completed)")
