// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Testing
@testable import MixedInputCore

@Suite("Application input mode rules")
struct AppInputRulesTests {
    let terminal = AppInputModeSession.Application(bundleIdentifier: "com.example.Terminal", processIdentifier: 42)
    let editor = AppInputModeSession.Application(bundleIdentifier: "com.example.Editor", processIdentifier: 43)
    var settings: AppInputRuleSettings { .init(rules: [.init(bundleIdentifier: terminal.bundleIdentifier, displayName: "Terminal", mode: .english)]) }
    func target(_ s: AppInputModeSession, client: String? = "com.example.Terminal", active: Bool = true,
                secure: Bool = false, safe: Bool = true) -> AppInputMode? {
        s.target(clientBundleIdentifier: client, generation: s.generation, inputActive: active, secureInput: secure, safeToSwitch: safe)
    }
    @Test func disabledEmptyAndUnconfiguredKeepExistingBehavior() {
        var s = AppInputModeSession()
        s.enter(terminal, enabled: false, settings: settings)
        #expect(target(s) == nil)
        s.enter(editor, enabled: true, settings: settings)
        #expect(target(s, client: editor.bundleIdentifier) == nil)
        s.enter(terminal, enabled: true, settings: .init())
        #expect(target(s) == nil)
    }
    @Test func repeatedActivationAndSetValueKeepManualChoiceAcrossClients() {
        var s = AppInputModeSession()
        s.enter(terminal, enabled: true, settings: settings)
        #expect(target(s) == .english)
        let generation = s.generation
        s.selectManually(.bopomofo, clientBundleIdentifier: terminal.bundleIdentifier, generation: generation)
        let changed = s.enter(terminal, enabled: true, settings: settings)
        #expect(!changed)
        #expect(s.generation == generation)
        for _ in 0..<4 { #expect(target(s) == .bopomofo) }
        s.enter(editor, enabled: true, settings: settings)
        s.enter(terminal, enabled: true, settings: settings)
        #expect(target(s) == .english)
    }
    @Test func settingsChangesWaitUntilNextVisit() {
        var s = AppInputModeSession()
        s.enter(terminal, enabled: true, settings: settings)
        s.enter(terminal, enabled: false, settings: .init())
        #expect(target(s) == .english)
        s.enter(editor, enabled: false, settings: .init())
        s.enter(terminal, enabled: false, settings: .init())
        #expect(target(s) == nil)
    }
    @Test func compositionsGesturesSecureInputAndInactiveSourcesDefer() {
        var s = AppInputModeSession()
        s.enter(terminal, enabled: true, settings: settings)
        #expect(target(s, safe: false) == nil)
        #expect(target(s, secure: true) == nil)
        #expect(target(s, active: false) == nil)
        #expect(target(s, client: nil) == nil)
        #expect(target(s, client: editor.bundleIdentifier) == nil)
        #expect(target(s) == .english)
    }
    @Test func staleCallbacksCannotChangeNewForegroundSession() {
        var s = AppInputModeSession()
        s.enter(terminal, enabled: true, settings: settings)
        let old = s.generation
        s.enter(editor, enabled: true, settings: settings)
        s.enter(terminal, enabled: true, settings: settings)
        s.selectManually(.bopomofo, clientBundleIdentifier: terminal.bundleIdentifier, generation: old)
        #expect(s.target(clientBundleIdentifier: terminal.bundleIdentifier, generation: old, inputActive: true, secureInput: false, safeToSwitch: true) == nil)
        #expect(target(s) == .english)
        s.enter(nil, enabled: true, settings: settings)
        #expect(target(s) == nil)
    }
    @Test func restartAndSameDisplayNamesUseIdentity() {
        var s = AppInputModeSession()
        s.enter(terminal, enabled: true, settings: settings)
        s.selectManually(.bopomofo, clientBundleIdentifier: terminal.bundleIdentifier, generation: s.generation)
        s.enter(.init(bundleIdentifier: terminal.bundleIdentifier, processIdentifier: 99), enabled: true, settings: settings)
        #expect(target(s) == .english)
        var rules = settings
        rules.upsert(.init(bundleIdentifier: editor.bundleIdentifier, displayName: "Terminal", mode: .bopomofo))
        s.enter(editor, enabled: true, settings: rules)
        #expect(target(s, client: editor.bundleIdentifier) == .bopomofo)
    }
    @Test func addEditRemoveAndTerminalExamplesDoNotOverwrite() {
        var rules = AppInputRuleSettings()
        let manual = AppInputRule(bundleIdentifier: terminal.bundleIdentifier, displayName: "Terminal", mode: .bopomofo)
        rules.upsert(manual)
        rules.upsert(settings.rules[0], replacingExisting: false)
        #expect(rules.rules == [manual])
        rules.upsert(settings.rules[0])
        #expect(rules.rules == settings.rules)
        #expect(AppInputRuleSettings.decode(rules.encoded()) == rules)
        rules.remove(bundleIdentifier: terminal.bundleIdentifier)
        #expect(rules.rules.isEmpty)
    }
    @Test func corruptedUnsupportedDuplicateAndInvalidSettingsFailSafely() {
        for raw in ["", "{", "[]", "{\"version\":2,\"rules\":[]}", "{\"version\":1,\"rules\":[{\"mode\":\"invalid\"}]}", String(repeating: "x", count: 1_048_577)] {
            #expect(AppInputRuleSettings.decode(raw).rules.isEmpty)
        }
        let rule = settings.rules[0]
        let invalid = AppInputRule(bundleIdentifier: "bad id", displayName: "App", mode: .english)
        #expect(AppInputRuleSettings(rules: [rule, rule, invalid]).rules == [rule])
    }
    @Test func automaticSwitchWaitsForDoubleShiftAndDoesNotBreakGesture() {
        var gesture = DoubleShiftGesture()
        #expect(!gesture.isPending(at: 0))
        _ = gesture.update(shiftDown: true, otherModifiers: false, time: 0)
        #expect(gesture.isPending(at: 0.01))
        _ = gesture.update(shiftDown: false, otherModifiers: false, time: 0.05)
        #expect(gesture.isPending(at: 0.1))
        #expect(!gesture.isPending(at: 1))
        _ = gesture.update(shiftDown: true, otherModifiers: false, time: 0.15)
        let recognized = gesture.update(shiftDown: false, otherModifiers: false, time: 0.2)
        #expect(recognized)
        #expect(!gesture.isPending(at: 0.2))
    }

    @Test func symbolOwnershipStillBlocksSwitchAfterFRelease() {
        var ownership = SymbolKeyOwnership()
        #expect(!ownership.hasOwnedKeys)
        _ = ownership.keyDown(15, repeating: false, layerActive: true, shortcut: false, mapped: true)
        #expect(ownership.hasOwnedKeys)
        let swallowed = ownership.keyDown(15, repeating: true, layerActive: false, shortcut: false)
        #expect(swallowed)
        #expect(ownership.hasOwnedKeys)
        _ = ownership.keyUp(15)
        #expect(!ownership.hasOwnedKeys)
    }

}
