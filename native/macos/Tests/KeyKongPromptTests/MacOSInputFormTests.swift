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
        XCTAssertTrue(
            form.window.collectionBehavior.contains(.moveToActiveSpace)
        )
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
        XCTAssertTrue(
            KeyKongPointerCursor.isInstalled(
                on: try XCTUnwrap(
                    form.window.standardWindowButton(.closeButton)
                )
            )
        )
    }

    func testTwoFieldFormKeepsTheHeaderCloseToTheFirstField() throws {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Credentials needed",
                fields: [
                    PromptField(
                        id: "github_token",
                        label: "GitHub token",
                        type: .secret
                    ),
                    PromptField(
                        id: "deploy_token",
                        label: "Deploy token",
                        type: .secret
                    )
                ],
                deliveries: [
                    PromptDelivery(
                        path: "/tmp/output",
                        operation: .append
                    )
                ]
            )
        ) { _ in }
        let root = try XCTUnwrap(form.window.contentView)
        root.layoutSubtreeIfNeeded()
        let emblem = try XCTUnwrap(descendant("emblem", in: root))
        let heading = try XCTUnwrap(descendant("heading", in: root))
        let reassurance = try XCTUnwrap(descendant("reassurance", in: root))
        let firstField = form.inputViews[0]
        let firstRow = try XCTUnwrap(firstField.superview)
        let headerContentFrame = emblem.convert(emblem.bounds, to: root).union(
            heading.convert(heading.bounds, to: root)
        ).union(
            reassurance.convert(reassurance.bounds, to: root)
        )
        let firstRowFrame = firstRow.convert(firstRow.bounds, to: root)
        let gap = headerContentFrame.minY - firstRowFrame.maxY

        XCTAssertEqual(
            gap,
            20,
            accuracy: 0.5,
            "The header-to-form gap should match the compact themed mockup"
        )
        let detailsFrame = form.detailsButton.convert(
            form.detailsButton.bounds,
            to: root
        )
        let footerControlsFrame = form.cancelButton.convert(
            form.cancelButton.bounds,
            to: root
        ).union(
            form.sendButton.convert(form.sendButton.bounds, to: root)
        )
        let footerGap = detailsFrame.minY - footerControlsFrame.maxY

        XCTAssertEqual(
            footerGap,
            29,
            accuracy: 0.5,
            "Details should stay visually connected to the footer controls"
        )
    }

    func testInteractiveIconsUseThePointingHandCursor() {
        let button = CursorRecordingButton()

        button.resetCursorRects()

        XCTAssertTrue(button.recordedCursors.contains { cursor in
            cursor === NSCursor.pointingHand
        })
    }

    func testShieldLockMatchesTheUnlockedIconCanvasAndUsesExplicitColor() throws {
        let shield = try XCTUnwrap(
            KeyKongTheme.shieldLockSymbol(description: "Reveal secret")
        )
        let unlocked = try XCTUnwrap(
            KeyKongTheme.symbol(
                "lock.open.fill",
                description: "Hide secret"
            )
        )

        XCTAssertEqual(shield.size, unlocked.size)
        XCTAssertFalse(shield.isTemplate)
    }

    func testLongHeadingStaysWithinTheHeader() throws {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: String(repeating: "Localized credentials title ", count: 5),
                fields: [
                    PromptField(id: "token", label: "Token", type: .secret)
                ]
            )
        ) { _ in }
        let root = try XCTUnwrap(form.window.contentView)
        root.layoutSubtreeIfNeeded()
        let header = try XCTUnwrap(descendant("header", in: root))
        let heading = try XCTUnwrap(
            descendant("heading", in: root) as? NSTextField
        )

        XCTAssertEqual(heading.lineBreakMode, .byTruncatingTail)
        XCTAssertLessThanOrEqual(
            heading.alignmentRect(forFrame: heading.frame).maxX,
            header.bounds.maxX
        )
        XCTAssertGreaterThanOrEqual(header.frame.height, 88)
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
        let root = try XCTUnwrap(form.window.contentView)
        let bounds = NSRect(x: 0, y: 0, width: 300, height: 36)

        for field in [
            textField,
            secret.secureTextField,
            secret.revealedTextField
        ] {
            let drawingRect = try XCTUnwrap(field.cell)
                .drawingRect(forBounds: bounds)
            XCTAssertEqual(drawingRect.midY, bounds.midY, accuracy: 1)
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
        root.layoutSubtreeIfNeeded()
        let secureDrawingRect = try XCTUnwrap(secret.secureTextField.cell)
            .drawingRect(forBounds: secret.secureTextField.bounds)
        XCTAssertLessThan(
            secureDrawingRect.maxX,
            secret.revealButton.frame.minX
        )
    }

    func testKeyboardNavigationAndFeatureTogglingFollowFormConventions() throws {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Keyboard navigation",
                fields: [
                    PromptField(
                        id: "token",
                        label: "Deploy token",
                        type: .secret
                    ),
                    PromptField(
                        id: "environment",
                        label: "Environment",
                        type: .text
                    ),
                    PromptField(
                        id: "region",
                        label: "Region",
                        type: .select,
                        options: [
                            PromptOption(label: "Oregon", value: "us-west-2"),
                            PromptOption(label: "Virginia", value: "us-east-1")
                        ]
                    ),
                    PromptField(
                        id: "features",
                        label: "Features",
                        type: .multiSelect,
                        options: [
                            PromptOption(label: "Audit", value: "audit"),
                            PromptOption(label: "Alerts", value: "alerts")
                        ]
                    )
                ]
            )
        ) { _ in }
        let secret = try XCTUnwrap(
            form.inputViews[0] as? SecretInputView
        )
        let environment = try XCTUnwrap(
            form.inputViews[1] as? NSTextField
        )
        let region = try XCTUnwrap(
            form.inputViews[2] as? KeyKongPopUpButton
        )
        let features = try XCTUnwrap(
            form.inputViews[3] as? NSStackView
        ).arrangedSubviews.compactMap { $0 as? KeyKongCheckboxButton }
        let firstFeature = try XCTUnwrap(features.first)
        let secondFeature = try XCTUnwrap(features.last)

        XCTAssertFalse(form.window.autorecalculatesKeyViewLoop)
        XCTAssertTrue(
            secret.secureTextField.nextKeyView
                === secret.revealedTextField
        )
        XCTAssertTrue(secret.revealedTextField.nextKeyView === environment)
        XCTAssertFalse(secret.revealButton === secret.secureTextField.nextKeyView)
        XCTAssertFalse(secret.revealButton === secret.revealedTextField.nextKeyView)
        XCTAssertTrue(environment.nextKeyView === region)
        XCTAssertTrue(region.nextKeyView === firstFeature)
        XCTAssertTrue(firstFeature.nextKeyView === secondFeature)
        XCTAssertTrue(region.acceptsFirstResponder)
        XCTAssertTrue(features.allSatisfy(\.acceptsFirstResponder))

        XCTAssertTrue(form.window.makeFirstResponder(secret.secureTextField))
        form.window.sendEvent(keyDown(keyCode: 48, characters: "\t"))
        XCTAssertTrue(focusedControl(in: form.window) === environment)

        form.window.sendEvent(
            keyDown(
                keyCode: 48,
                characters: "\t",
                modifiers: .shift
            )
        )
        XCTAssertTrue(
            focusedControl(in: form.window) === secret.secureTextField
        )

        form.window.sendEvent(keyDown(keyCode: 48, characters: "\t"))
        XCTAssertTrue(focusedControl(in: form.window) === environment)
        form.window.sendEvent(keyDown(keyCode: 48, characters: "\t"))
        XCTAssertTrue(focusedControl(in: form.window) === region)

        form.window.sendEvent(
            keyDown(
                keyCode: 48,
                characters: "\t",
                modifiers: .shift
            )
        )
        XCTAssertTrue(focusedControl(in: form.window) === environment)

        form.window.sendEvent(keyDown(keyCode: 48, characters: "\t"))
        form.window.sendEvent(keyDown(keyCode: 48, characters: "\t"))
        XCTAssertTrue(focusedControl(in: form.window) === firstFeature)

        XCTAssertTrue(
            form.window.performKeyEquivalent(
                with: keyDown(keyCode: 36, characters: "\r")
            )
        )
        XCTAssertEqual(firstFeature.state, .on)

        form.window.sendEvent(keyDown(keyCode: 48, characters: "\t"))
        XCTAssertTrue(focusedControl(in: form.window) === secondFeature)
        form.window.sendEvent(
            keyDown(
                keyCode: 48,
                characters: "\t",
                modifiers: .shift
            )
        )
        XCTAssertTrue(focusedControl(in: form.window) === firstFeature)
    }

    func testEnterOpensTheFocusedRegionMenu() {
        let window = KeyKongFormWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: .titled,
            backing: .buffered,
            defer: false
        )
        let region = ClickRecordingPopUpButton()
        window.contentView = region

        XCTAssertTrue(window.makeFirstResponder(region))
        XCTAssertTrue(
            window.performKeyEquivalent(
                with: keyDown(keyCode: 36, characters: "\r")
            )
        )
        XCTAssertEqual(region.clickCount, 1)
    }

    func testEnterTogglesTheFocusedDetailsControl() {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Keyboard details",
                fields: [
                    PromptField(
                        id: "environment",
                        label: "Environment",
                        type: .text
                    )
                ],
                deliveries: [
                    PromptDelivery(path: "/tmp/output", operation: .append)
                ]
            )
        ) { _ in }

        XCTAssertTrue(form.window.makeFirstResponder(form.detailsButton))
        XCTAssertTrue(
            form.window.performKeyEquivalent(
                with: keyDown(keyCode: 36, characters: "\r")
            )
        )
        XCTAssertEqual(form.detailsButton.state, .on)
        XCTAssertFalse(form.detailsView.isHidden)

        XCTAssertTrue(
            form.window.performKeyEquivalent(
                with: keyDown(keyCode: 36, characters: "\r")
            )
        )
        XCTAssertEqual(form.detailsButton.state, .off)
        XCTAssertTrue(wait { form.detailsView.isHidden })
    }

    func testShiftEnterSubmitsWithoutFocusingFooterButtons() throws {
        var outcome: PromptOutcome?
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Keyboard submission",
                fields: [
                    PromptField(
                        id: "environment",
                        label: "Environment",
                        type: .text
                    )
                ],
                deliveries: [
                    PromptDelivery(path: "/tmp/output", operation: .append)
                ]
            )
        ) {
            outcome = $0
        }
        let environment = try XCTUnwrap(
            form.inputViews.first as? NSTextField
        )
        environment.stringValue = "production"

        XCTAssertTrue(environment.nextKeyView === form.detailsButton)
        XCTAssertTrue(form.detailsButton.nextKeyView === environment)
        XCTAssertFalse(environment.nextKeyView === form.cancelButton)
        XCTAssertFalse(environment.nextKeyView === form.sendButton)
        XCTAssertTrue(form.window.makeFirstResponder(form.detailsButton))

        form.window.sendEvent(keyDown(keyCode: 48, characters: "\t"))
        XCTAssertTrue(focusedControl(in: form.window) === environment)
        form.window.sendEvent(
            keyDown(
                keyCode: 48,
                characters: "\t",
                modifiers: .shift
            )
        )
        XCTAssertTrue(focusedControl(in: form.window) === form.detailsButton)

        XCTAssertTrue(
            form.window.performKeyEquivalent(
                with: keyDown(
                    keyCode: 36,
                    characters: "\r",
                    modifiers: .shift
                )
            )
        )
        XCTAssertEqual(
            outcome,
            .submitted(["environment": .text("production")])
        )
    }

    func testEnterSubmitsFromATextField() throws {
        var outcome: PromptOutcome?
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Text field submission",
                fields: [
                    PromptField(
                        id: "environment",
                        label: "Environment",
                        type: .text
                    )
                ]
            )
        ) {
            outcome = $0
        }
        let environment = try XCTUnwrap(
            form.inputViews.first as? NSTextField
        )
        environment.stringValue = "production"

        XCTAssertTrue(form.window.makeFirstResponder(environment))
        XCTAssertTrue(
            form.window.performKeyEquivalent(
                with: keyDown(keyCode: 36, characters: "\r")
            )
        )
        XCTAssertEqual(
            outcome,
            .submitted(["environment": .text("production")])
        )
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
                    ),
                    PromptField(id: "region", label: "Region", type: .text),
                    PromptField(id: "project", label: "Project", type: .text)
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
        XCTAssertGreaterThan(
            documentView.frame.height,
            scrollView.contentView.bounds.height
        )
        XCTAssertGreaterThanOrEqual(
            documentView.frame.height,
            try XCTUnwrap(documentView.subviews.first).fittingSize.height
        )
        for view in form.inputViews.prefix(3) {
            XCTAssertEqual(view.frame.height, 36, accuracy: 0.5)
        }
    }

    func testCompactFormsShowAllOptionsWithoutScrolling() throws {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Deploy",
                fields: [
                    PromptField(
                        id: "environment",
                        label: "Environment",
                        type: .text
                    ),
                    PromptField(
                        id: "region",
                        label: "Region",
                        type: .select,
                        options: [
                            PromptOption(label: "Oregon", value: "us-west-2")
                        ]
                    ),
                    PromptField(
                        id: "features",
                        label: "Features",
                        type: .multiSelect,
                        options: [
                            PromptOption(label: "Audit", value: "audit"),
                            PromptOption(label: "Alerts", value: "alerts")
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
        let featureButtons = try XCTUnwrap(
            form.inputViews[2] as? NSStackView
        ).arrangedSubviews

        XCTAssertEqual(scrollView.contentView.bounds.minY, 0, accuracy: 0.5)
        for button in featureButtons {
            XCTAssertTrue(
                scrollView.contentView.bounds.contains(
                    button.convert(button.bounds, to: scrollView.contentView)
                ),
                "\(button.identifier?.rawValue ?? "Feature") should be visible"
            )
        }
    }

    func testFormControlsLeaveRoomForFocusRingsAndRoundedEdges() throws {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Deploy",
                fields: [
                    PromptField(
                        id: "environment",
                        label: "Environment",
                        type: .text
                    ),
                    PromptField(
                        id: "region",
                        label: "Region",
                        type: .select,
                        options: [
                            PromptOption(label: "Oregon", value: "us-west-2")
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
        let renderingBounds = scrollView.contentView.bounds.insetBy(
            dx: 4,
            dy: 0
        )

        for input in form.inputViews {
            let frame = input.convert(
                input.bounds,
                to: scrollView.contentView
            )
            XCTAssertTrue(renderingBounds.contains(frame))
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
                    PromptField(id: "four", label: "Four", type: .text),
                    PromptField(id: "five", label: "Five", type: .text),
                    PromptField(id: "six", label: "Six", type: .text)
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

    func testDetailsExpansionGrowsTheWindowAndCollapseRestoresIt() {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Expandable details",
                fields: [
                    PromptField(id: "token", label: "Token", type: .secret)
                ],
                deliveries: [
                    PromptDelivery(path: "/tmp/one", operation: .append),
                    PromptDelivery(path: "/tmp/two", operation: .append)
                ]
            )
        ) { _ in }
        let collapsedFrame = form.window.frame

        form.detailsButton.performClick(nil)

        XCTAssertTrue(wait {
            form.window.frame.height > collapsedFrame.height
        })
        XCTAssertEqual(
            form.window.frame.maxY,
            collapsedFrame.maxY,
            accuracy: 0.5
        )

        form.detailsButton.performClick(nil)

        XCTAssertTrue(wait {
            abs(form.window.frame.height - collapsedFrame.height) < 0.5
        })
        XCTAssertEqual(
            form.window.frame.maxY,
            collapsedFrame.maxY,
            accuracy: 0.5
        )
    }

    func testDetailsCollapseKeepsTheDetailsControlVisible() throws {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Credentials needed",
                fields: [
                    PromptField(
                        id: "github_token",
                        label: "GitHub token",
                        type: .secret
                    ),
                    PromptField(
                        id: "deploy_token",
                        label: "Deploy token",
                        type: .secret
                    ),
                    PromptField(
                        id: "environment",
                        label: "Environment",
                        type: .text
                    ),
                    PromptField(
                        id: "region",
                        label: "Region",
                        type: .select,
                        options: [
                            PromptOption(label: "Oregon", value: "us-west-2")
                        ]
                    ),
                    PromptField(
                        id: "features",
                        label: "Features",
                        type: .multiSelect,
                        options: [
                            PromptOption(label: "Audit", value: "audit"),
                            PromptOption(label: "Alerts", value: "alerts"),
                            PromptOption(label: "Previews", value: "previews")
                        ]
                    )
                ],
                deliveries: [
                    PromptDelivery(path: "/tmp/one", operation: .append),
                    PromptDelivery(path: "/tmp/two", operation: .append)
                ]
            )
        ) { _ in }
        let root = try XCTUnwrap(form.window.contentView)
        let scrollView = try XCTUnwrap(
            descendant("form-scroll", in: root) as? NSScrollView
        )
        form.window.center()
        form.window.orderFront(nil)
        root.layoutSubtreeIfNeeded()
        form.detailsButton.scrollToVisible(form.detailsButton.bounds)
        let collapsedScrollOffset = scrollView.contentView.bounds.origin.y

        form.detailsButton.performClick(nil)
        XCTAssertTrue(wait {
            root.layoutSubtreeIfNeeded()
            return !form.detailsView.isHidden
                && scrollView.contentView.bounds.contains(
                    form.detailsView.convert(
                        form.detailsView.bounds,
                        to: scrollView.contentView
                    )
                )
        })

        form.detailsButton.performClick(nil)

        XCTAssertTrue(wait {
            root.layoutSubtreeIfNeeded()
            return form.detailsView.isHidden
                && scrollView.contentView.bounds.contains(
                    form.detailsButton.convert(
                        form.detailsButton.bounds,
                        to: scrollView.contentView
                    )
                )
        })
        XCTAssertEqual(
            scrollView.contentView.bounds.origin.y,
            collapsedScrollOffset,
            accuracy: 0.5
        )
        form.window.orderOut(nil)
    }

    func testDetailsExpansionSuppressesTheTransientScroller() throws {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Smooth details",
                fields: [
                    PromptField(id: "token", label: "Token", type: .secret)
                ],
                deliveries: [
                    PromptDelivery(path: "/tmp/one", operation: .append),
                    PromptDelivery(path: "/tmp/two", operation: .append)
                ]
            )
        ) { _ in }
        let root = try XCTUnwrap(form.window.contentView)
        let scrollView = try XCTUnwrap(
            descendant("form-scroll", in: root) as? NSScrollView
        )
        form.window.orderFront(nil)
        let scrollerStates = BoolRecorder()
        let observation = scrollView.observe(
            \.hasVerticalScroller,
            options: [.new]
        ) { _, change in
            if let state = change.newValue {
                scrollerStates.append(state)
            }
        }

        form.detailsButton.performClick(nil)

        XCTAssertEqual(scrollerStates.values.first, false)
        XCTAssertTrue(wait {
            scrollerStates.values.last == true
        })
        withExtendedLifetime(observation) {}
        form.window.orderOut(nil)
    }

    func testValidationScrollsTheFirstInvalidFieldIntoView() throws {
        let form = MacOSInputFormController(
            request: PromptRequest(
                title: "Validation",
                fields: [
                    PromptField(id: "one", label: "One", type: .text),
                    PromptField(id: "two", label: "Two", type: .text),
                    PromptField(id: "three", label: "Three", type: .text),
                    PromptField(id: "four", label: "Four", type: .text),
                    PromptField(id: "five", label: "Five", type: .text),
                    PromptField(id: "six", label: "Six", type: .text)
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
            let detailsFrame = form.detailsView.convert(
                form.detailsView.bounds,
                to: scrollView.contentView
            )
            return scrollView.contentView.bounds.origin.y > 0
                && scrollView.contentView.bounds.contains(detailsFrame)
        })
        let scrolledOffset = scrollView.contentView.bounds.origin.y

        form.sendButton.performClick(nil)

        let firstInput = form.inputViews[0]
        XCTAssertTrue(wait {
            root.layoutSubtreeIfNeeded()
            let target = firstInput.superview ?? firstInput
            let targetFrame = target.convert(
                target.bounds,
                to: scrollView.contentView
            )
            return scrollView.contentView.bounds.contains(targetFrame)
                && scrollView.contentView.bounds.origin.y < scrolledOffset
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

    private func focusedControl(in window: NSWindow) -> NSControl? {
        if let control = window.firstResponder as? NSControl {
            return control
        }
        return (window.firstResponder as? NSTextView)?.delegate as? NSControl
    }

    private func keyDown(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
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
                    operation: .append,
                    template: "TOKEN={{ api_token }}\n"
                ),
                PromptDelivery(
                    path: "/tmp/settings",
                    operation: .insertLine,
                    line: 2,
                    template: "credentials={{ api_token }}"
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
        form.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(secretInput.revealButton is KeyKongPointerButton)
        XCTAssertEqual(
            secretInput.revealButton.image?.accessibilityDescription,
            "Reveal secret"
        )
        let concealedButtonFrame = secretInput.revealButton.frame
        XCTAssertFalse(secretInput.secureTextField.isHidden)
        XCTAssertTrue(secretInput.revealedTextField.isHidden)
        secretInput.secureTextField.stringValue = "highly-secret"

        secretInput.revealButton.performClick(nil)

        XCTAssertTrue(secretInput.secureTextField.isHidden)
        XCTAssertFalse(secretInput.revealedTextField.isHidden)
        XCTAssertEqual(secretInput.revealedTextField.stringValue, "highly-secret")
        form.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(secretInput.revealButton.frame, concealedButtonFrame)
        secretInput.revealButton.performClick(nil)
        XCTAssertFalse(secretInput.secureTextField.isHidden)
        XCTAssertTrue(secretInput.revealedTextField.isHidden)
        XCTAssertEqual(secretInput.secureTextField.stringValue, "highly-secret")
        XCTAssertEqual(secretInput.revealedTextField.stringValue, "")
        XCTAssertTrue(form.detailsView.isHidden)
        XCTAssertEqual(
            form.deliveryDetails,
            [
                """
                /tmp/existing.env — append
                Template:
                TOKEN={{ api_token }}

                """,
                """
                /tmp/settings — insert before line 2
                Template:
                credentials={{ api_token }}
                """,
                "/tmp/existing.env — set API_TOKEN from API token"
            ]
        )
        XCTAssertFalse(form.deliveryDetails.joined().contains("highly-secret"))
        let appendTemplate = try XCTUnwrap(
            descendant(
                "delivery-0-template",
                in: try XCTUnwrap(form.window.contentView)
            ) as? NSTextField
        )
        XCTAssertEqual(appendTemplate.stringValue, "TOKEN={{ api_token }}\n")
        XCTAssertTrue(appendTemplate.isSelectable)

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
        XCTAssertEqual(form.sendButton.keyEquivalentModifierMask, .shift)
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

@MainActor
private final class ClickRecordingPopUpButton: KeyKongPopUpButton {
    private(set) var clickCount = 0

    override func performClick(_ sender: Any?) {
        clickCount += 1
    }
}

@MainActor
private final class CursorRecordingButton: KeyKongPointerButton {
    private(set) var recordedCursors: [NSCursor] = []

    override func addCursorRect(_ rect: NSRect, cursor object: NSCursor) {
        recordedCursors.append(object)
        super.addCursorRect(rect, cursor: object)
    }
}

private final class BoolRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Bool] = []

    var values: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return recordedValues
    }

    func append(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        recordedValues.append(value)
    }
}
