// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Testing
@testable import MixedInputCore

@Suite("Independent F symbol layer")
struct QuickSymbolTests {
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
        var gesture = FHoldGesture()
        #expect(gesture.handle(.press(eligible: true, repeating: false)) == [.schedule, .consume])
        #expect(gesture.handle(.release) == [.invalidate, .replayTap, .consume])
        #expect(gesture.handle(.release).isEmpty)
        #expect(gesture.handle(.timeout).isEmpty)
    }

    @Test func holdEntersAndReleaseExitsWithoutTypingF() {
        var gesture = FHoldGesture()
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.timeout) == [.beginLayer])
        #expect(gesture.phase == .held)
        #expect(gesture.handle(.press(eligible: false, repeating: true)) == [.consume])
        #expect(gesture.handle(.otherKey).isEmpty)
        #expect(gesture.handle(.release) == [.invalidate, .endLayer, .consume])
        #expect(gesture.phase == .idle)
    }

    @Test func fastTypingReplaysBeforeFollowingKey() {
        var gesture = FHoldGesture()
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.otherKey) == [.invalidate, .replayTap])
        #expect(gesture.handle(.timeout).isEmpty)
        #expect(gesture.handle(.release).isEmpty)
    }

    @Test func modifiedFAndEnglishAndPhoneticInputStayUntouched() {
        var gesture = FHoldGesture()
        #expect(gesture.handle(.press(eligible: false, repeating: false)).isEmpty)
        #expect(gesture.handle(.timeout).isEmpty)
        #expect(gesture.handle(.press(eligible: true, repeating: true)).isEmpty)
        #expect(gesture.phase == .idle)
    }

    @Test func deactivationInvalidatesPendingTimer() {
        var gesture = FHoldGesture()
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.cancel) == [.invalidate])
        #expect(gesture.handle(.timeout).isEmpty)
        #expect(gesture.handle(.release).isEmpty)
    }

    @Test func cancellationExitsHeldLayer() {
        var gesture = FHoldGesture()
        _ = gesture.handle(.press(eligible: true, repeating: false))
        _ = gesture.handle(.timeout)
        #expect(gesture.handle(.cancel) == [.invalidate, .endLayer])
        #expect(gesture.phase == .idle)
    }
    @Test func thresholdAndMissingReleaseRecovery() {
        var gesture = FHoldGesture()
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.poll(elapsed: 0.099, isPressed: true)).isEmpty)
        #expect(gesture.phase == .pending)
        #expect(gesture.handle(.poll(elapsed: 0.100, isPressed: true)).isEmpty)
        #expect(gesture.handle(.poll(elapsed: 0.101, isPressed: true)) == [.beginLayer])
        #expect(gesture.handle(.poll(elapsed: 0.150, isPressed: true)).isEmpty)
        #expect(gesture.handle(.poll(elapsed: 0.160, isPressed: false)) == [.invalidate, .endLayer, .consume])
        #expect(gesture.phase == .idle)
        #expect(gesture.handle(.release).isEmpty)
        #expect(gesture.handle(.poll(elapsed: 0.200, isPressed: false)).isEmpty)
        #expect(gesture.handle(.press(eligible: true, repeating: false)) == [.schedule, .consume])
    }

    @Test func missingShortTapReleaseReplaysOnceAndCannotOpenLayerLater() {
        var gesture = FHoldGesture()
        _ = gesture.handle(.press(eligible: true, repeating: false))
        _ = gesture.handle(.poll(elapsed: 0.010, isPressed: true))
        #expect(gesture.handle(.poll(elapsed: 0.050, isPressed: false)) == [.invalidate, .replayTap, .consume])
        #expect(gesture.handle(.poll(elapsed: 0.110, isPressed: false)).isEmpty)
        #expect(gesture.handle(.release).isEmpty)
    }

    @Test func cancelledGestureIgnoresPollingUntilNextPress() {
        var gesture = FHoldGesture()
        _ = gesture.handle(.press(eligible: true, repeating: false))
        _ = gesture.handle(.poll(elapsed: 0.101, isPressed: true))
        _ = gesture.handle(.cancel)
        #expect(gesture.handle(.poll(elapsed: 0.200, isPressed: true)).isEmpty)
        #expect(gesture.handle(.release).isEmpty)
        #expect(gesture.handle(.press(eligible: true, repeating: false)) == [.schedule, .consume])
    }

    @Test func unavailableSamplerReplaysFInsteadOfLatchingLayer() {
        var gesture = FHoldGesture()
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.poll(elapsed: 0.010, isPressed: false)).isEmpty)
        #expect(gesture.handle(.poll(elapsed: 0.100, isPressed: false)).isEmpty)
        #expect(gesture.handle(.poll(elapsed: 0.101, isPressed: false)) == [.invalidate, .replayTap, .consume])
        #expect(gesture.phase == .idle)
        #expect(gesture.handle(.release).isEmpty)
    }

    @Test func samplerTrustDoesNotLeakAcrossGestures() {
        var gesture = FHoldGesture()
        _ = gesture.handle(.press(eligible: true, repeating: false))
        _ = gesture.handle(.poll(elapsed: 0.010, isPressed: true))
        _ = gesture.handle(.release)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.poll(elapsed: 0.010, isPressed: false)).isEmpty)
        #expect(gesture.handle(.poll(elapsed: 0.101, isPressed: false)) == [.invalidate, .replayTap, .consume])
        #expect(gesture.handle(.release).isEmpty)
    }

}
