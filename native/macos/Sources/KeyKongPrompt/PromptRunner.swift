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

    static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        applicationMenu.addItem(
            NSMenuItem(
                title: "Quit KeyKong",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

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
                title: "Undo",
                action: Selector(("undo:")),
                keyEquivalent: "z"
            )
        )
        let redoItem = NSMenuItem(
            title: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(
            NSMenuItem(
                title: "Cut",
                action: #selector(NSText.cut(_:)),
                keyEquivalent: "x"
            )
        )
        editMenu.addItem(
            NSMenuItem(
                title: "Copy",
                action: #selector(NSText.copy(_:)),
                keyEquivalent: "c"
            )
        )
        editMenu.addItem(
            NSMenuItem(
                title: "Paste",
                action: #selector(NSText.paste(_:)),
                keyEquivalent: "v"
            )
        )
        editMenu.addItem(.separator())
        editMenu.addItem(
            NSMenuItem(
                title: "Select All",
                action: #selector(NSResponder.selectAll(_:)),
                keyEquivalent: "a"
            )
        )
        return mainMenu
    }
}
