// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

@objc public protocol ModelServiceProtocol {
    func perform(_ kind: String, payload: Data, reply: @escaping (Data?, String?) -> Void)
    func cancel()
}
public struct ModelCorrectionPayload: Codable, Sendable {
    public let text: String
    public let mode: AssistanceMode
    public let english: Bool
    public init(text: String, mode: AssistanceMode, english: Bool) { self.text = text; self.mode = mode; self.english = english }
}
public struct AppleTextAssistance: CorrectionProvider {
    public init() {}
    public func suggest(_ request: CorrectionRequest) async throws -> [String] {
        guard request.isValid else { throw AssistanceError.invalidRequest }
        let payload = try JSONEncoder().encode(ModelCorrectionPayload(text: request.text, mode: request.mode, english: request.isEnglish))
        let bytes = try await ModelServiceClient.shared.correct(payload)
        return request.validated(try JSONDecoder().decode([String].self, from: bytes))
    }
}

/// 所有控制器共用單一服務連線。逾時不建立第二個模型程序；背景整理不搶占手動工作。
@MainActor public final class ModelServiceClient {
    public static let shared = ModelServiceClient()
    private var connection: NSXPCConnection?
    private var connectionGeneration: UUID?
    private var pending: (id: UUID, background: Bool, continuation: CheckedContinuation<Data, any Error>)?
    private var timer: Task<Void, Never>?
    private var lease = ModelRequestLease()
    private var cooldownUntil = Date.distantPast
    private init() {}
    public func correct(_ payload: Data) async throws -> Data {
        if pending?.background == true { cancelBackground(); throw AssistanceError.unavailable }
        return try await request("correction", payload: payload, background: false)
    }
    public func organize(_ payload: Data) async throws -> Data { try await request("organize", payload: payload, background: true) }
    public func cancelBackground() { if pending?.background == true { cancelRequest() } }
    private func cancelRequest() {
        guard let request = pending else { return }
        pending = nil; timer?.cancel(); timer = nil; lease.cancel()
        (connection?.remoteObjectProxy as? ModelServiceProtocol)?.cancel()
        request.continuation.resume(throwing: CancellationError())
        // 服務內 watchdog 負責終止失去回應的自身程序。此處不假設 cancel 已結束推論。
    }
    private func request(_ kind: String, payload: Data, background: Bool) async throws -> Data {
        guard #available(macOS 26.0, *), payload.count <= 65536,
              pending == nil, lease.canStart, Date() >= cooldownUntil else { throw AssistanceError.unavailable }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let conn = connection ?? makeConnection()
                pending = (id, background, continuation)
                _ = lease.begin(id)
                let connectionID = connectionGeneration
                let proxy = conn.remoteObjectProxyWithErrorHandler { @Sendable [weak self] _ in
                    Task { @MainActor in if self?.connectionGeneration == connectionID { self?.disconnected() } }
                } as? ModelServiceProtocol
                guard let proxy else { disconnected(); return }
                proxy.perform(kind, payload: payload) { @Sendable [weak self] data, error in
                    Task { @MainActor in self?.finish(id, data: data, error: error) }
                }
                timer = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(background ? 20 : 5))
                    guard !Task.isCancelled, self?.pending?.id == id else { return }
                    self?.cancelRequest()
                }
            }
        } onCancel: { Task { @MainActor [weak self] in if self?.pending?.id == id { self?.cancelRequest() } } }
    }
    private func makeConnection() -> NSXPCConnection {
        let generation = UUID(); connectionGeneration = generation
        let conn = NSXPCConnection(serviceName: "org.aibopomofo.inputmethod.AIBopomofo.ModelService")
        conn.remoteObjectInterface = NSXPCInterface(with: ModelServiceProtocol.self)
        conn.interruptionHandler = { @Sendable [weak self] in Task { @MainActor in if self?.connectionGeneration == generation { self?.disconnected() } } }
        conn.invalidationHandler = { @Sendable [weak self] in Task { @MainActor in if self?.connectionGeneration == generation { self?.disconnected() } } }
        conn.resume(); connection = conn; return conn
    }
    private func finish(_ id: UUID, data: Data?, error: String?) {
        guard lease.finish(id) else { return }
        guard let request = pending, request.id == id else { return }
        pending = nil; timer?.cancel(); timer = nil
        if let data, data.count <= 65536, error == nil { request.continuation.resume(returning: data) }
        else { cooldownUntil = Date().addingTimeInterval(60); request.continuation.resume(throwing: AssistanceError.unavailable) }
    }
    private func disconnected() {
        let request = pending; pending = nil; timer?.cancel(); timer = nil
        lease.disconnect(); cooldownUntil = Date().addingTimeInterval(60)
        connectionGeneration = nil
        connection?.interruptionHandler = nil; connection?.invalidationHandler = nil
        connection?.invalidate(); connection = nil
        request?.continuation.resume(throwing: AssistanceError.unavailable)
    }
}
