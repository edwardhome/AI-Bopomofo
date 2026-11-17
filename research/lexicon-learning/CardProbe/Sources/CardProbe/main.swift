// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
// 僅由獨立 CLI 執行合成卡片，不啟動輸入法、不讀使用者詞庫。
import Foundation
import FoundationModels
import CandidateRanking
import LearningCore
import LearningOrganizer

struct Result: Encodable {
    var fixture: String, transport: String, availability: String, status: String
    var elapsed: Double
    var changes: [CardChange]
    var generated: String?
    var rejected: [CardProposalRejection] = []
}
@main struct CardProbe {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 4 else { fatalError("fixture xpc|direct output.json") }
        let fixture = CommandLine.arguments[1], transport = CommandLine.arguments[2]
        var graph = CardGraph()
        let text: String, definition: String, reading: String
        switch fixture {
        case "wavelength": text = "波長"; definition = "波的相鄰兩個波峰之間的距離"; reading = "ㄅㄛ-ㄔㄤˊ"
        case "silica": text = "二氧化矽"; definition = "矽與氧形成的化合物，化學式 SiO2"; reading = "ㄦˋ-ㄧㄤˇ-ㄏㄨㄚˋ-ㄒㄧˋ"
        default: text = "銀行"; definition = "辦理存款及放款的金融機構"; reading = "ㄧㄣˊ-ㄏㄤˊ"
        }
        let concept = LexiconConcept(definition: definition, domain: fixture == "bank" ? "金融" : "自然科學")
        graph.concepts.append(concept)
        try graph.editName(concept: concept.id, text: text, kind: "zh", codes: [], readings: [reading])
        let request = CardOrganizationRequest(revision: "synthetic-probe", graph: graph)
        let start = Date(), model = SystemLanguageModel.default
        var result = Result(fixture: fixture, transport: transport, availability: String(describing: model.availability), status: "", elapsed: 0, changes: [])
        do {
            let bytes: Data
            if transport == "xpc" { bytes = try await ModelServiceClient.shared.organizeCards(request.encoded()) }
            else {
                let input = CardModelInput(request)
                let session = LanguageModelSession(model: model, instructions: CardModelInstructions.text)
                let response = try await session.respond(to: input.prompt(), generating: CardModelSuggestions.self,
                    options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 1024))
                result.generated = String(describing: response.content)
                bytes = try input.validatedResponse(response.content)
            }
            let response = try request.validateServiceResponse(bytes)
            result.changes = response.changes; result.rejected = response.rejected
            result.status = result.changes.isEmpty ? "empty" : "validated"
        } catch { result.status = String(describing: error) }
        result.elapsed = Date().timeIntervalSince(start)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
        print("\(fixture): \(result.status), \(result.changes.count) proposals, \(result.elapsed) seconds")
    }
}
