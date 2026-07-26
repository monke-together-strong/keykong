import AppKit
import XCTest
@testable import KeyKongPrompt

@MainActor
final class MacOSInputFormTests: XCTestCase {
    func testWindowUsesConventionalApplicationBehavior() {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Conventional window",
                fields: [
                    PromptField(id: "name", label: "Name", type: .text)
                ]
            )
        ) { _ in }

        XCTAssertTrue(form.window.styleMask.contains(.miniaturizable))
        XCTAssertEqual(form.window.level, .normal)
    }

    func testThemedHeaderAndFooterControlsStayCentered() throws {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Alignment",
                fields: [
                    PromptField(id: "token", label: "Token", type: .secret)
                ]
            )
        ) { _ in }
        let root = try XCTUnwrap(form.window.contentView)
        root.layoutSubtreeIfNeeded()
        let emblem = try XCTUnwrap(
            descendant("emblem", in: root)
        )
        let heading = try XCTUnwrap(
            descendant("heading", in: root)
        )
        let reassurance = try XCTUnwrap(
            descendant("reassurance", in: root)
        )
        let emblemFrame = emblem.convert(emblem.bounds, to: root)
        let textFrame = heading.convert(heading.bounds, to: root).union(
            reassurance.convert(reassurance.bounds, to: root)
        )
        let cancelFrame = form.cancelButton.convert(
            form.cancelButton.bounds,
            to: root
        )
        let sendFrame = form.sendButton.convert(
            form.sendButton.bounds,
            to: root
        )

        XCTAssertEqual(emblemFrame.midY, textFrame.midY, accuracy: 0.5)
        XCTAssertEqual(emblemFrame.width, 88, accuracy: 0.5)
        XCTAssertGreaterThan(textFrame.height, 40)
        XCTAssertEqual(cancelFrame.midY, sendFrame.midY, accuracy: 0.5)
        XCTAssertEqual(cancelFrame.height, sendFrame.height, accuracy: 0.5)
        XCTAssertTrue(KeyKongPointerCursor.isInstalled(on: form.detailsButton))
        XCTAssertTrue(
            KeyKongPointerCursor.isInstalled(
                on: try XCTUnwrap(
                    form.window.standardWindowButton(.closeButton)
                )
            )
        )
    }

    func testTextAndSecureCellsCenterTheirDrawingRectsVertically() throws {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Field alignment",
                fields: [
                    PromptField(id: "name", label: "Name", type: .text),
                    PromptField(id: "token", label: "Token", type: .secret)
                ]
            )
        ) { _ in }
        let textField = try XCTUnwrap(
            form.inputViews[0] as? NSTextField
        )
        let secret = try XCTUnwrap(
            form.inputViews[1] as? SecretInputView
        )
        let bounds = NSRect(x: 0, y: 0, width: 300, height: 36)

        for field in [
            textField,
            secret.secureTextField,
            secret.revealedTextField
        ] {
            let drawingRect = try XCTUnwrap(field.cell)
                .drawingRect(forBounds: bounds)
            XCTAssertEqual(drawingRect.midY, bounds.midY, accuracy: 0.5)
            XCTAssertTrue(field.isEditable)
            XCTAssertTrue(field.isSelectable)
            XCTAssertTrue(field.acceptsFirstResponder)
            XCTAssertNil(field.placeholderString)
        }
        XCTAssertTrue(
            secret.secureTextField.cell is KeyKongSecureTextFieldCell
        )
        XCTAssertEqual(textField.accessibilityLabel(), "Name")
        XCTAssertEqual(secret.secureTextField.accessibilityLabel(), "Token")
        XCTAssertEqual(secret.revealedTextField.accessibilityLabel(), "Token")
    }

    func testLongFormsStartAtTheTopWithUniformInputHeights() throws {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Long form",
                fields: [
                    PromptField(id: "name", label: "Name", type: .text),
                    PromptField(id: "token", label: "Token", type: .secret),
                    PromptField(
                        id: "environment",
                        label: "Environment",
                        type: .select,
                        options: [
                            PromptOption(label: "Production", value: "production")
                        ]
                    ),
                    PromptField(
                        id: "services",
                        label: "Services",
                        type: .multiSelect,
                        options: [
                            PromptOption(label: "API", value: "api"),
                            PromptOption(label: "Web", value: "web")
                        ]
                    )
                ]
            )
        ) { _ in }
        let root = try XCTUnwrap(form.window.contentView)
        root.layoutSubtreeIfNeeded()
        let scrollView = try XCTUnwrap(
            descendant("form-scroll", in: root) as? NSScrollView
        )
        let documentView = try XCTUnwrap(scrollView.documentView)

        XCTAssertTrue(documentView.isFlipped)
        XCTAssertEqual(scrollView.contentView.bounds.minY, 0, accuracy: 0.5)
        for view in form.inputViews.prefix(3) {
            XCTAssertEqual(view.frame.height, 36, accuracy: 0.5)
        }
    }

    func testExpandedDetailsScrollFullyIntoView() throws {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Details",
                fields: [
                    PromptField(id: "one", label: "One", type: .text),
                    PromptField(id: "two", label: "Two", type: .text),
                    PromptField(id: "three", label: "Three", type: .text),
                    PromptField(id: "four", label: "Four", type: .text)
                ],
                deliveries: [
                    PromptDelivery(path: "/tmp/one", operation: .append),
                    PromptDelivery(path: "/tmp/two", operation: .append)
                ]
            )
        ) { _ in }
        let root = try XCTUnwrap(form.window.contentView)
        root.layoutSubtreeIfNeeded()
        let scrollView = try XCTUnwrap(
            descendant("form-scroll", in: root) as? NSScrollView
        )

        form.detailsButton.performClick(nil)

        XCTAssertFalse(form.detailsView.isHidden)
        XCTAssertTrue(wait {
            root.layoutSubtreeIfNeeded()
            let detailsFrame = form.detailsView.convert(
                form.detailsView.bounds,
                to: scrollView.contentView
            )
            return scrollView.contentView.bounds.contains(detailsFrame)
        })
    }

    func testValidationScrollsTheFirstInvalidFieldIntoView() throws {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Validation",
                fields: [
                    PromptField(id: "one", label: "One", type: .text),
                    PromptField(id: "two", label: "Two", type: .text),
                    PromptField(id: "three", label: "Three", type: .text),
                    PromptField(id: "four", label: "Four", type: .text)
                ],
                deliveries: [
                    PromptDelivery(path: "/tmp/one", operation: .append),
                    PromptDelivery(path: "/tmp/two", operation: .append)
                ]
            )
        ) { _ in }
        let root = try XCTUnwrap(form.window.contentView)
        root.layoutSubtreeIfNeeded()
        let scrollView = try XCTUnwrap(
            descendant("form-scroll", in: root) as? NSScrollView
        )
        form.detailsButton.performClick(nil)
        XCTAssertTrue(wait {
            scrollView.contentView.bounds.maxY
                >= form.detailsView.convert(
                    form.detailsView.bounds,
                    to: scrollView.contentView
                ).maxY
        })

        form.sendButton.performClick(nil)

        let firstInput = form.inputViews[0]
        XCTAssertTrue(wait {
            root.layoutSubtreeIfNeeded()
            let inputFrame = firstInput.convert(
                firstInput.bounds,
                to: scrollView.contentView
            )
            return scrollView.contentView.bounds.intersects(inputFrame)
        })
    }

    func testReactivationRestoresTheExistingPromptWindow() {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Reactivate prompt",
                fields: [
                    PromptField(id: "name", label: "Name", type: .text)
                ]
            )
        ) { _ in }
        let applicationDelegate = PromptApplicationDelegate(
            window: form.window
        )
        form.window.orderFront(nil)
        form.window.miniaturize(nil)

        let shouldCreateWindow = applicationDelegate
            .applicationShouldHandleReopen(
                NSApplication.shared,
                hasVisibleWindows: false
            )

        XCTAssertFalse(shouldCreateWindow)
        XCTAssertTrue(wait {
            !form.window.isMiniaturized && form.window.isVisible
        })
        XCTAssertIdentical(applicationDelegate.window, form.window)
        form.window.orderOut(nil)
    }

    private func wait(
        timeout: TimeInterval = 1,
        until condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() {
                return true
            }
            RunLoop.current.run(
                mode: .default,
                before: Date().addingTimeInterval(0.01)
            )
        } while Date() < deadline
        return condition()
    }

    private func descendant(
        _ identifier: String,
        in view: NSView
    ) -> NSView? {
        if view.identifier?.rawValue == identifier {
            return view
        }
        return view.subviews.lazy.compactMap {
            self.descendant(identifier, in: $0)
        }.first
    }

    func testCancellationClearsEnteredValuesBeforeCompleting() throws {
        let request = PromptRequest(
            title: "Cancel input",
            fields: [
                PromptField(id: "name", label: "Name", type: .text),
                PromptField(id: "token", label: "Token", type: .secret)
            ],
            deliveries: [
                PromptDelivery(
                    path: "/tmp/existing.env",
                    operation: .append
                )
            ]
        )
        var outcome: PromptOutcome?
        let form = MacOSInputFormController(request: request) {
            outcome = $0
        }
        let nameInput = try XCTUnwrap(form.inputViews[0] as? NSTextField)
        let secretInput = try XCTUnwrap(form.inputViews[1] as? SecretInputView)
        nameInput.stringValue = "production"
        secretInput.secureTextField.stringValue = "highly-secret"
        secretInput.revealButton.performClick(nil)

        form.cancelButton.performClick(nil)

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(nameInput.stringValue, "")
        XCTAssertEqual(secretInput.secureTextField.stringValue, "")
        XCTAssertEqual(secretInput.revealedTextField.stringValue, "")
        XCTAssertEqual(secretInput.revealButton.state, .off)
    }

    func testSecretFieldIsMaskedCanBeRevealedAndDetailsStaySanitized() throws {
        let request = PromptRequest(
            title: "Add credentials",
            fields: [
                PromptField(id: "api_token", label: "API token", type: .secret)
            ],
            deliveries: [
                PromptDelivery(
                    path: "/tmp/existing.env",
                    operation: .append
                ),
                PromptDelivery(
                    path: "/tmp/settings",
                    operation: .insertLine,
                    line: 2
                ),
                PromptDelivery(
                    path: "/tmp/existing.env",
                    operation: .setEnv,
                    key: "API_TOKEN",
                    field: "api_token"
                )
            ]
        )
        var outcome: PromptOutcome?
        let form = MacOSInputFormController(request: request) {
            outcome = $0
        }

        let secretInput = try XCTUnwrap(form.inputViews.first as? SecretInputView)
        XCTAssertTrue(secretInput.revealButton is KeyKongPointerButton)
        let concealedIconSize = try XCTUnwrap(secretInput.revealButton.image).size
        XCTAssertFalse(secretInput.secureTextField.isHidden)
        XCTAssertTrue(secretInput.revealedTextField.isHidden)
        secretInput.secureTextField.stringValue = "highly-secret"

        secretInput.revealButton.performClick(nil)

        XCTAssertTrue(secretInput.secureTextField.isHidden)
        XCTAssertFalse(secretInput.revealedTextField.isHidden)
        XCTAssertEqual(secretInput.revealedTextField.stringValue, "highly-secret")
        XCTAssertEqual(secretInput.revealButton.image?.size, concealedIconSize)
        secretInput.revealButton.performClick(nil)
        XCTAssertFalse(secretInput.secureTextField.isHidden)
        XCTAssertTrue(secretInput.revealedTextField.isHidden)
        XCTAssertEqual(secretInput.secureTextField.stringValue, "highly-secret")
        XCTAssertTrue(form.detailsView.isHidden)
        XCTAssertEqual(
            form.deliveryDetails,
            [
                "/tmp/existing.env — append",
                "/tmp/settings — insert before line 2",
                "/tmp/existing.env — set API_TOKEN from API token"
            ]
        )
        XCTAssertFalse(form.deliveryDetails.joined().contains("TOKEN="))
        XCTAssertFalse(form.deliveryDetails.joined().contains("highly-secret"))

        form.detailsButton.performClick(nil)
        XCTAssertFalse(form.detailsView.isHidden)
        form.sendButton.performClick(nil)

        XCTAssertEqual(
            outcome,
            .submitted(["api_token": .text("highly-secret")])
        )
        XCTAssertEqual(secretInput.secureTextField.stringValue, "")
        XCTAssertEqual(secretInput.revealedTextField.stringValue, "")
        XCTAssertEqual(secretInput.revealButton.state, .off)
    }

    func testDetailsResolveCanonicallyEquivalentFieldIDsExactly() {
        let precomposed = "\u{AC00}"
        let decomposed = "\u{1100}\u{1161}"
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Exact field identity",
                fields: [
                    PromptField(id: precomposed, label: "Precomposed", type: .text),
                    PromptField(id: decomposed, label: "Decomposed", type: .text)
                ],
                deliveries: [
                    PromptDelivery(
                        path: "/tmp/existing.env",
                        operation: .setEnv,
                        key: "VALUE",
                        field: decomposed
                    )
                ]
            )
        ) { _ in }

        XCTAssertEqual(
            form.deliveryDetails,
            ["/tmp/existing.env — set VALUE from Decomposed"]
        )
    }

    func testFormPresentsAndSubmitsRequiredFieldsInRequestOrder() throws {
        let request = PromptRequest(
            title: "Prepare release",
            fields: [
                PromptField(id: "release_name", label: "Release name", type: .text),
                PromptField(
                    id: "environment",
                    label: "Environment shown to the user",
                    type: .select,
                    options: [
                        PromptOption(label: "Production display label", value: "production")
                    ]
                ),
                PromptField(
                    id: "services",
                    label: "Services",
                    type: .multiSelect,
                    options: [
                        PromptOption(label: "API display label", value: "api"),
                        PromptOption(label: "Web display label", value: "web")
                    ]
                )
            ]
        )
        var outcome: PromptOutcome?
        let form = MacOSInputFormController(request: request) {
            outcome = $0
        }

        XCTAssertEqual(form.window.title, "Prepare release")
        XCTAssertEqual(
            form.inputViews.map { $0.identifier?.rawValue },
            ["release_name", "environment", "services"]
        )
        XCTAssertEqual(form.sendButton.keyEquivalent, "\r")
        XCTAssertEqual(form.cancelButton.keyEquivalent, "\u{1b}")

        form.sendButton.performClick(nil)

        XCTAssertNil(outcome)
        XCTAssertFalse(try XCTUnwrap(form.errorLabels["release_name"]).isHidden)

        try XCTUnwrap(form.inputViews[0] as? NSTextField).stringValue = "2026.07"
        try XCTUnwrap(form.inputViews[1] as? NSPopUpButton).selectItem(at: 1)
        let serviceButtons = try XCTUnwrap(form.inputViews[2] as? NSStackView)
            .arrangedSubviews
            .compactMap { $0 as? NSButton }
        serviceButtons.forEach { $0.state = .on }

        form.sendButton.performClick(nil)

        XCTAssertEqual(
            outcome,
            .submitted([
                "release_name": .text("2026.07"),
                "environment": .text("production"),
                "services": .selection(["api", "web"])
            ])
        )
    }
}
