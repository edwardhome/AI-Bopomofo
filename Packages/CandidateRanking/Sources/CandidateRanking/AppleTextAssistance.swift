// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
private struct TextSuggestions {
    @Guide(description: "Up to three complete corrected versions, or one complete English continuation. Return an empty array if no change is needed.")
    var suggestions: [String]
}
#endif

public struct AppleTextAssistance: CorrectionProvider {
    public init() {}
    public func suggest(_ request: CorrectionRequest) async throws -> [String] {
        guard request.isValid else { throw AssistanceError.invalidRequest }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.availability == .available,
                  model.supportsLocale(Locale(identifier: request.isEnglish ? "en-US" : "zh-Hant-TW")) else {
                throw AssistanceError.unavailable
            }
            try Task.checkCancellation()
            // 整段未送出的組字就是上下文；不讀取文件游標前後的已提交文字。
            let session = LanguageModelSession(model: model, instructions: ContextualCorrectionPrompt.instructions)
            struct Payload: Encodable { let mode: AssistanceMode; let text: String }
            let payload = Payload(mode: request.mode, text: request.text)
            let prompt = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
            let response = try await session.respond(to: prompt, generating: TextSuggestions.self,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 384))
            try Task.checkCancellation()
            return response.content.suggestions
        }
        #endif
        throw AssistanceError.unavailable
    }
}
