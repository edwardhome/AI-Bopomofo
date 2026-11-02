// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Testing
@testable import MixedInputCore

@Suite("Independent F symbol layer")
struct QuickSymbolTests {
    @Test func phoneticOverlapReplaysOnceAndNeverReenters() {
        for code: UInt16 in [32, 46] {
            for milliseconds in [100, 150, 250, 1000] {
                let deadline = Double(milliseconds) / 1000
                for elapsed in [0.001, deadline - 0.001, deadline] {
                    for fReleasedFirst in [false, true] {
                        var gesture = FHoldGesture(delayMilliseconds: milliseconds)
                        var ownership = SymbolKeyOwnership()
                        _ = gesture.handle(.press(eligible: true, repeating: false))
                        #expect(gesture.handle(.elapsed(elapsed)).isEmpty)
                        let mapped = QuickSymbolLayer.canStartChord(keyCode: code, repeating: false,
                            hasDisallowedModifiers: false, prefersPhonetic: true)
                        #expect(!mapped)
                        #expect(gesture.handle(.otherKey(isMapped: mapped)) == [.invalidate, .replayTap])
                        #expect(gesture.phase == .idle)
                        #expect(ownership.keyDown(code, repeating: false, layerActive: false, shortcut: false) == false)
                        // 已選注音就不能被晚到的計時器或仍按住的 F 重複事件變回符號。
                        #expect(gesture.handle(.elapsed(deadline + 1)).isEmpty)
                        #expect(gesture.handle(.timeout).isEmpty)
                        #expect(gesture.handle(.press(eligible: true, repeating: true)) == [.consume])
                        #expect(gesture.handle(.otherKey(isMapped: true)).isEmpty)
                        if !fReleasedFirst { #expect(ownership.keyUp(code) == false) }
                        #expect(gesture.handle(.observedRelease) == [.consume])
                        #expect(gesture.handle(.release) == [.consume])
                        if fReleasedFirst { #expect(ownership.keyUp(code) == false) }
                        #expect(gesture.handle(.release).isEmpty)
                        #expect(ownership.keyDown(code, repeating: true, layerActive: false, shortcut: false) == false)
                    }
                }
            }
        }
    }

    @Test func longHoldKeepsEightAndTwoAfterPhoneticDeadline() {
        for (code, output): (UInt16, String) in [(32, "8"), (46, "2")] {
            var gesture = FHoldGesture(delayMilliseconds: 250)
            var ownership = SymbolKeyOwnership()
            _ = gesture.handle(.press(eligible: true, repeating: false))
            #expect(gesture.handle(.elapsed(0.251)) == [.beginLayer])
            #expect(gesture.handle(.otherKey(isMapped: true)).isEmpty)
            #expect(ownership.keyDown(code, repeating: false, layerActive: true, shortcut: false) == false)
            #expect(QuickSymbolLayer.output(for: code) == output)
            #expect(gesture.handle(.observedRelease) == [.invalidate, .endLayer, .consume])
            #expect(ownership.keyDown(code, repeating: true, layerActive: false, shortcut: false) == true)
            #expect(ownership.keyUp(code) == true)
        }
    }

    @Test func englishAndOtherChordsKeepImmediateEntry() {
        for code: UInt16 in [32, 46, 15, 53] {
            var gesture = FHoldGesture(delayMilliseconds: 250)
            _ = gesture.handle(.press(eligible: true, repeating: false))
            let mapped = QuickSymbolLayer.canStartChord(keyCode: code, repeating: false,
                hasDisallowedModifiers: false, prefersPhonetic: false)
            #expect(mapped)
            #expect(gesture.handle(.otherKey(isMapped: mapped)) == [.beginLayer])
            #expect(gesture.handle(.release) == [.invalidate, .endLayer, .consume])
        }
    }

    @Test func phoneticCancelAndIMKFirstReleaseCannotReplayAgain() {
        for end in [FHoldGesture.Event.release, .cancel] {
            var gesture = FHoldGesture(delayMilliseconds: 250)
            _ = gesture.handle(.press(eligible: true, repeating: false))
            #expect(gesture.handle(.otherKey(isMapped: false)) == [.invalidate, .replayTap])
            #expect(!gesture.handle(end).contains(.replayTap))
            #expect(!gesture.handle(.observedRelease).contains(.replayTap))
            #expect(gesture.handle(.timeout).isEmpty)
        }
    }

    @Test func immediateChordRetainsMonitorUntilRelease() {
        for milliseconds in [100, 150, 500, 1000] {
            var gesture = FHoldGesture(delayMilliseconds: milliseconds)
            var monitoring = false
            let pressed = gesture.handle(.press(eligible: true, repeating: false))
            if pressed.contains(.schedule) { monitoring = true }
            #expect(gesture.handle(.elapsed(0.010)).isEmpty)
            let started = gesture.handle(.otherKey(isMapped: true))
            if started.contains(.invalidate) { monitoring = false }
            #expect(started == [.beginLayer])
            #expect(monitoring)
            #expect(gesture.phase == .held)
            #expect(gesture.handle(.elapsed(2)).isEmpty)
            #expect(gesture.handle(.otherKey(isMapped: true)).isEmpty)
            let released = gesture.handle(.observedRelease)
            if released.contains(.invalidate) { monitoring = false }
            #expect(!monitoring)
            #expect(released == [.invalidate, .endLayer, .consume])
            #expect(gesture.phase == .idle)
            #expect(gesture.handle(.release) == [.consume])
        }
    }

    @Test func firstChordKeyIsOwnedAndEditedExactlyOnce() throws {
        for entry in QuickSymbolLayer.entries {
            var gesture = FHoldGesture()
            var keys = SymbolKeyOwnership()
            var buffer = ASCIIComposition()
            _ = gesture.handle(.press(eligible: true, repeating: false))
            let mapped = QuickSymbolLayer.canStartChord(keyCode: entry.keyCode,
                repeating: false, hasDisallowedModifiers: false)
            #expect(gesture.handle(.otherKey(isMapped: mapped)) == [.beginLayer])
            // Match the adapter ordering: activate, register ownership, route text.
            #expect(keys.keyDown(entry.keyCode, repeating: false,
                layerActive: gesture.phase == .held, shortcut: false) == false)
            if case .updated(let edited) = QuickSymbolLayer.edit(keyCode: entry.keyCode, composition: buffer) {
                buffer = edited
            } else { Issue.record("First chord key was not edited") }
            #expect(buffer.raw == entry.output)
            _ = gesture.handle(.observedRelease)
            #expect(keys.keyDown(entry.keyCode, repeating: true,
                layerActive: gesture.phase == .held, shortcut: false) == true)
            #expect(keys.keyUp(entry.keyCode) == true)
            #expect(keys.keyDown(entry.keyCode, repeating: false,
                layerActive: false, shortcut: false) == false)
        }
    }

    @Test func shortcutRepeatAndUnmappedKeysNeverStartEarly() {
        for code: UInt16 in [15, 53, 8, 51] {
            for repeated in [false, true] {
                for forbidden in [false, true] {
                    var gesture = FHoldGesture()
                    _ = gesture.handle(.press(eligible: true, repeating: false))
                    let mapped = QuickSymbolLayer.canStartChord(keyCode: code,
                        repeating: repeated, hasDisallowedModifiers: forbidden)
                    let expected = (code == 15 || code == 53) && !repeated && !forbidden
                    #expect(mapped == expected)
                    let effects = gesture.handle(.otherKey(isMapped: mapped))
                    #expect(effects == (expected ? [.beginLayer] : [.invalidate, .replayTap]))
                }
            }
        }
    }

    @Test func releasedFBeforeMappedKeyIsNormalFastTyping() {
        var gesture = FHoldGesture()
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.observedRelease) == [.invalidate, .replayTap, .consume])
        #expect(gesture.handle(.otherKey(isMapped: true)).isEmpty)
        #expect(gesture.phase == .idle)
        #expect(gesture.handle(.release) == [.consume])
    }

    @Test func earlyLayerCancelOrMonitorFailureCannotReenter() {
        for end in [FHoldGesture.Event.cancel, .release] {
            var gesture = FHoldGesture()
            _ = gesture.handle(.press(eligible: true, repeating: false))
            _ = gesture.handle(.otherKey(isMapped: true))
            let effects = gesture.handle(end)
            #expect(effects.contains(.invalidate))
            #expect(effects.contains(.endLayer))
            #expect(!effects.contains(.replayTap))
            #expect(gesture.handle(.elapsed(1)).isEmpty)
            #expect(gesture.handle(.otherKey(isMapped: true)).isEmpty)
        }
    }

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
        #expect(gesture.handle(.otherKey(isMapped: false)).contains(.replayTap))
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
        #expect(gesture.handle(.otherKey(isMapped: false)).isEmpty)
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

    @Test func unmappedKeyReplaysBeforeTheNextPhoneticKey() {
        var gesture = FHoldGesture(delayMilliseconds: 500)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.elapsed(0.200)).isEmpty)
        #expect(gesture.handle(.otherKey(isMapped: false)) == [.invalidate, .replayTap])
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
            ([53,50,18,19,20,21,23,22,26,28,25,29,27,24],
             ["`","`","!","@","#","$","%","^","&","~","(",")","_","'"]),
            ([12,13,14,15,16,32,34,31,35,33,30,42],
             ["/","*","-","+","7","8","9","{","}","[","]","\\"]),
            ([0,1,2,5,4,38,40,37,41,39],
             ["<",">","=",">","4","5","6",":",";","\""]),
            ([6,7,11,45,46,43,47,44,49], ["'","|","°","1","2","3",".","?","0"])
        ]
        for (codes, values) in rows {
            #expect(codes.map { QuickSymbolLayer.output(for: $0) } == values.map(Optional.some))
        }
        #expect(Set(QuickSymbolLayer.entries.map(\.keyCode)).count == 45)
        for code: UInt16 in [3,8,9,17,36,55] { #expect(QuickSymbolLayer.output(for: code) == nil) }
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
        #expect(gesture.handle(.otherKey(isMapped: false)).isEmpty)
        #expect(gesture.handle(.release) == [.invalidate, .endLayer, .consume])
        #expect(gesture.phase == .idle)
    }

    @Test func unmappedOverlappingKeyReplaysBeforeFollowingKey() {
        var gesture = FHoldGesture(delayMilliseconds: 100)
        _ = gesture.handle(.press(eligible: true, repeating: false))
        #expect(gesture.handle(.otherKey(isMapped: false)) == [.invalidate, .replayTap])
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


@Suite("Held symbols and deletion")
struct HeldSymbolEditingTests {
    private func edit(_ code: UInt16, _ composition: ASCIIComposition) throws -> ASCIIComposition {
        let result = try #require(QuickSymbolLayer.edit(keyCode: code, composition: composition))
        guard case .updated(let updated) = result else {
            Issue.record("Expected an editable composition")
            return composition
        }
        return updated
    }

    @Test func backspaceRepeatsWhileFRemainsHeld() throws {
        var buffer = ASCIIComposition()
        for code: UInt16 in [16, 32, 34, 15] { buffer = try edit(code, buffer) }
        #expect(buffer.raw == "789+")
        for expected in ["789", "78", "7", "", ""] {
            buffer = try edit(51, buffer)
            #expect(buffer.raw == expected)
        }
        buffer = try edit(15, buffer)
        #expect(buffer.raw == "+")
    }

    @Test func editingPreservesEnglishCursorAndForwardDelete() throws {
        var buffer = ASCIIComposition(raw: "abcd", cursor: 2)
        buffer = try edit(15, buffer)
        #expect(buffer.raw == "ab+cd")
        buffer = try edit(51, buffer)
        #expect(buffer.raw == "abcd")
        #expect(buffer.cursor == 2)
        buffer = try edit(117, buffer)
        #expect(buffer.raw == "abd")
        #expect(buffer.cursor == 2)
    }

    @Test func deletionNeverAcquiresSymbolRepeatOwnership() {
        var keys = SymbolKeyOwnership()
        for code: UInt16 in [51, 117] {
            #expect(keys.keyDown(code, repeating: false, layerActive: true, shortcut: false) == false)
            for active in [true, false, false] {
                #expect(keys.keyDown(code, repeating: true, layerActive: active, shortcut: false) == false)
            }
            #expect(keys.keyUp(code) == false)
        }
    }

    @Test func mappedKeyRepeatStopsOnFReleaseAndFreshPressRecoversWithoutKeyUp() {
        var keys = SymbolKeyOwnership()
        #expect(keys.keyDown(15, repeating: false, layerActive: true, shortcut: false) == false)
        #expect(keys.keyDown(15, repeating: true, layerActive: true, shortcut: false) == false)
        #expect(keys.keyDown(15, repeating: true, layerActive: false, shortcut: false) == true)
        #expect(keys.keyDown(15, repeating: false, layerActive: false, shortcut: false) == false)
        #expect(keys.keyDown(15, repeating: true, layerActive: false, shortcut: false) == false)
    }

    @Test func shortcutAndKeyUpReleaseOwnership() {
        var keys = SymbolKeyOwnership()
        _ = keys.keyDown(15, repeating: false, layerActive: true, shortcut: false)
        #expect(keys.keyUp(15) == true)
        #expect(keys.keyDown(15, repeating: true, layerActive: false, shortcut: false) == false)
        _ = keys.keyDown(15, repeating: false, layerActive: true, shortcut: false)
        #expect(keys.keyDown(15, repeating: true, layerActive: false, shortcut: true) == false)
    }
}
