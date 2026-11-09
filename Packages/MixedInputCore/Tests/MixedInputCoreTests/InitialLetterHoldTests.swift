// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Testing
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
}
