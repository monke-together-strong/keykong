import AppKit
import XCTest
@testable import KeyKongCore
@testable import KeyKongMacOS

@MainActor
final class MacOSInputFormTests: XCTestCase {
    func testCancellationClearsEnteredValuesBeforeCompleting() throws {
        let request = InputRequest(
            id: "cancel-input",
            title: "Cancel input",
            fields: [
                InputField(id: "name", label: "Name", type: .text),
                InputField(id: "token", label: "Token", type: .secret)
            ],
            deliveries: [
                Delivery(
                    id: "write-token",
                    path: "/tmp/existing.env",
                    operation: .append,
                    template: "{{ token }}"
                )
            ]
        )
        var outcome: InputOutcome?
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

    func testExpirationClearsEnteredValuesAndCompletesAsExpired() throws {
        let request = InputRequest(
            id: "expiring-input",
            title: "Expiring input",
            fields: [
                InputField(id: "token", label: "Token", type: .secret)
            ],
            deliveries: [
                Delivery(
                    id: "write-token",
                    path: "/tmp/existing.env",
                    operation: .append,
                    template: "{{ token }}"
                )
            ]
        )
        var outcome: InputOutcome?
        let form = MacOSInputFormController(
            request: request,
            expirationInterval: 0.01
        ) {
            outcome = $0
        }
        let secretInput = try XCTUnwrap(form.inputViews.first as? SecretInputView)
        secretInput.secureTextField.stringValue = "highly-secret"

        form.show()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(outcome, .expired)
        XCTAssertEqual(secretInput.secureTextField.stringValue, "")
        XCTAssertEqual(secretInput.revealedTextField.stringValue, "")
        form.window.orderOut(nil)
    }

    func testSecretFieldIsMaskedCanBeRevealedAndDetailsStaySanitized() throws {
        let request = InputRequest(
            id: "credential-input",
            title: "Add credentials",
            fields: [
                InputField(id: "api_token", label: "API token", type: .secret)
            ],
            deliveries: [
                Delivery(
                    id: "append-token",
                    path: "/tmp/existing.env",
                    operation: .append,
                    template: "TOKEN={{ api_token }}"
                ),
                Delivery(
                    id: "insert-token",
                    path: "/tmp/settings",
                    operation: .insertLine,
                    line: 2,
                    template: "{{ api_token }}"
                )
            ]
        )
        var outcome: InputOutcome?
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
    }

    func testFormPresentsAndSubmitsRequiredFieldsInRequestOrder() throws {
        let request = InputRequest(
            id: "release-input",
            title: "Prepare release",
            fields: [
                InputField(id: "release_name", label: "Release name", type: .text),
                InputField(
                    id: "environment",
                    label: "Environment shown to the user",
                    type: .select,
                    options: [
                        InputOption(label: "Production display label", value: "production")
                    ]
                ),
                InputField(
                    id: "services",
                    label: "Services",
                    type: .multiSelect,
                    options: [
                        InputOption(label: "API display label", value: "api"),
                        InputOption(label: "Web display label", value: "web")
                    ]
                )
            ]
        )
        var outcome: InputOutcome?
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
