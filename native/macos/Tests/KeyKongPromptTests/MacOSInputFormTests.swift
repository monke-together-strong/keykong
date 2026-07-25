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
                )
            ]
        )
        var outcome: PromptOutcome?
        let form = MacOSInputFormController(request: request) {
            outcome = $0
        }

        let secretInput = try XCTUnwrap(form.inputViews.first as? SecretInputView)
        XCTAssertFalse(secretInput.secureTextField.isHidden)
        XCTAssertTrue(secretInput.revealedTextField.isHidden)
        secretInput.secureTextField.stringValue = "highly-secret"

        secretInput.revealButton.performClick(nil)

        XCTAssertTrue(secretInput.secureTextField.isHidden)
        XCTAssertFalse(secretInput.revealedTextField.isHidden)
        XCTAssertEqual(secretInput.revealedTextField.stringValue, "highly-secret")
        secretInput.revealButton.performClick(nil)
        XCTAssertFalse(secretInput.secureTextField.isHidden)
        XCTAssertTrue(secretInput.revealedTextField.isHidden)
        XCTAssertEqual(secretInput.secureTextField.stringValue, "highly-secret")
        XCTAssertTrue(form.detailsView.isHidden)
        XCTAssertEqual(
            form.deliveryDetails,
            [
                "/tmp/existing.env — append",
                "/tmp/settings — insert before line 2"
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
