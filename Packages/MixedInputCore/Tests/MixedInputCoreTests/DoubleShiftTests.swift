import Testing
@testable import MixedInputCore
@Suite("Double Shift") struct DoubleShiftTests {
    func tap(_ g: inout DoubleShiftGesture, at t: Double) -> Bool {
        _ = g.update(isShift: true, isDown: true, otherModifiers: false, time: t)
        return g.update(isShift: true, isDown: false, otherModifiers: false, time: t + 0.05)
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
        _ = g.update(isShift: true, isDown: true, otherModifiers: true, time: 0.2)
        #expect(!tap(&g, at: 0.3))
    }
    @Test func longPressAndSlowTapsDoNotToggle() {
        var g = DoubleShiftGesture()
        _ = g.update(isShift: true, isDown: true, otherModifiers: false, time: 0)
        #expect(g.update(isShift: true, isDown: false, otherModifiers: false, time: 0.5) == false)
        #expect(!tap(&g, at: 0.6)); #expect(!tap(&g, at: 1.2))
    }
    @Test func overlappingShiftsAndFocusChangeCancel() {
        var g = DoubleShiftGesture()
        _ = g.update(isShift: true, isDown: true, otherModifiers: false, time: 0)
        _ = g.update(isShift: true, isDown: true, otherModifiers: false, time: 0.01)
        #expect(g.update(isShift: true, isDown: false, otherModifiers: false, time: 0.05) == false)
        #expect(!tap(&g, at: 0.1)); g.reset(); #expect(!tap(&g, at: 0.2))
    }
    @Test func uppercaseFChordDoesNotCountAsShiftTap() {
        var g = DoubleShiftGesture()
        _ = g.update(isShift: true, isDown: true, otherModifiers: false, time: 0)
        g.reset() // F key-down while Shift is held.
        #expect(g.update(isShift: true, isDown: false, otherModifiers: false, time: 0.1) == false)
        #expect(!tap(&g, at: 0.2))
        #expect(tap(&g, at: 0.3))
    }

}
