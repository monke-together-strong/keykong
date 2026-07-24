import AppKit
import KeyKongCore

public final class MacOSInputAdapter: InputAdapter {
    public init() {}

    public func collectInput(
        for request: InputRequest,
        deadline: RequestDeadline
    ) -> InputOutcome {
        precondition(Thread.isMainThread, "The macOS adapter must run on the main thread")
        guard !deadline.isExpired else { return .expired }
        return MainActor.assumeIsolated {
            Self.collectInputOnMainActor(
                for: request,
                expirationInterval: max(
                    0,
                    deadline.remainingTimeInterval - 0.25
                )
            )
        }
    }

    @MainActor
    private static func collectInputOnMainActor(
        for request: InputRequest,
        expirationInterval: TimeInterval
    ) -> InputOutcome {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        var outcome = InputOutcome.cancelled
        let form = MacOSInputFormController(
            request: request,
            expirationInterval: expirationInterval
        ) { result in
            outcome = result
            NSApp.stopModal()
        }

        form.show()
        app.runModal(for: form.window)
        form.window.orderOut(nil)
        return outcome
    }
}
