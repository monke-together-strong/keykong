import AppKit

public enum PromptRunner {
    @MainActor
    public static func run(_ request: PromptRequest) -> PromptOutcome {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        var outcome = PromptOutcome.cancelled
        let form = MacOSInputFormController(request: request) { result in
            outcome = result
            NSApp.stopModal()
        }
        form.show()
        app.runModal(for: form.window)
        form.window.orderOut(nil)
        return outcome
    }
}
