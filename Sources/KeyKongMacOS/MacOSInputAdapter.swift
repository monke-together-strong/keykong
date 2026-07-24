import AppKit
import KeyKongCore

public final class MacOSInputAdapter: InputAdapter {
    public init() {}

    public func collectInput(for request: InputRequest) -> InputOutcome {
        precondition(Thread.isMainThread, "The macOS adapter must run on the main thread")
        return MainActor.assumeIsolated {
            Self.collectInputOnMainActor(for: request)
        }
    }

    @MainActor
    private static func collectInputOnMainActor(for request: InputRequest) -> InputOutcome {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        var outcome = InputOutcome.cancelled
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
