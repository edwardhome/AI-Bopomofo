import Testing
@testable import MixedInputCore
@Suite("Double Shift") struct DoubleShiftTests {
    func tap(_ g: inout DoubleShiftGesture, at t: Double) -> Bool {
        _ = g.update(shiftDown: true, otherModifiers: false, time: t)
        return g.update(shiftDown: false, otherModifiers: false, time: t + 0.05)
    }
    @Test func twoTapsToggleOnceAndCanToggleBack() {
        var g = DoubleShiftGesture()
        #expect(!tap(&g, at: 0)); #expect(tap(&g, at: 0.15))
        #expect(!tap(&g, at: 0.3)); #expect(tap(&g, at: 0.45))
    }
    @Test func typingAndChordsCancel() {
        var g = DoubleShiftGesture()
        #expect(!tap(&g, at: 0)); g.reset()
        #expect(!tap(&g, at: 0.1))
        _ = g.update(shiftDown: true, otherModifiers: true, time: 0.2)
        #expect(!tap(&g, at: 0.3))
    }
    @Test func longPressAndSlowTapsDoNotToggle() {
        var g = DoubleShiftGesture()
        _ = g.update(shiftDown: true, otherModifiers: false, time: 0)
        #expect(g.update(shiftDown: false, otherModifiers: false, time: 0.5) == false)
        #expect(!tap(&g, at: 0.6)); #expect(!tap(&g, at: 1.2))
    }
    @Test func focusChangeClearsFirstTap() {
        var g = DoubleShiftGesture()
        #expect(!tap(&g, at: 0))
        g.reset()
        #expect(!tap(&g, at: 0.1))
        #expect(tap(&g, at: 0.2))
    }
    @Test func uppercaseFChordDoesNotCountAsShiftTap() {
        var g = DoubleShiftGesture()
        _ = g.update(shiftDown: true, otherModifiers: false, time: 0)
        g.reset() // F key-down while Shift is held.
        #expect(g.update(shiftDown: false, otherModifiers: false, time: 0.1) == false)
        #expect(!tap(&g, at: 0.2))
        #expect(tap(&g, at: 0.3))
    }

    @Test func idleModifierSnapshotsDoNotEraseFirstTap() {
        var g = DoubleShiftGesture()
        #expect(g.update(shiftDown: false, otherModifiers: false, time: 0) == false)
        #expect(!tap(&g, at: 0.1))
        #expect(g.update(shiftDown: false, otherModifiers: false, time: 0.16) == false)
        #expect(tap(&g, at: 0.25))
        #expect(g.update(shiftDown: false, otherModifiers: false, time: 0.31) == false)
        #expect(!tap(&g, at: 0.4))
    }

    @Test func modifierChordCannotBecomeTapWhenOtherModifierReleasesFirst() {
        var g = DoubleShiftGesture()
        #expect(!tap(&g, at: 0))
        #expect(g.update(shiftDown: true, otherModifiers: true, time: 0.1) == false)
        #expect(g.update(shiftDown: true, otherModifiers: false, time: 0.12) == false)
        #expect(g.update(shiftDown: false, otherModifiers: false, time: 0.15) == false)
        #expect(!tap(&g, at: 0.2))
        #expect(tap(&g, at: 0.3))
    }

    @Test func continuousShiftStateCountsAsOnlyOneTap() {
        var g = DoubleShiftGesture()
        #expect(g.update(shiftDown: true, otherModifiers: false, time: 0) == false)
        #expect(g.update(shiftDown: true, otherModifiers: false, time: 0.01) == false)
        #expect(g.update(shiftDown: true, otherModifiers: false, time: 0.02) == false)
        #expect(g.update(shiftDown: false, otherModifiers: false, time: 0.03) == false)
        #expect(tap(&g, at: 0.1))
        #expect(!tap(&g, at: 0.2))
    }

    @Test func invalidOrReversedTimesDoNotToggle() {
        var g = DoubleShiftGesture()
        #expect(g.update(shiftDown: true, otherModifiers: false, time: 1) == false)
        #expect(g.update(shiftDown: false, otherModifiers: false, time: 0.9) == false)
        #expect(g.update(shiftDown: true, otherModifiers: false, time: .nan) == false)
        #expect(g.update(shiftDown: false, otherModifiers: false, time: 1.1) == false)
        #expect(!tap(&g, at: 1.2))
        #expect(tap(&g, at: 1.3))
    }

    @Test func duplicatedIMKStateTraceTogglesOncePerPair() {
        // Relative times and Shift state from a user-operated IMK session; no text or key codes.
        let events: [(Double, Bool)] = [
            (0.000000, true),
            (0.009039, true),
            (0.093952, false),
            (0.101317, false),
            (0.177079, true),
            (0.185815, true),
            (0.259797, false),
            (0.265476, false),
            (0.696150, true),
            (0.704858, true),
            (0.799292, false),
            (0.806327, false),
            (0.881575, true),
            (0.892519, true),
            (0.960975, false),
            (0.967865, false)
        ]
        var g = DoubleShiftGesture()
        var toggles: [Int] = []
        for (index, event) in events.enumerated() {
            if g.update(shiftDown: event.1, otherModifiers: false, time: event.0) {
                toggles.append(index)
                g.reset() // The controller resets after changing modes.
            }
        }
        #expect(toggles == [6, 14])
    }

    @Test func duplicateDownDoesNotRestartLongPressTimer() {
        var g = DoubleShiftGesture()
        #expect(!tap(&g, at: 0))
        #expect(g.update(shiftDown: true, otherModifiers: false, time: 0.1) == false)
        #expect(g.update(shiftDown: true, otherModifiers: false, time: 0.3) == false)
        #expect(g.update(shiftDown: false, otherModifiers: false, time: 0.4) == false)
        #expect(!tap(&g, at: 0.5))
        #expect(tap(&g, at: 0.6))
    }

}
