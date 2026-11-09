// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Testing
import Foundation
@testable import MixedInputCore

@Suite("Initial letter hold timing")
struct InitialLetterHoldTests {
    @Test(arguments: [100, 150, 250, 500, 1000])
    func configurableThresholdAndSingleConversion(_ delay: Int) {
        var gesture = InitialLetterHoldGesture()
        gesture.begin(keyCode: 1, at: 10, delayMilliseconds: delay)
        let threshold = 10 + Double(delay) / 1000
        let result1 = gesture.advance(to: threshold - 0.001, keyIsDown: true)
        #expect(!result1)
        let result2 = gesture.advance(to: threshold, keyIsDown: true)
        #expect(result2)
        let result3 = gesture.advance(to: threshold + 1, keyIsDown: true)
        #expect(!result3)
        #expect(gesture.keyCode == nil)
    }
    @Test func shortReleaseAndMissingKeyUpNeverConvertLater() {
        var gesture = InitialLetterHoldGesture()
        gesture.begin(keyCode: 1, at: 0, delayMilliseconds: 250)
        let result4 = gesture.release(at: 0.249)
        #expect(!result4)
        let result5 = gesture.advance(to: 1, keyIsDown: true)
        #expect(!result5)
        gesture.begin(keyCode: 1, at: 2, delayMilliseconds: 250)
        let result6 = gesture.advance(to: 3, keyIsDown: false)
        #expect(!result6)
        let result7 = gesture.advance(to: 4, keyIsDown: true)
        #expect(!result7)
    }
    @Test func delayedTimerSettlesUsingReleaseTimestamp() {
        var gesture = InitialLetterHoldGesture()
        gesture.begin(keyCode: 1, at: 0, delayMilliseconds: 250)
        let result8 = gesture.release(at: 0.25)
        #expect(result8)
        let result9 = gesture.release(at: 1)
        #expect(!result9)
    }
    @Test func cancellationAndNewGestureDoNotInheritElapsedTime() {
        var gesture = InitialLetterHoldGesture()
        gesture.begin(keyCode: 1, at: 0, delayMilliseconds: 100)
        gesture.cancel()
        let result10 = gesture.advance(to: 1, keyIsDown: true)
        #expect(!result10)
        gesture.begin(keyCode: 2, at: 2, delayMilliseconds: 1000)
        #expect(gesture.keyCode == 2)
        let result11 = gesture.advance(to: 2.9, keyIsDown: true)
        #expect(!result11)
        let result12 = gesture.advance(to: 3, keyIsDown: true)
        #expect(result12)
    }
    @Test func invalidStoredDurationsAreBounded() {
        #expect(InitialLetterHoldGesture.defaultDelayMilliseconds == 250)
        #expect(InitialLetterHoldGesture.clampedDelayMilliseconds(Int.min) == 100)
        #expect(InitialLetterHoldGesture.clampedDelayMilliseconds(Int.max) == 1000)
    }

    @Test(arguments: [true, false])
    func eitherStateTableCanConfirmHold(_ useSession: Bool) throws {
        var gesture = InitialLetterHoldGesture()
        gesture.begin(keyCode: 1, at: 0, delayMilliseconds: 250)
        let early = gesture.probe(to: 0.1, sessionKeyDown: useSession, hardwareKeyDown: !useSession)
        #expect(!early)
        let due = gesture.probe(to: 0.25, sessionKeyDown: useSession, hardwareKeyDown: !useSession)
        #expect(due)
        let initial = ShiftLetterSession(composition: ASCIIComposition(raw: "S"))
        let lower = try #require(initial.lowercasingInitialLetter())
        #expect(lower.composition.raw == "s")
    }

    @Test func failedProbePreservesRealRepeatFallbackAndConfiguredDeadline() throws {
        var gesture = InitialLetterHoldGesture()
        gesture.begin(keyCode: 1, at: 0, delayMilliseconds: 1000)
        let probe = gesture.probe(to: 0.25, sessionKeyDown: false, hardwareKeyDown: false)
        #expect(!probe)
        #expect(gesture.keyCode == 1)
        let earlyRepeat = gesture.advance(to: 0.5, keyIsDown: true)
        #expect(!earlyRepeat)
        let dueProbe = gesture.probe(to: 1, sessionKeyDown: false, hardwareKeyDown: false)
        #expect(!dueProbe)
        let realRepeat = gesture.advance(to: 1.1, keyIsDown: true)
        #expect(realRepeat)
        let initial = ShiftLetterSession(composition: ASCIIComposition(raw: "S"))
        let lower = try #require(initial.lowercasingInitialLetter())
        if case .updated(let next) = lower.applying(.insert("S"), shiftHeld: true, repeating: true) {
            #expect(next.composition.raw == "s")
        } else { Issue.record("Repeat must preserve one lowercase letter") }
    }

    @Test func failedProbeDoesNotChangeShortReleaseOrCancelledComposition() {
        var gesture = InitialLetterHoldGesture()
        gesture.begin(keyCode: 1, at: 0, delayMilliseconds: 250)
        let probe = gesture.probe(to: 0.3, sessionKeyDown: false, hardwareKeyDown: false)
        #expect(!probe)
        // IMK 晚送，但實際放開時間早於門檻；不可因回呼延遲變成小寫。
        let released = gesture.release(at: 0.1)
        #expect(!released)
        let staleRepeat = gesture.advance(to: 0.6, keyIsDown: true)
        #expect(!staleRepeat)
        gesture.begin(keyCode: 1, at: 1, delayMilliseconds: 250)
        gesture.cancel()
        let staleProbe = gesture.probe(to: 2, sessionKeyDown: true, hardwareKeyDown: true)
        #expect(!staleProbe)
    }

    @Test func receiverSurvivesTransientProxyAndIsReleasedOnCancellation() {
        var context = InitialLetterHoldContext<NSObject>()
        weak var proxy: NSObject?
        let token: UUID
        do {
            let eventReceiver = NSObject(); proxy = eventReceiver
            token = context.begin(receiver: eventReceiver)
        }
        #expect(proxy != nil)
        #expect(context.resolve(token) === proxy)
        context.cancel()
        #expect(proxy == nil)
        #expect(context.resolve(token) == nil)
    }

    @Test func staleTimerCannotResolveNewInputConnection() {
        var context = InitialLetterHoldContext<NSObject>()
        let old = context.begin(receiver: NSObject())
        context.cancel() // 失焦、模式切換、Secure Input 或編輯時取消。
        let receiver = NSObject(), current = context.begin(receiver: receiver)
        #expect(context.resolve(old) == nil)
        #expect(context.resolve(current) === receiver)
        context.cancel()
        #expect(context.resolve(current) == nil)
    }
}
