import AppKit
import XCTest
@testable import KeyKongCore
@testable import KeyKongMacOS

@MainActor
final class MacOSInputFormTests: XCTestCase {
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
