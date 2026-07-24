import AppKit

public enum PromptRunner {
    @MainActor
    public static func run(_ request: PromptRequest) -> PromptOutcome {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        var outcome = PromptOutcome.cancelled
        let form = MacOSInputFormController(request: request) {
            outcome = $0
            NSApp.stopModal()
        }
        form.show()
        app.runModal(for: form.window)
        form.window.orderOut(nil)
        return outcome
    }
}
