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
        let previousDelegate = app.delegate
        let applicationDelegate = PromptApplicationDelegate(
            window: form.window
        )
        app.delegate = applicationDelegate
        defer {
            app.delegate = previousDelegate
        }
        app.finishLaunching()
        form.show()
        app.runModal(for: form.window)
        form.window.orderOut(nil)
        return outcome
    }
}
