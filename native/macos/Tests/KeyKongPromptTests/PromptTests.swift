import AppKit
import XCTest
@testable import KeyKongPrompt

@MainActor
final class PromptTests: XCTestCase {
    func testFormPresentsAndSubmitsAllFieldKindsInOrder() throws {
        let request = PromptRequest(
            title: "Prepare release",
            fields: [
                PromptField(id: "name", label: "Name", type: .text),
                PromptField(id: "token", label: "Token", type: .secret),
                PromptField(
                    id: "environment",
                    label: "Environment",
                    type: .select,
                    options: [
                        PromptOption(label: "Production label", value: "production")
                    ]
                ),
                PromptField(
                    id: "services",
                    label: "Services",
                    type: .multiSelect,
                    options: [
                        PromptOption(label: "API label", value: "api"),
                        PromptOption(label: "Web label", value: "web")
                    ]
                )
            ]
        )
        var outcome: PromptOutcome?
        let form = MacOSInputFormController(request: request) { outcome = $0 }

        XCTAssertEqual(
            form.inputViews.map { $0.identifier?.rawValue },
            ["name", "token", "environment", "services"]
        )
        XCTAssertEqual(form.sendButton.keyEquivalent, "\r")
        XCTAssertEqual(form.cancelButton.keyEquivalent, "\u{1b}")
        form.show()
        form.window.makeFirstResponder(form.inputViews[2])
        form.sendButton.performClick(nil)
        XCTAssertNil(outcome)
        XCTAssertFalse(try XCTUnwrap(form.errorLabels["name"]).isHidden)
        let nameInput = try XCTUnwrap(
            form.inputViews[0] as? NSTextField
        )
        let fieldEditor = form.window.firstResponder as? NSTextView
        XCTAssertTrue(
            form.window.firstResponder === nameInput
                || fieldEditor?.delegate === nameInput
        )

        nameInput.stringValue = "v1"
        try XCTUnwrap(form.inputViews[1] as? SecretInputView)
            .secureTextField.stringValue = "secret"
        try XCTUnwrap(form.inputViews[2] as? NSPopUpButton).selectItem(at: 1)
        try XCTUnwrap(form.inputViews[3] as? NSStackView)
            .arrangedSubviews
            .compactMap { $0 as? NSButton }
            .forEach { $0.state = .on }
        form.sendButton.performClick(nil)

        XCTAssertEqual(
            outcome,
            .submitted([
                "name": .text("v1"),
                "token": .text("secret"),
                "environment": .text("production"),
                "services": .selection(["api", "web"])
            ])
        )
        form.window.orderOut(nil)
    }

    func testEnterSubmitsAndEscapeCancels() throws {
        let request = PromptRequest(
            title: "Keyboard",
            fields: [
                PromptField(id: "name", label: "Name", type: .text)
            ]
        )
        var submitted: PromptOutcome?
        let submitForm = MacOSInputFormController(request: request) {
            submitted = $0
        }
        try XCTUnwrap(submitForm.inputViews[0] as? NSTextField)
            .stringValue = "value"
        let enter = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: submitForm.window.windowNumber,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            )
        )

        XCTAssertTrue(submitForm.window.performKeyEquivalent(with: enter))
        XCTAssertEqual(submitted, .submitted(["name": .text("value")]))

        var cancelled: PromptOutcome?
        let cancelForm = MacOSInputFormController(request: request) {
            cancelled = $0
        }
        let escape = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: cancelForm.window.windowNumber,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: 53
            )
        )

        XCTAssertTrue(cancelForm.window.performKeyEquivalent(with: escape))
        XCTAssertEqual(cancelled, .cancelled)
    }

    func testSecretRevealCancellationAndDetailsAreSanitized() throws {
        let request = PromptRequest(
            title: "Credentials",
            fields: [
                PromptField(id: "token", label: "Token", type: .secret)
            ],
            deliveries: [
                PromptDelivery(path: "/tmp/.env", operation: .append),
                PromptDelivery(
                    path: "/tmp/settings",
                    operation: .insertLine,
                    line: 2
                )
            ]
        )
        var outcome: PromptOutcome?
        let form = MacOSInputFormController(request: request) { outcome = $0 }
        let secret = try XCTUnwrap(form.inputViews.first as? SecretInputView)
        secret.secureTextField.stringValue = "highly-secret"

        secret.revealButton.performClick(nil)
        XCTAssertEqual(secret.revealedTextField.stringValue, "highly-secret")
        secret.revealButton.performClick(nil)
        XCTAssertEqual(secret.secureTextField.stringValue, "highly-secret")
        XCTAssertEqual(
            form.deliveryDetails,
            [
                "/tmp/.env — append",
                "/tmp/settings — insert before line 2"
            ]
        )
        XCTAssertFalse(form.deliveryDetails.joined().contains("highly-secret"))

        form.cancelButton.performClick(nil)
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(secret.secureTextField.stringValue, "")
        XCTAssertEqual(secret.revealedTextField.stringValue, "")
    }

    func testOneShotProtocolDecodesPresentationAndEncodesSubmission() throws {
        let request = try JSONDecoder().decode(
            PromptRequest.self,
            from: Data(
                """
                {
                  "title": "Prompt",
                  "fields": [
                    {"id":"region","label":"Region","type":"select",
                     "options":[{"label":"Oregon","value":"us-west-2"}]}
                  ],
                  "deliveries": [
                    {"path":"/tmp/config","operation":"insert_line","line":2}
                  ]
                }
                """.utf8
            )
        )
        XCTAssertEqual(request.fields.first?.options?.first?.value, "us-west-2")
        XCTAssertEqual(request.deliveries.first?.line, 2)

        let encoded = try JSONEncoder().encode(
            PromptOutcome.submitted(["region": .text("us-west-2")])
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(object["status"] as? String, "submitted")
        XCTAssertEqual(
            (object["values"] as? [String: String])?["region"],
            "us-west-2"
        )
    }
}
