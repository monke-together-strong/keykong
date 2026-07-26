import AppKit

@MainActor
final class KeyKongFormWindow: NSWindow {
    var moveFocus: ((NSControl, Bool) -> Void)?
    var submit: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.keyCode == 48,
           event.modifierFlags
            .intersection([.command, .control, .option])
            .isEmpty,
           let focusedControl {
            moveFocus?(
                focusedControl,
                !event.modifierFlags.contains(.shift)
            )
            return
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           event.keyCode == 36 || event.keyCode == 76,
           event.modifierFlags.contains(.shift),
           event.modifierFlags
            .intersection([.command, .control, .option])
            .isEmpty {
            submit?()
            return true
        }
        if event.type == .keyDown,
           event.keyCode == 36 || event.keyCode == 76,
           let focusedControl {
            if let popUp = focusedControl as? KeyKongPopUpButton {
                popUp.performClick(nil)
                return true
            }
            if let checkbox = focusedControl as? KeyKongCheckboxButton {
                checkbox.performClick(nil)
                return true
            }
            if let button = focusedControl as? KeyKongPointerButton {
                button.performClick(nil)
                return true
            }
            if focusedControl is NSTextField {
                submit?()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    private var focusedControl: NSControl? {
        if let control = firstResponder as? NSControl {
            return control
        }
        return (firstResponder as? NSTextView)?.delegate as? NSControl
    }
}

@MainActor
final class MacOSInputFormController: NSObject, NSWindowDelegate {
    private static let bodySpacing: CGFloat = 18
    private static let bodyHorizontalInset: CGFloat = 6
    private static let maximumInitialWindowHeight: CGFloat = 520

    let window: KeyKongFormWindow
    let sendButton: NSButton
    let cancelButton: NSButton
    let detailsButton: NSButton
    let detailsView: NSStackView
    let deliveryDetails: [String]
    private(set) var inputViews: [NSView] = []
    private(set) var errorLabels: [String: NSTextField] = [:]

    private let request: PromptRequest
    private let onComplete: (PromptOutcome) -> Void
    private var didComplete = false
    private var collapsedWindowHeight: CGFloat?
    private weak var formScrollView: NSScrollView?
    private var tabOrder: [NSView] = []

    init(
        request: PromptRequest,
        onComplete: @escaping (PromptOutcome) -> Void
    ) {
        let deliveryDetails = request.deliveries.map {
            Self.describe($0, fields: request.fields)
        }
        self.request = request
        self.onComplete = onComplete
        self.window = KeyKongFormWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 426),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        self.sendButton = NSButton(title: "Send", target: nil, action: nil)
        self.cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        self.detailsButton = KeyKongPointerButton(
            title: "Details",
            target: nil,
            action: nil
        )
        self.deliveryDetails = deliveryDetails
        self.detailsView = NSStackView(
            views: deliveryDetails.map {
                NSTextField(wrappingLabelWithString: $0)
            }
        )
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

            case .secret:
                let secretInput = view as! SecretInputView
                if secretInput.stringValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty {
                    markInvalid(field.id)
                    firstInvalidView = firstInvalidView ?? secretInput.focusView
                } else {
                    values[field.id] = .text(secretInput.stringValue)
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
            DispatchQueue.main.async {
                firstInvalidView.enclosingScrollView?
                    .documentView?
                    .layoutSubtreeIfNeeded()
                let target = firstInvalidView.superview ?? firstInvalidView
                target.scrollToVisible(target.bounds)
            }
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
        window.moveFocus = { [weak self] control, forward in
            self?.moveFocus(from: control, forward: forward)
        }
        window.submit = { [weak self] in
            self?.submit()
        }
        window.title = request.title
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = KeyKongTheme.charcoal
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        if let closeButton = window.standardWindowButton(.closeButton) {
            KeyKongPointerCursor.install(on: closeButton)
        }

        sendButton.target = self
        sendButton.action = #selector(submit)
        KeyKongTheme.stylePrimaryButton(sendButton)
        sendButton.keyEquivalent = "\r"
        sendButton.keyEquivalentModifierMask = .shift
        sendButton.identifier = NSUserInterfaceItemIdentifier("send")
        sendButton.toolTip = "Submit these values for delivery"
        sendButton.widthAnchor.constraint(equalToConstant: 116).isActive = true
        sendButton.heightAnchor.constraint(equalToConstant: 34).isActive = true

        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        KeyKongTheme.styleSecondaryButton(cancelButton)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.identifier = NSUserInterfaceItemIdentifier("cancel")
        cancelButton.widthAnchor.constraint(equalToConstant: 104).isActive = true
        cancelButton.heightAnchor.constraint(equalToConstant: 34).isActive = true

        detailsButton.target = self
        detailsButton.action = #selector(toggleDetails)
        detailsButton.setButtonType(.pushOnPushOff)
        detailsButton.bezelStyle = .inline
        detailsButton.isBordered = false
        detailsButton.image = NSImage(
            systemSymbolName: "chevron.right",
            accessibilityDescription: "Show details"
        )
        detailsButton.imagePosition = .imageLeading
        detailsButton.identifier = NSUserInterfaceItemIdentifier("details")
        detailsButton.contentTintColor = KeyKongTheme.silver
        detailsButton.font = .systemFont(ofSize: 14, weight: .medium)
        detailsButton.isHidden = request.deliveries.isEmpty

        detailsView.orientation = .vertical
        detailsView.alignment = .leading
        detailsView.spacing = 6
        detailsView.isHidden = true
        for case let label as NSTextField in detailsView.arrangedSubviews {
            label.textColor = KeyKongTheme.silver
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        }

        let root = KeyKongBackgroundView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let emblem = NSImageView()
        emblem.identifier = NSUserInterfaceItemIdentifier("emblem")
        emblem.image = KeyKongTheme.emblem
        emblem.imageScaling = .scaleProportionallyUpOrDown
        emblem.wantsLayer = true
        emblem.layer?.cornerRadius = 44
        emblem.layer?.masksToBounds = true
        emblem.setAccessibilityElement(false)
        emblem.widthAnchor.constraint(equalToConstant: 88).isActive = true
        emblem.heightAnchor.constraint(equalToConstant: 88).isActive = true

        let heading = NSTextField(labelWithString: request.title)
        heading.identifier = NSUserInterfaceItemIdentifier("heading")
        heading.font = .systemFont(ofSize: 26, weight: .semibold)
        heading.textColor = .white
        heading.maximumNumberOfLines = 1
        heading.lineBreakMode = .byTruncatingTail
        heading.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        let reassurance = NSTextField(
            wrappingLabelWithString:
                "Values stay on this Mac and are delivered directly "
                + "to the selected destination."
        )
        reassurance.identifier = NSUserInterfaceItemIdentifier("reassurance")
        reassurance.font = .systemFont(ofSize: 14)
        reassurance.textColor = KeyKongTheme.silver
        reassurance.maximumNumberOfLines = 2

        let header = NSView()
        header.identifier = NSUserInterfaceItemIdentifier("header")
        for view in [emblem, heading, reassurance] {
            view.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(view)
        }
        let textBlock = NSLayoutGuide()
        header.addLayoutGuide(textBlock)
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 88),
            emblem.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            emblem.topAnchor.constraint(equalTo: header.topAnchor),
            textBlock.leadingAnchor.constraint(
                equalTo: emblem.trailingAnchor,
                constant: 24
            ),
            textBlock.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            textBlock.centerYAnchor.constraint(equalTo: emblem.centerYAnchor),
            heading.leadingAnchor.constraint(equalTo: textBlock.leadingAnchor),
            heading.trailingAnchor.constraint(equalTo: textBlock.trailingAnchor),
            heading.topAnchor.constraint(equalTo: textBlock.topAnchor),
            reassurance.leadingAnchor.constraint(equalTo: textBlock.leadingAnchor),
            reassurance.trailingAnchor.constraint(equalTo: textBlock.trailingAnchor),
            reassurance.topAnchor.constraint(
                equalTo: heading.bottomAnchor,
                constant: 8
            ),
            reassurance.bottomAnchor.constraint(equalTo: textBlock.bottomAnchor)
        ])

        let fieldsStack = NSStackView()
        fieldsStack.orientation = .vertical
        fieldsStack.alignment = .leading
        fieldsStack.spacing = 18
        fieldsStack.translatesAutoresizingMaskIntoConstraints = false

        var focusableViews: [NSView] = []
        for field in request.fields {
            let input = makeInput(for: field)
            input.identifier = NSUserInterfaceItemIdentifier(field.id)
            inputViews.append(input)

            let error = NSTextField(labelWithString: "This field is required.")
            error.textColor = NSColor.systemRed.blended(
                withFraction: 0.25,
                of: .white
            ) ?? .systemRed
            error.font = .systemFont(ofSize: 11)
            error.isHidden = true
            errorLabels[field.id] = error

            let label = NSTextField(labelWithString: field.label)
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .white

            let fieldStack = NSStackView(views: [label, input, error])
            fieldStack.orientation = .vertical
            fieldStack.alignment = .leading
            fieldStack.spacing = 7
            fieldStack.translatesAutoresizingMaskIntoConstraints = false
            input.widthAnchor.constraint(equalTo: fieldStack.widthAnchor).isActive = true
            fieldsStack.addArrangedSubview(fieldStack)
            fieldStack.widthAnchor.constraint(equalTo: fieldsStack.widthAnchor).isActive = true

            focusableViews.append(contentsOf: focusableControls(in: input))
        }

        let scrollView = NSScrollView()
        scrollView.identifier = NSUserInterfaceItemIdentifier("form-scroll")
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        formScrollView = scrollView

        let bodyStack = NSStackView(
            views: [fieldsStack, detailsButton, detailsView]
        )
        bodyStack.orientation = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = Self.bodySpacing
        bodyStack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = KeyKongFlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(bodyStack)
        scrollView.documentView = documentView

        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            bodyStack.leadingAnchor.constraint(
                equalTo: documentView.leadingAnchor,
                constant: Self.bodyHorizontalInset
            ),
            bodyStack.trailingAnchor.constraint(
                equalTo: documentView.trailingAnchor,
                constant: -Self.bodyHorizontalInset
            ),
            bodyStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            bodyStack.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor),
            fieldsStack.widthAnchor.constraint(equalTo: bodyStack.widthAnchor),
            detailsView.widthAnchor.constraint(equalTo: bodyStack.widthAnchor)
        ])

        let buttons = NSStackView(views: [cancelButton, sendButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 12

        let footer = NSView()
        footer.identifier = NSUserInterfaceItemIdentifier("footer")
        footer.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(buttons)
        NSLayoutConstraint.activate([
            buttons.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            buttons.topAnchor.constraint(equalTo: footer.topAnchor),
            buttons.bottomAnchor.constraint(equalTo: footer.bottomAnchor)
        ])

        let content = NSStackView(
            views: [header, scrollView, footer]
        )
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 20
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 48),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -48),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 54),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -30),
            header.widthAnchor.constraint(equalTo: content.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: content.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            footer.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])

        window.contentView = root
        window.autorecalculatesKeyViewLoop = false
        let detailControls = request.deliveries.isEmpty ? [] : [detailsButton]
        configureTabOrder(focusableViews + detailControls)
        root.layoutSubtreeIfNeeded()

        let missingBodyHeight = max(
            0,
            bodyStack.fittingSize.height - scrollView.contentView.bounds.height
        )
        let availableGrowth = max(
            0,
            Self.maximumInitialWindowHeight - window.frame.height
        )
        var frame = window.frame
        frame.size.height += min(missingBodyHeight, availableGrowth)
        window.setFrame(frame, display: false)
    }

    private func makeInput(for field: PromptField) -> NSView {
        switch field.type {
        case .text:
            let textField = NSTextField()
            KeyKongTheme.style(textField)
            textField.setAccessibilityLabel(field.label)
            textField.heightAnchor.constraint(equalToConstant: 36).isActive = true
            return textField

        case .secret:
            return SecretInputView(label: field.label)

        case .select:
            let popUp = KeyKongPopUpButton()
            KeyKongTheme.style(popUp)
            popUp.setAccessibilityLabel(field.label)
            popUp.addItem(withTitle: "Select…")
            popUp.item(at: 0)?.isEnabled = false
            for option in field.options ?? [] {
                popUp.addItem(withTitle: option.label)
            }
            popUp.selectItem(at: 0)
            popUp.heightAnchor.constraint(equalToConstant: 36).isActive = true
            return popUp

        case .multiSelect:
            let buttons = (field.options ?? []).map { option in
                let button = KeyKongCheckboxButton(
                    checkboxWithTitle: option.label,
                    target: nil,
                    action: nil
                )
                button.identifier = NSUserInterfaceItemIdentifier(
                    "\(field.id).\(option.value)"
                )
                KeyKongTheme.styleCheckbox(button)
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
        if let secret = view as? SecretInputView {
            return [
                secret.secureTextField,
                secret.revealedTextField
            ]
        }
        if let stack = view as? NSStackView {
            return stack.arrangedSubviews
        }
        return [view]
    }

    private func configureTabOrder(_ views: [NSView]) {
        tabOrder = views
        for (current, next) in zip(views, views.dropFirst()) {
            current.nextKeyView = next
        }
        views.last?.nextKeyView = views.first
    }

    private func moveFocus(from control: NSControl, forward: Bool) {
        guard tabOrder.count > 1,
              let currentIndex = tabOrder.firstIndex(where: { $0 === control })
        else {
            return
        }

        for offset in 1..<tabOrder.count {
            let delta = forward ? offset : -offset
            let index = (currentIndex + delta + tabOrder.count)
                % tabOrder.count
            let destination = tabOrder[index]
            if destination.isHiddenOrHasHiddenAncestor {
                continue
            }
            if let control = destination as? NSControl, !control.isEnabled {
                continue
            }
            if window.makeFirstResponder(destination) {
                destination.scrollToVisible(destination.bounds)
                return
            }
        }
    }

    private func firstFocusableView() -> NSView? {
        inputViews.first.flatMap { focusableControls(in: $0).first }
    }

    private func markInvalid(_ fieldID: String) {
        errorLabels[fieldID]?.isHidden = false
    }

    @objc private func toggleDetails() {
        let isExpanded = detailsButton.state == .on
        if window.isVisible {
            formScrollView?.hasVerticalScroller = false
        }
        if isExpanded {
            detailsView.isHidden = false
        }
        detailsButton.image = NSImage(
            systemSymbolName: isExpanded ? "chevron.down" : "chevron.right",
            accessibilityDescription:
                isExpanded ? "Hide details" : "Show details"
        )
        resizeWindowForDetails(isExpanded: isExpanded)
    }

    private func resizeWindowForDetails(isExpanded: Bool) {
        let frame = window.frame
        let targetHeight: CGFloat

        if isExpanded {
            collapsedWindowHeight = collapsedWindowHeight ?? frame.height
            window.contentView?.layoutSubtreeIfNeeded()
            let desiredHeight = frame.height
                + detailsView.fittingSize.height
                + Self.bodySpacing
            if window.isVisible, let visibleFrame = window.screen?.visibleFrame {
                let availableHeight = frame.maxY - visibleFrame.minY
                targetHeight = min(
                    desiredHeight,
                    max(frame.height, availableHeight)
                )
            } else {
                targetHeight = desiredHeight
            }
        } else {
            targetHeight = collapsedWindowHeight ?? frame.height
            collapsedWindowHeight = nil
        }

        guard abs(targetHeight - frame.height) > 0.5 else {
            finishDetailsTransition(isExpanded: isExpanded)
            return
        }
        var targetFrame = frame
        targetFrame.size.height = targetHeight
        targetFrame.origin.y = frame.maxY - targetHeight
        if window.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().setFrame(targetFrame, display: true)
            } completionHandler: {
                Task { @MainActor [weak self] in
                    self?.finishDetailsTransition(isExpanded: isExpanded)
                }
            }
        } else {
            window.setFrame(targetFrame, display: true)
            finishDetailsTransition(isExpanded: isExpanded)
        }
    }

    private func finishDetailsTransition(isExpanded: Bool) {
        formScrollView?.hasVerticalScroller = true
        if isExpanded {
            detailsView.superview?.layoutSubtreeIfNeeded()
            detailsView.scrollToVisible(detailsView.bounds)
        } else {
            detailsView.isHidden = true
        }
    }

    private func finish(with outcome: PromptOutcome) {
        guard !didComplete else { return }
        didComplete = true
        clearInputs()
        onComplete(outcome)
    }

    private func clearInputs() {
        for (field, view) in zip(request.fields, inputViews) {
            switch field.type {
            case .text:
                (view as? NSTextField)?.stringValue = ""
            case .secret:
                (view as? SecretInputView)?.clear()
            case .select:
                (view as? NSPopUpButton)?.selectItem(at: 0)
            case .multiSelect:
                (view as? NSStackView)?.arrangedSubviews
                    .compactMap { $0 as? NSButton }
                    .forEach { $0.state = .off }
            }
        }
    }

    private static func describe(
        _ delivery: PromptDelivery,
        fields: [PromptField]
    ) -> String {
        switch delivery.operation {
        case .append:
            return "\(delivery.path) — append"
        case .insertLine:
            return "\(delivery.path) — insert before line \(delivery.line ?? 0)"
        case .setEnv:
            let field = delivery.field ?? ""
            let label = fields.first {
                $0.id.utf8.elementsEqual(field.utf8)
            }?.label ?? field
            return "\(delivery.path) — set \(delivery.key ?? "") from \(label)"
        }
    }
}

@MainActor
final class SecretInputView: NSView {
    let secureTextField = NSSecureTextField()
    let revealedTextField = NSTextField()
    let revealButton: NSButton = KeyKongPointerButton()

    var stringValue: String {
        revealButton.state == .on
            ? revealedTextField.stringValue
            : secureTextField.stringValue
    }

    var focusView: NSView {
        revealButton.state == .on ? revealedTextField : secureTextField
    }

    init(label: String) {
        super.init(frame: .zero)

        KeyKongTheme.style(secureTextField)
        KeyKongTheme.style(revealedTextField)
        let revealGutter: CGFloat = 42
        (secureTextField.cell as? KeyKongSecureTextFieldCell)?
            .trailingTextInset = revealGutter
        (revealedTextField.cell as? KeyKongTextFieldCell)?
            .trailingTextInset = revealGutter
        secureTextField.setAccessibilityLabel(label)
        revealedTextField.setAccessibilityLabel(label)
        revealedTextField.isHidden = true
        revealButton.target = self
        revealButton.action = #selector(toggleReveal)
        revealButton.setButtonType(.toggle)
        revealButton.bezelStyle = .inline
        revealButton.isBordered = false
        updateRevealButton(isRevealed: false)
        revealButton.imagePosition = .imageOnly
        revealButton.imageScaling = .scaleNone
        revealButton.alignment = .center
        revealButton.contentTintColor = KeyKongTheme.brass
        revealButton.toolTip = "Reveal secret"
        revealButton.setAccessibilityLabel("Reveal secret")
        revealButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        revealButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        revealedTextField.nextKeyView = revealButton

        let fieldContainer = NSView()
        for field in [secureTextField, revealedTextField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            fieldContainer.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor),
                field.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor),
                field.topAnchor.constraint(equalTo: fieldContainer.topAnchor),
                field.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor)
            ])
        }

        revealButton.translatesAutoresizingMaskIntoConstraints = false
        fieldContainer.addSubview(revealButton)
        fieldContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fieldContainer)

        NSLayoutConstraint.activate([
            fieldContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            fieldContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            fieldContainer.topAnchor.constraint(equalTo: topAnchor),
            fieldContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            fieldContainer.heightAnchor.constraint(equalToConstant: 36),
            revealButton.trailingAnchor.constraint(
                equalTo: fieldContainer.trailingAnchor,
                constant: -8
            ),
            revealButton.centerYAnchor.constraint(
                equalTo: fieldContainer.centerYAnchor
            )
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc private func toggleReveal() {
        if revealButton.state == .on {
            revealedTextField.stringValue = secureTextField.stringValue
            secureTextField.isHidden = true
            revealedTextField.isHidden = false
            updateRevealButton(isRevealed: true)
            window?.makeFirstResponder(revealedTextField)
        } else {
            secureTextField.stringValue = revealedTextField.stringValue
            revealedTextField.stringValue = ""
            revealedTextField.isHidden = true
            secureTextField.isHidden = false
            updateRevealButton(isRevealed: false)
            window?.makeFirstResponder(secureTextField)
        }
    }

    func clear() {
        secureTextField.stringValue = ""
        revealedTextField.stringValue = ""
        revealButton.state = .off
        updateRevealButton(isRevealed: false)
        revealedTextField.isHidden = true
        secureTextField.isHidden = false
    }

    private func updateRevealButton(isRevealed: Bool) {
        let description = isRevealed ? "Hide secret" : "Reveal secret"
        if isRevealed {
            revealButton.image = KeyKongTheme.symbol(
                "lock.open.fill",
                description: description
            )
        } else {
            revealButton.image = KeyKongTheme.shieldLockSymbol(
                description: description
            )
        }
        revealButton.toolTip = description
        revealButton.setAccessibilityLabel(description)
    }
}
