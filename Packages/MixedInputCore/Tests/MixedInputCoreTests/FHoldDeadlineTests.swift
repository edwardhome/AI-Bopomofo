// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import Testing
@testable import MixedInputCore

@Suite @MainActor struct FHoldDeadlineTests {
    @Test func heldPreviewExpiresWithoutKeyUpOrAnotherKey() async throws {
        let timer = FHoldDeadline()
        var gesture = FHoldGesture(delayMilliseconds: 100)
        var effects: [FHoldGesture.Effect] = []
        _ = gesture.handle(.press(eligible: true, repeating: false))
        timer.schedule(after: 0.102) { effects = gesture.handle(.elapsed(0.102)) }
        for _ in 0..<100 where effects.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(effects == [.beginLayer]); #expect(gesture.phase == .held)
        #expect(gesture.handle(.release).contains(.replayTap))
    }
    @Test func cancelledDeadlineCannotEnterLayer() async throws {
        let timer = FHoldDeadline(); var calls = 0
        timer.schedule(after: 0.02) { calls += 1 }; timer.cancel()
        try await Task.sleep(for: .milliseconds(70))
        #expect(calls == 0)
    }
    @Test func newDeadlineInvalidatesPreviousReceiver() async throws {
        let timer = FHoldDeadline(); var deliveries: [String] = []
        timer.schedule(after: 0.02) { deliveries.append("old") }
        timer.schedule(after: 0.03) { deliveries.append("new") }
        for _ in 0..<100 where deliveries.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(deliveries == ["new"])
    }
}
