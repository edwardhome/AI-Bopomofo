// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import MixedInputCore

let lexicon = TechnicalLexicon(custom: (0..<5000).map { "ProjectTerm\($0)" })
var samples: [Double] = []
var state = ASCIIComposition()
for index in 0..<20000 {
    if index % 40 == 0 { state = ASCIIComposition() }
    let start = ContinuousClock.now
    if case .updated(let next) = state.applying(.insert(index % 2 == 0 ? "p" : "y"), lexicon: lexicon) { state = next }
    let duration = start.duration(to: .now).components
    samples.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
}
samples.sort()
@MainActor func percentile(_ p: Double) -> Double { samples[Int(Double(samples.count - 1) * p)] }
let result: [String: Any] = ["samples": samples.count, "custom_terms": 5000, "scope": "pure composition only; excludes IMK, UI, Chinese engine and cold start", "p50_ms": percentile(0.5), "p95_ms": percentile(0.95), "p99_ms": percentile(0.99)]
print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
