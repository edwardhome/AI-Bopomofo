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
    @Test func overlappingShiftsAndFocusChangeCancel() {
        var g = DoubleShiftGesture()
        _ = g.update(shiftDown: true, otherModifiers: false, time: 0)
        _ = g.update(shiftDown: true, otherModifiers: false, time: 0.01)
        #expect(g.update(shiftDown: false, otherModifiers: false, time: 0.05) == false)
        #expect(!tap(&g, at: 0.1)); g.reset(); #expect(!tap(&g, at: 0.2))
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

    @Test func overlappingShiftsRequireFreshPairAfterBothRelease() {
        var g = DoubleShiftGesture()
        #expect(g.update(shiftDown: true, otherModifiers: false, time: 0) == false)
        #expect(g.update(shiftDown: true, otherModifiers: false, time: 0.01) == false)
        #expect(g.update(shiftDown: true, otherModifiers: false, time: 0.02) == false)
        #expect(g.update(shiftDown: false, otherModifiers: false, time: 0.03) == false)
        #expect(!tap(&g, at: 0.1))
        #expect(tap(&g, at: 0.2))
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

}
