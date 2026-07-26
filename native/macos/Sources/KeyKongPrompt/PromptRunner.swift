import AppKit

public enum PromptRunner {
    @MainActor
    public static func run(_ request: PromptRequest) -> PromptOutcome {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.mainMenu = makeMainMenu()

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

    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let editMenu = NSMenu(title: "Edit")
        let editItem = NSMenuItem(
            title: "Edit",
            action: nil,
            keyEquivalent: ""
        )
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        editMenu.addItem(
            NSMenuItem(
                title: "Paste",
                action: #selector(NSText.paste(_:)),
                keyEquivalent: "v"
            )
        )
        return mainMenu
    }
}
