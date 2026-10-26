// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Cocoa

enum InputFeedback {
    static func beep() {
        // Hosted tests must never play sound, independent of persisted preferences.
        guard ProcessInfo.processInfo.environment["AI_BOPOMOFO_SILENT_TESTS"] != "1",
              NSClassFromString("XCTestCase") == nil else { return }
        NSSound.beep()
    }
}

extension InputState {
    /// An explicit, reversible ASCII composition. Ordinary Bopomofo keys never enter it.
    @objc(InputStateASCII)
    class ASCII: Inputting {
        @objc init(text: String, cursor: UInt) {
            super.init(composingBuffer: text, cursorIndex: min(cursor, UInt(text.utf16.count)))
            tooltip = NSLocalizedString("ASCII: Enter to commit, Esc to cancel", comment: "")
        }

        override var description: String { "<InputState.ASCII>" }
    }
}

/// Called exclusively by KeyHandler, keeping all event transitions in the IME pipeline.
@objc class MixedInputHandler: NSObject {
    @objc static func handle(
        input: KeyHandlerInput, state: InputState.ASCII,
        stateCallback: (InputState) -> Void, errorCallback: () -> Void
    ) -> Bool {
        let text = state.composingBuffer as NSString
        let cursor = Int(state.cursorIndex)
        func update(_ text: String, _ cursor: Int) {
            stateCallback(InputState.ASCII(text: text, cursor: UInt(cursor)))
        }
        func commit() {
            stateCallback(InputState.Committing(poppedText: state.composingBuffer))
            stateCallback(InputState.Empty())
        }
        if input.charCode == 27 {
            stateCallback(InputState.EmptyIgnoringPreviousState())
        } else if input.isCommandHold || input.isOptionHold || input.isControlHold {
            commit()
            return false
        } else if input.charCode == 13 || input.isEnter {
            commit()
        } else if input.charCode == 8 {
            if cursor > 0 {
                update(text.replacingCharacters(in: NSRange(location: cursor - 1, length: 1), with: ""), cursor - 1)
            }
        } else if input.isDelete {
            if cursor < text.length {
                update(text.replacingCharacters(in: NSRange(location: cursor, length: 1), with: ""), cursor)
            }
        } else if input.isLeft {
            update(text as String, max(0, cursor - 1))
        } else if input.isRight {
            update(text as String, min(text.length, cursor + 1))
        } else if input.isHome {
            update(text as String, 0)
        } else if input.isEnd {
            update(text as String, text.length)
        } else if let literal = input.inputText, !literal.isEmpty,
                  literal.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) }),
                  text.length + literal.utf16.count <= 256 {
            update(text.replacingCharacters(in: NSRange(location: cursor, length: 0), with: literal), cursor + literal.utf16.count)
        } else {
            errorCallback()
        }
        return true
    }
}
