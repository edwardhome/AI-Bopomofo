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
    private var pending: (id: UUID, kind: ModelRequestKind, continuation: CheckedContinuation<Data, any Error>)?
    private var timer: Task<Void, Never>?
    private var lease = ModelRequestLease()
    private var cooldownUntil = Date.distantPast
    // 注入傳輸僅用於無介面測試；正式實例仍使用隔離的 XPC 服務。
    typealias TestTransport = (String, Data, @escaping @Sendable (Data?, String?) -> Void) -> Void
    private var testTransport: TestTransport?
    private var testCancel: (() -> Void)?
    private var testTimeout: Duration?
    init(transport: TestTransport? = nil, cancel: (() -> Void)? = nil, timeout: Duration? = nil) {
        testTransport = transport; testCancel = cancel; testTimeout = timeout
    }
    public func correct(_ payload: Data) async throws -> Data {
        if pending?.kind.isAutomatic == true { cancelBackground(); throw ModelServiceFailure.busy }
        return try await request(.correction, payload: payload)
    }
    public func organize(_ payload: Data) async throws -> Data { try await request(.organize, payload: payload) }
    public func organizeCards(_ payload: Data) async throws -> Data { try await request(.organizeCards, payload: payload) }
    public func cancelBackground() { if pending?.kind.isAutomatic == true { cancelRequest() } }
    public func cancelOrganizing() { if let kind = pending?.kind, kind != .correction { cancelRequest() } }
    private func cancelRequest(reason: ModelServiceFailure = .cancelled) {
        guard let request = pending else { return }
        pending = nil; timer?.cancel(); timer = nil; lease.cancel()
        if let testCancel { testCancel() } else { (connection?.remoteObjectProxy as? ModelServiceProtocol)?.cancel() }
        request.continuation.resume(throwing: reason)
        // 服務內 watchdog 負責終止失去回應的自身程序。此處不假設 cancel 已結束推論。
    }
    private func request(_ kind: ModelRequestKind, payload: Data) async throws -> Data {
        guard #available(macOS 26.0, *) else { throw ModelServiceFailure.unsupportedDevice }
        guard payload.count <= 65536 else { throw ModelServiceFailure.invalidRequest }
        guard pending == nil, lease.canStart else { throw ModelServiceFailure.busy }
        guard Date() >= cooldownUntil else { throw ModelServiceFailure.coolingDown }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending = (id, kind, continuation)
                _ = lease.begin(id)
                let callback: @Sendable (Data?, String?) -> Void = { [weak self] data, error in
                    Task { @MainActor in self?.finish(id, data: data, error: error) }
                }
                if let testTransport { testTransport(kind.rawValue, payload, callback) }
                else {
                    let conn = connection ?? makeConnection()
                    let connectionID = connectionGeneration
                    let proxy = conn.remoteObjectProxyWithErrorHandler { @Sendable [weak self] _ in
                        Task { @MainActor in if self?.connectionGeneration == connectionID { self?.disconnected() } }
                    } as? ModelServiceProtocol
                    guard let proxy else { disconnected(); return }
                    proxy.perform(kind.rawValue, payload: payload, reply: callback)
                }
                timer = Task { [weak self] in
                    try? await Task.sleep(for: self?.testTimeout ?? .seconds(kind.timeoutSeconds))
                    guard !Task.isCancelled, self?.pending?.id == id else { return }
                    self?.cancelRequest(reason: .timeout)
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
        else {
            let failure = error.map(ModelServiceFailure.fromWire) ?? .invalidResponse
            if failure.requiresCooldown { cooldownUntil = Date().addingTimeInterval(60) }
            request.continuation.resume(throwing: failure)
        }
    }
    private func disconnected() {
        let request = pending; pending = nil; timer?.cancel(); timer = nil
        lease.disconnect(); cooldownUntil = Date().addingTimeInterval(60)
        connectionGeneration = nil
        connection?.interruptionHandler = nil; connection?.invalidationHandler = nil
        connection?.invalidate(); connection = nil
        request?.continuation.resume(throwing: ModelServiceFailure.disconnected)
    }
}
