// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
/// Two short, isolated Shift taps; chords, typing and long presses cancel the gesture.
public struct DoubleShiftGesture {
    public static let tapLimit = 0.25
    public static let interval = 0.35
    private var downAt: Double?
    private var firstRelease: Double?
    private var shiftWasDown = false
    public init() {}
    public mutating func reset() {
        downAt = nil
        firstRelease = nil
        shiftWasDown = false
    }
    private mutating func cancelSequence() { downAt = nil; firstRelease = nil }

    /// Read modifier state, not a physical key code: IMK clients need not identify a Shift side.
    /// The caller supplies monotonic receipt time and resets on typing or focus changes.
    public mutating func update(shiftDown: Bool, otherModifiers: Bool, time: Double) -> Bool {
        let changed = shiftDown != shiftWasDown
        shiftWasDown = shiftDown
        guard time.isFinite, !otherModifiers else { cancelSequence(); return false }
        guard changed else {
            // A second down notification can mean overlapping left/right Shift keys.
            // An idle flags snapshot is harmless and must not erase the first tap.
            if shiftDown { cancelSequence() }
            return false
        }
        if shiftDown {
            if let last = firstRelease, time < last || time - last > Self.interval { firstRelease = nil }
            downAt = time
            return false
        }
        guard let downAt, time >= downAt, time - downAt <= Self.tapLimit else { cancelSequence(); return false }
        self.downAt = nil
        if let last = firstRelease, time >= last, time - last <= Self.interval {
            firstRelease = nil; return true
        }
        firstRelease = time
        return false
    }
}
