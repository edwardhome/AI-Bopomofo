// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Testing
@testable import MixedInputCore

@Suite("Independent F symbol layer")
struct QuickSymbolTests {
    @Test func passiveTapThenIMKReleaseDoesNotLeakF() {
        for held in [false, true] {
            var gesture = FHoldGesture(delayMilliseconds: 300)
            _ = gesture.handle(.press(eligible: true, repeating: false))
            if held { _ = gesture.handle(.elapsed(0.301)) }
            let observed = gesture.handle(.observedRelease)
            #expect(observed.contains(.replayTap) == !held)
            #expect(observed.contains(.endLayer) == held)
            #expect(gesture.phase == .idle)
            #expect(gesture.handle(.observedRelease).contains(.replayTap) == false)
            #expect(gesture.handle(.release) == [.consume])
            #expect(gesture.handle(.release).isEmpty)
        }
    }

    @Test func imkReleaseBeforePassiveTapReplaysOnlyOnce() {
        var gesture = FHoldGesture(delayMilliseconds: 100)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.release).filter { $0 == .replayTap }.count == 1)
        #expect(gesture.handle(.observedRelease).isEmpty)
    }

    @Test func rolledFRepeatsCannotLeakAfterReplayingTap() {
        var gesture = FHoldGesture(delayMilliseconds: 500)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.otherKey).contains(.replayTap))
        for _ in 0..<3 {
            #expect(gesture.handle(.press(eligible: false, repeating: true)) == [.consume])
        }
        #expect(gesture.handle(.release) == [.consume])
        #expect(gesture.handle(.press(eligible: false, repeating: true)).isEmpty)
    }

    @Test func delayedTimerUsesSymbolEventDeadlineWithoutTypingF() {
        var gesture = FHoldGesture(delayMilliseconds: 400)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        // The adapter advances using R's timestamp even if the timer has not fired.
        #expect(gesture.handle(.elapsed(0.450)) == [.beginLayer])
        #expect(gesture.handle(.otherKey).isEmpty)
        #expect(gesture.handle(.observedRelease) == [.invalidate, .endLayer, .consume])
        #expect(gesture.handle(.release) == [.consume])
    }

    @Test func nextPressWorksWhenClientNeverDeliversKeyUp() {
        var gesture = FHoldGesture(delayMilliseconds: 100)
        for _ in 0..<3 {
            #expect(gesture.handle(.press(eligible: true, repeating: false)) == [.schedule, .consume])
            #expect(gesture.handle(.observedRelease) == [.invalidate, .replayTap, .consume])
        }
        _ = gesture.handle(.cancel)
        #expect(gesture.handle(.release).isEmpty)
    }

    @Test func longerDelayPreservesAnOrdinaryPress() {
        var gesture = FHoldGesture(delayMilliseconds: 400)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.elapsed(0.150)).isEmpty)
        #expect(gesture.handle(.press(eligible: true, repeating: true)) == [.consume])
        #expect(gesture.handle(.elapsed(0.250)).isEmpty)
        #expect(gesture.handle(.release) == [.invalidate, .replayTap, .consume])
        #expect(gesture.handle(.release).isEmpty)
        #expect(gesture.handle(.elapsed(0.500)).isEmpty)
    }

    @Test func longerDelayReplaysBeforeTheNextPhoneticKey() {
        var gesture = FHoldGesture(delayMilliseconds: 500)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.elapsed(0.200)).isEmpty)
        #expect(gesture.handle(.otherKey) == [.invalidate, .replayTap])
        #expect(gesture.handle(.release) == [.consume])
    }

    @Test func configuredThresholdAndRelease() {
        for milliseconds in [100, 150, 300, 500, 1000] {
            var gesture = FHoldGesture(delayMilliseconds: milliseconds)
            let seconds = Double(milliseconds) / 1000
            _ = gesture.handle(.press(eligible: true, repeating: false))
            #expect(gesture.handle(.elapsed(seconds)).isEmpty)
            #expect(gesture.handle(.elapsed(seconds + 0.001)) == [.beginLayer])
            #expect(gesture.handle(.release) == [.invalidate, .endLayer, .consume])
        }
    }

    @Test func releaseInsideGraceIntervalKeepsOriginalKey() {
        for seconds in [0.050, 0.099, 0.100, 0.125, 0.150] {
            var gesture = FHoldGesture()
            _ = gesture.handle(.press(eligible: true, repeating: false))
            #expect(gesture.handle(.elapsed(seconds)).isEmpty)
            #expect(gesture.handle(.observedRelease).contains(.replayTap))
        }
        var gesture = FHoldGesture()
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.elapsed(0.151)) == [.beginLayer])
        #expect(!gesture.handle(.observedRelease).contains(.replayTap))
    }

    @Test func invalidDelayIsBoundedAndDefaultIncludesGraceInterval() {
        #expect(FHoldGesture().delay == 0.15)
        #expect(FHoldGesture(delayMilliseconds: Int.min).delay == 0.1)
        #expect(FHoldGesture(delayMilliseconds: Int.max).delay == 1.0)
    }

    @Test func suppliedKeyboardRows() {
        let rows: [([UInt16], [String])] = [
            ([50,18,19,20,21,23,22,26,28,25,29,27,24],
             ["`","!","@","#","$","%","^","&","~","(",")","_","'"]),
            ([12,13,14,15,16,32,34,31,35,33,30,42],
             ["/","*","-","+","7","8","9","{","}","[","]","\\"]),
            ([0,1,2,5,4,38,40,37,41,39],
             ["<",">","=",">","4","5","6",":",";","\""]),
            ([6,7,11,45,46,43,47,44,49], ["'","|","°","1","2","3",".","?","0"])
        ]
        for (codes, values) in rows {
            #expect(codes.map { QuickSymbolLayer.output(for: $0) } == values.map(Optional.some))
        }
        #expect(Set(QuickSymbolLayer.entries.map(\.keyCode)).count == 44)
        for code: UInt16 in [3,8,9,17,36,53,55] { #expect(QuickSymbolLayer.output(for: code) == nil) }
    }

    @Test func tapReplaysExactlyOnce() {
        var gesture = FHoldGesture(delayMilliseconds: 100)
        #expect(gesture.handle(.press(eligible: true, repeating: false)) == [.schedule, .consume])
        #expect(gesture.handle(.release) == [.invalidate, .replayTap, .consume])
        #expect(gesture.handle(.release).isEmpty)
        #expect(gesture.handle(.timeout).isEmpty)
    }

    @Test func holdEntersAndReleaseExitsWithoutTypingF() {
        var gesture = FHoldGesture(delayMilliseconds: 100)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.timeout) == [.beginLayer])
        #expect(gesture.phase == .held)
        #expect(gesture.handle(.press(eligible: false, repeating: true)) == [.consume])
        #expect(gesture.handle(.otherKey).isEmpty)
        #expect(gesture.handle(.release) == [.invalidate, .endLayer, .consume])
        #expect(gesture.phase == .idle)
    }

    @Test func fastTypingReplaysBeforeFollowingKey() {
        var gesture = FHoldGesture(delayMilliseconds: 100)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.otherKey) == [.invalidate, .replayTap])
        #expect(gesture.handle(.timeout).isEmpty)
        #expect(gesture.handle(.release) == [.consume])
    }

    @Test func modifiedFAndEnglishAndPhoneticInputStayUntouched() {
        var gesture = FHoldGesture(delayMilliseconds: 100)
        #expect(gesture.handle(.press(eligible: false, repeating: false)).isEmpty)
        #expect(gesture.handle(.timeout).isEmpty)
        #expect(gesture.handle(.press(eligible: true, repeating: true)).isEmpty)
        #expect(gesture.phase == .idle)
    }

    @Test func deactivationInvalidatesPendingTimer() {
        var gesture = FHoldGesture(delayMilliseconds: 100)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.cancel) == [.invalidate])
        #expect(gesture.handle(.timeout).isEmpty)
        #expect(gesture.handle(.release).isEmpty)
    }

    @Test func cancellationExitsHeldLayer() {
        var gesture = FHoldGesture(delayMilliseconds: 100)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        _ = gesture.handle(.timeout)
        #expect(gesture.handle(.cancel) == [.invalidate, .endLayer])
        #expect(gesture.phase == .idle)
    }
    @Test func thresholdAndMonitorRelease() {
        var gesture = FHoldGesture(delayMilliseconds: 100)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.elapsed(0.099)).isEmpty)
        #expect(gesture.handle(.elapsed(0.100)).isEmpty)
        #expect(gesture.handle(.elapsed(0.101)) == [.beginLayer])
        #expect(gesture.handle(.elapsed(0.150)).isEmpty)
        #expect(gesture.handle(.release) == [.invalidate, .endLayer, .consume])
        #expect(gesture.handle(.release).isEmpty)
        #expect(gesture.handle(.elapsed(0.200)).isEmpty)
    }

    @Test func monitorReleaseBeforeDeadlineReplaysOnlyOnce() {
        var gesture = FHoldGesture(delayMilliseconds: 100)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.elapsed(0.050)).isEmpty)
        #expect(gesture.handle(.release) == [.invalidate, .replayTap, .consume])
        #expect(gesture.handle(.elapsed(0.110)).isEmpty)
        #expect(gesture.handle(.release).isEmpty)
    }

    @Test func monitorFailureReleasesPendingAndHeldGestures() {
        var gesture = FHoldGesture(delayMilliseconds: 100)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.release) == [.invalidate, .replayTap, .consume])
        _ = gesture.handle(.press(eligible: true, repeating: false))
        _ = gesture.handle(.elapsed(0.101))
        #expect(gesture.handle(.release) == [.invalidate, .endLayer, .consume])
        #expect(gesture.phase == .idle)
    }

    @Test func cancelAndLateTimerCannotReenter() {
        var gesture = FHoldGesture(delayMilliseconds: 100)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        _ = gesture.handle(.elapsed(0.101))
        _ = gesture.handle(.cancel)
        #expect(gesture.handle(.elapsed(0.200)).isEmpty)
        #expect(gesture.handle(.release).isEmpty)
        #expect(gesture.handle(.press(eligible: true, repeating: false)) == [.schedule, .consume])
    }
}
