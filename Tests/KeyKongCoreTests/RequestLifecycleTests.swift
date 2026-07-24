import Foundation
import XCTest
@testable import KeyKongCore

final class RequestLifecycleTests: XCTestCase {
    func testCallerCanCompleteAllResponseFieldTypesThroughCLI() throws {
        let requestJSON = """
        {
          "id": "release-input",
          "title": "Prepare release",
          "fields": [
            {
              "id": "release_name",
              "label": "Release name",
              "type": "text"
            },
            {
              "id": "environment",
              "label": "Environment shown to the user",
              "type": "select",
              "options": [
                { "label": "Production display label", "value": "production" },
                { "label": "Staging display label", "value": "staging" }
              ]
            },
            {
              "id": "services",
              "label": "Services",
              "type": "multi_select",
              "options": [
                { "label": "API display label", "value": "api" },
                { "label": "Web display label", "value": "web" }
              ]
            }
          ]
        }
        """
        let adapter = RecordingAdapter(
            outcome: .submitted([
                "release_name": .text("2026.07"),
                "environment": .text("production"),
                "services": .selection(["api", "web"])
            ])
        )

        let execution = KeyKongCommand(adapter: adapter).run(
            arguments: ["request", "--request", "-"],
            standardInput: Data(requestJSON.utf8)
        )

        XCTAssertEqual(execution.exitCode, 0)
        XCTAssertEqual(execution.standardError, Data())
        XCTAssertEqual(
            String(decoding: execution.standardOutput, as: UTF8.self),
            #"{"status":"completed","values":{"environment":"production","release_name":"2026.07","services":["api","web"]}}"# + "\n"
        )
        XCTAssertEqual(adapter.requests.map(\.id), ["release-input"])
        XCTAssertEqual(adapter.requests.first?.title, "Prepare release")
        XCTAssertEqual(
            adapter.requests.first?.fields.map(\.id),
            ["release_name", "environment", "services"]
        )
        XCTAssertEqual(
            adapter.requests.first?.fields.map(\.type),
            [.text, .select, .multiSelect]
        )
    }

    func testInvalidResponseFieldRequestDoesNotOpenAdapter() {
        let requestJSON = """
        {
          "id": "release-input",
          "title": "Prepare release",
          "fields": [
            { "id": "environment", "label": "Environment", "type": "text" },
            { "id": "environment", "label": "Duplicate", "type": "text" }
          ]
        }
        """
        let adapter = RecordingAdapter(outcome: .submitted([:]))

        let execution = KeyKongCommand(adapter: adapter).run(
            arguments: ["request", "--request", "-"],
            standardInput: Data(requestJSON.utf8)
        )

        XCTAssertEqual(execution.exitCode, 1)
        XCTAssertEqual(adapter.requests, [])
        XCTAssertEqual(
            String(decoding: execution.standardOutput, as: UTF8.self),
            #"{"status":"failed","values":{}}"# + "\n"
        )
        XCTAssertEqual(
            String(decoding: execution.standardError, as: UTF8.self),
            "request failed: field IDs must be unique\n"
        )
    }

    func testAdapterCannotReturnDisplayLabelsAsSelectValues() {
        let requestJSON = """
        {
          "id": "release-input",
          "title": "Prepare release",
          "fields": [
            {
              "id": "environment",
              "label": "Environment",
              "type": "select",
              "options": [
                { "label": "Production display label", "value": "production" }
              ]
            }
          ]
        }
        """
        let adapter = RecordingAdapter(
            outcome: .submitted([
                "environment": .text("Production display label")
            ])
        )

        let execution = KeyKongCommand(adapter: adapter).run(
            arguments: ["request", "--request", "-"],
            standardInput: Data(requestJSON.utf8)
        )

        XCTAssertEqual(execution.exitCode, 1)
        XCTAssertEqual(
            String(decoding: execution.standardOutput, as: UTF8.self),
            #"{"status":"failed","values":{}}"# + "\n"
        )
        XCTAssertEqual(
            String(decoding: execution.standardError, as: UTF8.self),
            "request failed: adapter returned an invalid value for field 'environment'\n"
        )
    }
}

private final class RecordingAdapter: InputAdapter {
    private(set) var requests: [InputRequest] = []
    private let outcome: InputOutcome

    init(outcome: InputOutcome) {
        self.outcome = outcome
    }

    func collectInput(for request: InputRequest) -> InputOutcome {
        requests.append(request)
        return outcome
    }
}
