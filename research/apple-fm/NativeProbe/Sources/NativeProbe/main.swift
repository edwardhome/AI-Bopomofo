import CandidateRanking
import Foundation
import FoundationModels

struct ProbeRow: Codable {
    let context: String
    let selectedID: Int?
    let expectedID: Int
    let milliseconds: Double
    let error: String?
}
struct ProbeReport: Codable {
    let model: String
    let availability: String
    let supportsTraditionalChineseTaiwan: Bool
    let rows: [ProbeRow]
}

let model = SystemLanguageModel.default
var rows: [ProbeRow] = []
let examples: [(String, [String], Int)] = [
    ("這個 FPGA 需要重新", ["編意", "編譯", "邊翼"], 1),
    ("Flask 的服務已經完成", ["部屬", "部署", "步數"], 1),
    ("自訂變數名稱是", ["qz_module7", "qzModule7", "module"], 0),
]
if model.availability == .available {
    for (index, example) in examples.enumerated() {
        let request = CandidateRankingRequest(
            compositionVersion: UInt64(index), contextBefore: example.0,
            candidates: example.1.enumerated().map { RankingCandidate(id: $0.offset, text: $0.element) }
        )
        let start = ContinuousClock.now
        var selected: Int?
        var failure: String?
        do {
            selected = try await AppleFoundationModelsReranker().rank(request).selectedID
        } catch {
            failure = String(describing: error)
        }
        let duration = start.duration(to: .now).components
        rows.append(.init(context: example.0, selectedID: selected, expectedID: example.2,
                          milliseconds: Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15,
                          error: failure))
    }
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let report = ProbeReport(
    model: "SystemLanguageModel.default (on-device)",
    availability: String(describing: model.availability),
    supportsTraditionalChineseTaiwan: model.supportsLocale(Locale(identifier: "zh-Hant-TW")), rows: rows
)
print(String(decoding: try encoder.encode(report), as: UTF8.self))
