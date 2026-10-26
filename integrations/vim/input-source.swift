// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Foundation
import Carbon

func property(_ source: TISInputSource, _ key: CFString) -> String {
    guard let p = TISGetInputSourceProperty(source, key) else { return "" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}
func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8)); exit(1)
}
let args = Array(CommandLine.arguments.dropFirst())
guard args.count <= 1 else { fail("Usage: ai-bopomofo-input [current|normal|insert|--vscode-obtain|source-id]") }
let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
let current = property(TISCopyCurrentKeyboardInputSource().takeRetainedValue(), kTISPropertyInputSourceID)
let command = args.first ?? "current"
if command == "current" { print(current); exit(0) }
let ai = sources.first {
    property($0, kTISPropertyBundleID) == "org.aibopomofo.inputmethod.AIBopomofo"
    && property($0, kTISPropertyInputModeID) == "org.aibopomofo.inputmethod.AIBopomofo.Bopomofo"
}
if command == "--vscode-obtain" {
    // VSCodeVim remembers this as the Insert-mode source, enforcing the user's mixed-input choice.
    guard let ai else { fail("AI-Bopomofo input mode is not registered") }
    print(property(ai, kTISPropertyInputSourceID)); exit(0)
}
let english = sources.first {
    property($0, kTISPropertyBundleID) == "org.aibopomofo.inputmethod.AIBopomofo"
    && property($0, kTISPropertyInputModeID) == "org.aibopomofo.inputmethod.AIBopomofo.English"
}
if command == "--normal-source" {
    guard let english else { fail("AI-Bopomofo English mode is not registered; log out and back in") }
    print(property(english, kTISPropertyInputSourceID)); exit(0)
}
let target: TISInputSource?
switch command {
case "insert": target = ai
case "normal": target = english
default:
    guard command.count <= 256, command.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { fail("Invalid source ID") }
    target = sources.first { property($0, kTISPropertyInputSourceID) == command }
}
guard let target else { fail("Requested input source is not available") }
let result = TISSelectInputSource(target)
guard result == noErr else { fail("Input source selection failed: \(result)") }
