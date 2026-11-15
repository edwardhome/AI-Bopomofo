// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Cocoa
import MixedInputCore

/// 只觀察前景應用程式，不監聽按鍵、不切換 TIS 系統來源。
/// 設定只在新的前景使用期間讀取，按鍵處理只查詢記憶體中的 session。
@MainActor
final class AppInputRuleRuntime {
    static let shared = AppInputRuleRuntime()
    private(set) var session = AppInputModeSession()
    weak var activeController: McBopomofoInputMethodController?
    private var observer: NSObjectProtocol?

    private init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshForeground() }
        }
        refreshForeground()
    }

    func refreshForeground() {
        let front = NSWorkspace.shared.frontmostApplication
        let identity = front.flatMap { app in
            app.bundleIdentifier.map { AppInputModeSession.Application(bundleIdentifier: $0, processIdentifier: app.processIdentifier) }
        }
        // 相同 App 的欄位啟用不能重新讀取／套用設定。
        guard identity != session.application else { return }
        let enabled = Preferences.appInputRulesEnabled
        session.enter(identity, enabled: enabled, settings: enabled ? Preferences.appInputRuleSettings : .init())
        activeController?.applicationRuleContextChanged()
    }

    func selectManually(_ mode: AppInputMode, clientBundleIdentifier: String?, generation: UInt64) {
        session.selectManually(mode, clientBundleIdentifier: clientBundleIdentifier, generation: generation)
    }
}
