import AppKit
import KeyKongCore

@MainActor
final class MacOSInputFormController: NSObject, NSWindowDelegate {
    let window: NSWindow
    let sendButton: NSButton
    let cancelButton: NSButton
    private(set) var inputViews: [NSView] = []
    private(set) var errorLabels: [String: NSTextField] = [:]

    private let request: InputRequest
    private let onComplete: (InputOutcome) -> Void
    private var didComplete = false

    init(request: InputRequest, onComplete: @escaping (InputOutcome) -> Void) {
        self.request = request
        self.onComplete = onComplete
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.sendButton = NSButton(title: "Send", target: nil, action: nil)
        self.cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        super.init()

        configureWindow()
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(firstFocusableView())
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func submit() {
        errorLabels.values.forEach { $0.isHidden = true }

        var values: [String: ResponseValue] = [:]
        var firstInvalidView: NSView?

        for (field, view) in zip(request.fields, inputViews) {
            switch field.type {
            case .text:
                let textField = view as! NSTextField
                if textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    markInvalid(field.id)
                    firstInvalidView = firstInvalidView ?? textField
                } else {
                    values[field.id] = .text(textField.stringValue)
                }

            case .select:
                let popUp = view as! NSPopUpButton
                if popUp.indexOfSelectedItem < 1 {
                    markInvalid(field.id)
                    firstInvalidView = firstInvalidView ?? popUp
                } else if let options = field.options {
                    values[field.id] = .text(options[popUp.indexOfSelectedItem - 1].value)
                }

            case .multiSelect:
                let stack = view as! NSStackView
                let selected = zip(field.options ?? [], stack.arrangedSubviews)
                    .compactMap { option, view -> String? in
                        (view as? NSButton)?.state == .on ? option.value : nil
                    }
                if selected.isEmpty {
                    markInvalid(field.id)
                    firstInvalidView = firstInvalidView ?? stack.arrangedSubviews.first
                } else {
                    values[field.id] = .selection(selected)
                }
            }
        }

        if let firstInvalidView {
            window.makeFirstResponder(firstInvalidView)
            return
        }

        finish(with: .submitted(values))
    }

    @objc private func cancel() {
        finish(with: .cancelled)
    }

    func windowWillClose(_ notification: Notification) {
        cancel()
    }

    private func configureWindow() {
        window.title = request.title
        window.isReleasedWhenClosed = false
        window.delegate = self

        sendButton.target = self
        sendButton.action = #selector(submit)
        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r"
        sendButton.identifier = NSUserInterfaceItemIdentifier("send")

        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.identifier = NSUserInterfaceItemIdentifier("cancel")

        let root = NSView()
        let heading = NSTextField(labelWithString: request.title)
        heading.font = .systemFont(ofSize: 20, weight: .semibold)

        let fieldsStack = NSStackView()
        fieldsStack.orientation = .vertical
        fieldsStack.alignment = .leading
        fieldsStack.spacing = 16
        fieldsStack.translatesAutoresizingMaskIntoConstraints = false

        var focusableViews: [NSView] = []
        for field in request.fields {
            let input = makeInput(for: field)
            input.identifier = NSUserInterfaceItemIdentifier(field.id)
            inputViews.append(input)

            let error = NSTextField(labelWithString: "This field is required.")
            error.textColor = .systemRed
            error.font = .systemFont(ofSize: 11)
            error.isHidden = true
            errorLabels[field.id] = error

            let label = NSTextField(labelWithString: field.label)
            label.font = .systemFont(ofSize: 13, weight: .medium)

            let fieldStack = NSStackView(views: [label, input, error])
            fieldStack.orientation = .vertical
            fieldStack.alignment = .leading
            fieldStack.spacing = 6
            fieldStack.translatesAutoresizingMaskIntoConstraints = false
            input.widthAnchor.constraint(equalTo: fieldStack.widthAnchor).isActive = true
            fieldsStack.addArrangedSubview(fieldStack)
            fieldStack.widthAnchor.constraint(equalTo: fieldsStack.widthAnchor).isActive = true

            focusableViews.append(contentsOf: focusableControls(in: input))
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(fieldsStack)
        scrollView.documentView = documentView

        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            fieldsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            fieldsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            fieldsStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            fieldsStack.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor)
        ])

        let buttons = NSStackView(views: [cancelButton, sendButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let content = NSStackView(views: [heading, scrollView, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            heading.widthAnchor.constraint(equalTo: content.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: content.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor)
        ])

        configureTabOrder(focusableViews + [cancelButton, sendButton])
        window.contentView = root
    }

    private func makeInput(for field: InputField) -> NSView {
        switch field.type {
        case .text:
            let textField = NSTextField()
            textField.placeholderString = field.label
            textField.heightAnchor.constraint(equalToConstant: 28).isActive = true
            return textField

        case .select:
            let popUp = NSPopUpButton()
            popUp.addItem(withTitle: "Select…")
            popUp.item(at: 0)?.isEnabled = false
            for option in field.options ?? [] {
                popUp.addItem(withTitle: option.label)
            }
            popUp.selectItem(at: 0)
            popUp.heightAnchor.constraint(equalToConstant: 28).isActive = true
            return popUp

        case .multiSelect:
            let buttons = (field.options ?? []).map { option in
                let button = NSButton(
                    checkboxWithTitle: option.label,
                    target: nil,
                    action: nil
                )
                button.identifier = NSUserInterfaceItemIdentifier(
                    "\(field.id).\(option.value)"
                )
                return button
            }
            let stack = NSStackView(views: buttons)
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 6
            return stack
        }
    }

    private func focusableControls(in view: NSView) -> [NSView] {
        if let stack = view as? NSStackView {
            return stack.arrangedSubviews
        }
        return [view]
    }

    private func configureTabOrder(_ views: [NSView]) {
        for (current, next) in zip(views, views.dropFirst()) {
            current.nextKeyView = next
        }
    }

    private func firstFocusableView() -> NSView? {
        inputViews.first.flatMap { focusableControls(in: $0).first }
    }

    private func markInvalid(_ fieldID: String) {
        errorLabels[fieldID]?.isHidden = false
    }

    private func finish(with outcome: InputOutcome) {
        guard !didComplete else { return }
        didComplete = true
        onComplete(outcome)
    }
}
