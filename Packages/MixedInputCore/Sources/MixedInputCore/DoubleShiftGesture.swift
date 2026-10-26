// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
/// Two short, isolated Shift taps; chords, typing and long presses cancel the gesture.
public struct DoubleShiftGesture {
    public static let tapLimit = 0.25
    public static let interval = 0.35
    private var downAt: Double?
    private var firstRelease: Double?
    public init() {}
    public mutating func reset() { downAt = nil; firstRelease = nil }
    public mutating func update(isShift: Bool, isDown: Bool, otherModifiers: Bool, time: Double) -> Bool {
        guard isShift, !otherModifiers else { reset(); return false }
        if isDown {
            guard downAt == nil else { reset(); return false }
            if let last = firstRelease, time < last || time - last > Self.interval { firstRelease = nil }
            downAt = time
            return false
        }
        guard let downAt, time >= downAt, time - downAt <= Self.tapLimit else { reset(); return false }
        self.downAt = nil
        if let last = firstRelease, time >= last, time - last <= Self.interval {
            firstRelease = nil; return true
        }
        firstRelease = time
        return false
    }
}
