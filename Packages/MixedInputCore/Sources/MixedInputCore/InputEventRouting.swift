// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
/// Only key-down events may mutate composition. No key timing or global monitoring.
public enum InputEventKind: Sendable { case keyDown, keyUp, modifiers, other }
public enum InputEventRoute: Sendable { case text, modifiers, consume, passThrough }
public enum InputEventRouting {
    public static func route(_ kind: InputEventKind, hasComposition: Bool) -> InputEventRoute {
        switch kind {
        case .keyDown: return .text
        case .modifiers: return .modifiers
        case .keyUp: return hasComposition ? .consume : .passThrough
        case .other: return .passThrough
        }
    }
}
