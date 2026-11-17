// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

/// XPC 只傳固定錯誤碼，不將模型提示、回應或私人詞彙寫進錯誤訊息。
public enum ModelServiceFailure: String, Error, Sendable, CaseIterable {
    case busy, coolingDown, timeout, cancelled, disconnected, invalidRequest, invalidResponse
    case unsupportedDevice, intelligenceDisabled, modelNotReady, unsupportedLanguage
    case contextLimit, refused, rateLimited, generationFailed

    public var messageKey: String {
        switch self {
        case .busy: "FM is busy or finishing cancellation. Please try again shortly."
        case .coolingDown: "FM is recovering from a service failure. Please retry after one minute."
        case .timeout: "FM exceeded the waiting limit. Try fewer cards or retry after the model is ready."
        case .cancelled: "FM organization was cancelled. Approved vocabulary is unchanged."
        case .disconnected: "The FM service disconnected. Please retry after one minute."
        case .invalidRequest: "The selected cards exceed the model input limit or contain invalid data. Try fewer cards."
        case .invalidResponse: "FM returned invalid suggestion fields. Nothing was applied; please retry."
        case .unsupportedDevice: "This Mac or macOS version does not support Foundation Models."
        case .intelligenceDisabled: "Enable Apple Intelligence in System Settings before using FM."
        case .modelNotReady: "The on-device model is not ready. Wait for Apple Intelligence to finish preparing it."
        case .unsupportedLanguage: "The on-device model does not support the requested language."
        case .contextLimit: "The cards exceed the model context limit. Select fewer cards."
        case .refused: "FM declined this request. No suggestion was applied."
        case .rateLimited: "FM is temporarily rate limited. Please retry later."
        case .generationFailed: "FM could not generate suggestions. Please retry; manual editing remains available."
        }
    }
    public static func fromWire(_ code: String) -> Self { Self(rawValue: code) ?? .generationFailed }
    public var requiresCooldown: Bool { self == .disconnected || self == .generationFailed || self == .rateLimited }
}

public enum ModelRequestKind: String, Sendable {
    case correction, organize, organizeCards = "organize_cards"
    public var timeoutSeconds: Int { self == .organizeCards ? 60 : self == .organize ? 20 : 5 }
    public var watchdogSeconds: Int { self == .organizeCards ? 75 : 30 }
    public var isAutomatic: Bool { self == .organize }
}
