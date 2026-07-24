import AppKit

final class DemoController: NSObject {
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 440, height: 270),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )

    @objc func submit() {
        // A real broker would deliver values to its declared sink here.
        // This demo intentionally never exposes entered values to stdout.
        window.contentView = confirmationView()
    }

    @objc func cancel() {
        NSApp.terminate(nil)
    }

    func show() {
        window.title = "Key Kong"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = formView()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func formView() -> NSView {
        let view = NSView()
        let title = label("Credentials needed", size: 20, weight: .semibold)
        let detail = label("Values stay on this Mac and are delivered directly to the selected destination.", size: 13, weight: .regular)
        detail.maximumNumberOfLines = 2
        let first = secureField("GitHub token")
        let second = secureField("Deploy token")
        let cancel = button("Cancel", action: #selector(cancel))
        let send = button("Send", action: #selector(submit))
        send.keyEquivalent = "\r"

        let buttons = NSStackView(views: [cancel, send])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let stack = NSStackView(views: [title, detail, first, second, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            first.widthAnchor.constraint(equalTo: stack.widthAnchor),
            second.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return view
    }

    private func confirmationView() -> NSView {
        let view = NSView()
        let title = label("Delivered", size: 20, weight: .semibold)
        let detail = label("Key Kong sent both values to their declared destination.", size: 13, weight: .regular)
        let done = button("Done", action: #selector(cancel))
        done.keyEquivalent = "\r"
        let stack = NSStackView(views: [title, detail, done])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 50),
            done.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
        return view
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.lineBreakMode = .byWordWrapping
        return field
    }

    private func secureField(_ placeholder: String) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.placeholderString = placeholder
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return field
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let controller = DemoController()
controller.show()
app.run()
