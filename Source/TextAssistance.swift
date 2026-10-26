// Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
import Cocoa
import Carbon
import CandidateRanking
import MixedInputCore

extension InputState {
    @objc(InputStateAssistance)
    class Assistance: InputState, CandidateProvider {
        @objc let original: InputState.Inputting
        let suggestions: [String]
        let selectedIndex: Int
        let isChecking: Bool
        let message: String
        var values: [String] { [original.composingBuffer] + suggestions }
        init(original: InputState.Inputting, suggestions: [String] = [], selectedIndex: Int = 0,
             isChecking: Bool = false, message: String) {
            self.original = original; self.suggestions = suggestions
            self.selectedIndex = min(max(selectedIndex, 0), suggestions.count)
            self.isChecking = isChecking; self.message = message
            super.init()
        }
        func selecting(_ index: Int) -> Assistance {
            Assistance(original: original, suggestions: suggestions, selectedIndex: index,
                       isChecking: false, message: NSLocalizedString("Choose a suggestion; Esc returns to your text", comment: ""))
        }
        var candidateCount: Int { values.count }
        func candidate(at index: Int) -> String {
            guard values.indices.contains(index) else { return "" }
            let label = index == 0 ? NSLocalizedString("Original", comment: "")
                : NSLocalizedString(original is InputState.ASCII ? "English spelling" : "Chinese correction", comment: "")
            return label + ": " + values[index]
        }
        func reading(at index: Int) -> String? { nil }
    }
}

@objc class AssistanceKeyHandler: NSObject {
    /// Return false to restore the original state and re-process a normal typing/shortcut key.
    @objc static func handle(input: KeyHandlerInput, state: InputState.Assistance,
                             stateCallback: (InputState) -> Void) -> Bool {
        if input.charCode == 27 { stateCallback(state.original); return true }
        if input.isCommandHold || input.isOptionHold || input.isControlHold { return false }
        if input.charCode == 13 || input.isEnter {
            accept(index: state.selectedIndex, state: state, stateCallback: stateCallback); return true
        }
        if input.isTab || input.isDown || input.isUp {
            let delta = input.isUp || (input.isTab && input.isShiftHold) ? -1 : 1
            stateCallback(state.selecting((state.selectedIndex + delta + state.candidateCount) % state.candidateCount))
            return true
        }
        if state.isChecking { return false }
        let labels = Array(Preferences.candidateKeys)
        if let character = input.inputText?.first, let index = labels.firstIndex(of: character), index < state.candidateCount {
            accept(index: index, state: state, stateCallback: stateCallback); return true
        }
        return false
    }
    @objc static func accept(index: Int, state: InputState.Assistance, stateCallback: (InputState) -> Void) {
        guard state.values.indices.contains(index) else { return }
        stateCallback(InputState.Committing(poppedText: state.values[index]))
        stateCallback(InputState.Empty())
    }
}

// IMK's Objective-C entry points do not declare Swift actor isolation. Marshal UI work
// explicitly rather than assuming a callback can call an actor-isolated API directly.
final class TextAssistant {
    private var session: TextAssistantSession?
    private func use(_ body: @escaping @MainActor (TextAssistantSession) -> Void) {
        let action: @MainActor () -> Void = {
            if self.session == nil { self.session = TextAssistantSession() }
            body(self.session!)
        }
        if Thread.isMainThread { MainActor.assumeIsolated(action) }
        else { DispatchQueue.main.sync { MainActor.assumeIsolated(action) } }
    }
    func cancel() { use { $0.cancel() } }
    func check(controller: McBopomofoInputMethodController) { use { $0.check(controller: controller) } }
    func schedulePrediction(state: InputState, controller: McBopomofoInputMethodController) {
        use { $0.schedulePrediction(state: state, controller: controller) }
    }
}

@MainActor
private final class TextAssistantSession {
    // Shared across every controller, not one inference slot per input field.
    private static let coordinator = AssistanceCoordinator(provider: AppleTextAssistance())
    private let owner = UUID()
    private var revision: UInt64 = 0
    private var debounce: Task<Void, Never>?

    func cancel() {
        revision &+= 1
        debounce?.cancel(); debounce = nil
        Self.coordinator.invalidate(owner: owner)
    }
    func check(controller: McBopomofoInputMethodController) {
        cancel()
        guard !IsSecureEventInputEnabled(), controller.currentClient != nil,
              controller.keyHandler.canBeginAssistance(with: controller.state),
              let original = controller.state as? InputState.Inputting else { return }
        let request = CorrectionRequest(revision: revision, text: original.composingBuffer,
            isEnglish: original is InputState.ASCII, protectedWords: MixedInputHandler.lexicon.words)
        guard request.isValid else {
            let next = InputState.Assistance(original: original,
                message: NSLocalizedString("Check up to 256 characters and 1024 bytes at a time", comment: ""))
            publish(next, controller: controller); return
        }
        let checking = InputState.Assistance(original: original, isChecking: true,
            message: NSLocalizedString("Checking on this Mac; you can keep typing", comment: ""))
        publish(checking, controller: controller)
        let checkingRevision = revision
        Task { [weak self, weak controller] in
            let fallback = await SystemSpelling.suggestions(for: request)
            guard let self, let controller, self.revision == checkingRevision, controller.state === checking,
                  controller.currentClient != nil, !IsSecureEventInputEnabled() else { return }
            Self.coordinator.submit(owner: self.owner, request: request, fallback: fallback,
            isCurrent: { [weak controller] in
                guard let controller else { return false }
                return controller.state === checking && controller.currentClient != nil && !IsSecureEventInputEnabled()
            }, completion: { [weak self, weak controller] result in
                guard let self, let controller else { return }
                // A dictionary reload can occur while inference is running.
                let latestRequest = CorrectionRequest(revision: request.revision, text: original.composingBuffer,
                    isEnglish: original is InputState.ASCII, protectedWords: MixedInputHandler.lexicon.words)
                let suggestions = latestRequest.validated(result.suggestions)
                let message: String
                switch result.status {
                case .ready: message = suggestions.isEmpty ? "No correction suggested" : "Choose a suggestion; Esc returns to your text"
                case .unavailable: message = "Apple AI unavailable; showing original or system spelling"
                case .timedOut: message = "Check timed out; showing original or system spelling"
                case .busy: message = "Apple AI is busy; showing original or system spelling"
                }
                self.publish(InputState.Assistance(original: original, suggestions: suggestions,
                    message: NSLocalizedString(message, comment: "")), controller: controller)
            })
        }
    }
    private func publish(_ state: InputState.Assistance, controller: McBopomofoInputMethodController) {
        controller.keyHandler.publishAssistance(state) {
            controller.handle(state: $0, client: controller.currentClient)
        }
    }
    func schedulePrediction(state: InputState, controller: McBopomofoInputMethodController) {
        guard Preferences.englishPredictionEnabled, !IsSecureEventInputEnabled(),
              controller.currentClient != nil, let ascii = state as? InputState.ASCII,
              ascii.prediction == nil, !ascii.predictionSuppressed,
              ascii.composition.selectedIndex == 0,
              ascii.composition.cursor == ascii.composition.raw.utf16.count else { return }
        let request = CorrectionRequest(revision: revision, text: ascii.composition.raw,
            mode: .prediction, isEnglish: true, protectedWords: MixedInputHandler.lexicon.words)
        guard request.isValid else { return }
        let scheduledRevision = revision
        debounce = Task { [weak self, weak controller] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self, let controller, self.revision == scheduledRevision,
                  controller.state === ascii, Preferences.englishPredictionEnabled,
                  !IsSecureEventInputEnabled() else { return }
            let fallback = await SystemSpelling.suggestions(for: request)
            guard self.revision == scheduledRevision, controller.state === ascii,
                  Preferences.englishPredictionEnabled, !IsSecureEventInputEnabled(), !Task.isCancelled else { return }
            // Show the fast system suggestion without waiting for the slower Foundation Model.
            // Publishing an immutable state normally cancels debounce; this task is already awake.
            self.debounce = nil
            var publishedState: InputState = ascii
            if let fastSuggestion = fallback.first {
                controller.keyHandler.publishPrediction(fastSuggestion, state: ascii) {
                    publishedState = $0
                    controller.handle(state: $0, client: controller.currentClient)
                }
            }
            guard controller.state === publishedState,
                  let predictionState = publishedState as? InputState.ASCII else { return }
            Self.coordinator.submit(owner: self.owner, request: request, fallback: fallback,
                isCurrent: { [weak controller] in
                    guard let controller else { return false }
                    return controller.state === predictionState && controller.currentClient != nil
                        && Preferences.englishPredictionEnabled && !IsSecureEventInputEnabled()
                }, completion: { [weak controller] result in
                    guard let controller, let suggestion = result.suggestions.first,
                          suggestion != predictionState.prediction else { return }
                    controller.keyHandler.publishPrediction(suggestion, state: predictionState) {
                        controller.handle(state: $0, client: controller.currentClient)
                    }
                })
        }
    }
}

extension McBopomofoInputMethodController {
    @objc func checkTextAssistance(_ sender: Any?) { textAssistant.check(controller: self) }
    @objc func toggleEnglishPrediction(_ sender: Any?) {
        Preferences.englishPredictionEnabled.toggle()
        textAssistant.cancel()
        if let ascii = state as? InputState.ASCII {
            handle(state: InputState.ASCII(composition: ascii.composition, predictionSuppressed: !Preferences.englishPredictionEnabled), client: currentClient)
        }
    }
}
