import AppKit

@MainActor
final class PromptApplicationDelegate: NSObject, NSApplicationDelegate {
    private(set) weak var window: NSWindow?

    init(window: NSWindow) {
        self.window = window
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        restorePrompt()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        restorePrompt()
        return false
    }

    private func restorePrompt() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }
}
