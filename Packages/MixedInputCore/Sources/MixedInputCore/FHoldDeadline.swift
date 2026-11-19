// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation

/// 主執行緒的一次性截止工作；不依賴下一個按鍵或持續輪詢。
/// action 與 schedule/cancel 均由主執行緒使用。取消及新手勢會使舊回呼失效。
public final class FHoldDeadline {
    private var work: DispatchWorkItem?
    private var generation = UUID()
    public init() {}
    public func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        cancel()
        let token = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.work = nil
            action()
        }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: item)
    }
    public func cancel() { generation = UUID(); work?.cancel(); work = nil }
    deinit { work?.cancel() }
}
