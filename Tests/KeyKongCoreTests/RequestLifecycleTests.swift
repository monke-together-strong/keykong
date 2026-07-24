import Foundation
import XCTest
@testable import KeyKongCore

final class RequestLifecycleTests: XCTestCase {
    func testCancellationReturnsJSONAndNonzeroExit() {
        let adapter = RecordingAdapter(outcome: .cancelled)

        let execution = KeyKongCommand(adapter: adapter).run(
            arguments: ["request", "--request", "-"],
            standardInput: Data(responseOnlyRequestJSON.utf8)
        )

        XCTAssertEqual(execution.exitCode, 1)
        XCTAssertEqual(execution.standardError, Data())
        XCTAssertEqual(
            String(decoding: execution.standardOutput, as: UTF8.self),
            #"{"status":"cancelled","values":{}}"# + "\n"
        )
    }

    func testExpiryReturnsJSONAndNonzeroExit() {
        let adapter = RecordingAdapter(outcome: .expired)

        let execution = KeyKongCommand(adapter: adapter).run(
            arguments: ["request", "--request", "-"],
            standardInput: Data(responseOnlyRequestJSON.utf8)
        )

        XCTAssertEqual(execution.exitCode, 1)
        XCTAssertEqual(execution.standardError, Data())
        XCTAssertEqual(
            String(decoding: execution.standardOutput, as: UTF8.self),
            #"{"status":"expired","values":{}}"# + "\n"
        )
    }

    func testPartialDeliveryReturnsFailedIDsAndNonSecretValues() throws {
        let successfulTarget = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let failedTarget = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: successfulTarget)
        try Data().write(to: failedTarget)
        defer {
            try? FileManager.default.removeItem(at: successfulTarget)
            try? FileManager.default.removeItem(at: failedTarget)
        }

        let requestJSON = twoDeliveryRequestJSON(
            firstTarget: successfulTarget,
            secondTarget: failedTarget
        )
        let adapter = RemovingAdapter(
            target: failedTarget,
            outcome: .submitted([
                "environment": .text("production"),
                "api_token": .text("highly-secret")
            ])
        )

        let execution = KeyKongCommand(adapter: adapter).run(
            arguments: ["request", "--request", "-"],
            standardInput: Data(requestJSON.utf8)
        )
        let combinedOutput = execution.standardOutput + execution.standardError

        XCTAssertEqual(execution.exitCode, 1)
        XCTAssertEqual(
            String(decoding: execution.standardOutput, as: UTF8.self),
            #"{"failedDeliveries":["write-token"],"status":"partial","values":{"environment":"production"}}"# + "\n"
        )
        XCTAssertEqual(
            try String(contentsOf: successfulTarget, encoding: .utf8),
            "production\n"
        )
        XCTAssertFalse(String(decoding: combinedOutput, as: UTF8.self).contains("highly-secret"))
    }

    func testChildProcessDeliveryReturnsOnlyFailedIDs() throws {
        let worker = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let firstTarget = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let secondTarget = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let workerScript = """
        #!/bin/sh
        [ "$1" = "_delivery-worker" ] || exit 2
        payload=$(cat)
        case "$payload" in
          *highly-secret*) ;;
          *) exit 3 ;;
        esac
        printf '{"failedDeliveryIDs":["write-token"]}\\n'
        """
        try Data(workerScript.utf8).write(to: worker)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: worker.path
        )
        try Data().write(to: firstTarget)
        try Data().write(to: secondTarget)
        defer {
            try? FileManager.default.removeItem(at: worker)
            try? FileManager.default.removeItem(at: firstTarget)
            try? FileManager.default.removeItem(at: secondTarget)
        }

        let requestJSON = twoDeliveryRequestJSON(
            firstTarget: firstTarget,
            secondTarget: secondTarget
        )
        let adapter = RecordingAdapter(
            outcome: .submitted([
                "environment": .text("production"),
                "api_token": .text("highly-secret")
            ])
        )
        let command = KeyKongCommand(
            adapter: adapter,
            deliveryExecutor: ChildProcessDeliveryExecutor(executableURL: worker)
        )

        let execution = command.run(
            arguments: ["request", "--request", "-"],
            standardInput: Data(requestJSON.utf8)
        )
        let combinedOutput = execution.standardOutput + execution.standardError

        XCTAssertEqual(execution.exitCode, 1)
        XCTAssertEqual(
            String(decoding: execution.standardOutput, as: UTF8.self),
            #"{"failedDeliveries":["write-token"],"status":"partial","values":{"environment":"production"}}"# + "\n"
        )
        XCTAssertFalse(String(decoding: combinedOutput, as: UTF8.self).contains("highly-secret"))
    }

    func testTargetLinesAreValidatedInDeliveryOrder() throws {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("first\n".utf8).write(to: target)
        defer { try? FileManager.default.removeItem(at: target) }

        let requestJSON = """
        {
          "id": "ordered-deliveries",
          "title": "Add credentials",
          "fields": [
            { "id": "api_token", "label": "API token", "type": "secret" }
          ],
          "deliveries": [
            {
              "id": "append-token",
              "path": "\(target.path)",
              "operation": "append",
              "template": "TOKEN={{ api_token }}\\n"
            },
            {
              "id": "insert-token",
              "path": "\(target.path)",
              "operation": "insert_line",
              "line": 3,
              "template": "SECOND={{ api_token }}"
            }
          ]
        }
        """
        let adapter = RecordingAdapter(
            outcome: .submitted(["api_token": .text("highly-secret")])
        )

        let execution = KeyKongCommand(adapter: adapter).run(
            arguments: ["request", "--request", "-"],
            standardInput: Data(requestJSON.utf8)
        )

        XCTAssertEqual(execution.exitCode, 0)
        XCTAssertEqual(
            try String(contentsOf: target, encoding: .utf8),
            "first\nTOKEN=highly-secret\nSECOND=highly-secret\n"
        )
    }

    func testNonRegularDeliveryTargetDoesNotOpenAdapter() {
        let requestJSON = """
        {
          "id": "credential-input",
          "title": "Add credentials",
          "fields": [
            { "id": "api_token", "label": "API token", "type": "secret" }
          ],
          "deliveries": [
            {
              "id": "append-token",
              "path": "/dev/null",
              "operation": "append",
              "template": "{{ api_token }}"
            }
          ]
        }
        """
        let adapter = RecordingAdapter(
            outcome: .submitted(["api_token": .text("highly-secret")])
        )

        let execution = KeyKongCommand(adapter: adapter).run(
            arguments: ["request", "--request", "-"],
            standardInput: Data(requestJSON.utf8)
        )

        XCTAssertEqual(execution.exitCode, 1)
        XCTAssertEqual(adapter.requests, [])
    }

    func testSecretsAreDeliveredInRequestOrderWithoutReturningToCaller() throws {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("first\nlast\n".utf8).write(to: target)
        defer { try? FileManager.default.removeItem(at: target) }

        let requestJSON = """
        {
          "id": "credential-input",
          "title": "Add credentials",
          "fields": [
            { "id": "account", "label": "Account", "type": "text" },
            { "id": "api_token", "label": "API token", "type": "secret" }
          ],
          "deliveries": [
            {
              "id": "insert-token",
              "path": "\(target.path)",
              "operation": "insert_line",
              "line": 2,
              "template": "TOKEN={{ api_token }}"
            },
            {
              "id": "append-account",
              "path": "\(target.path)",
              "operation": "append",
              "template": "ACCOUNT={{ account }}\\n"
            }
          ]
        }
        """
        let adapter = RecordingAdapter(
            outcome: .submitted([
                "account": .text("production"),
                "api_token": .text("highly-secret")
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
            #"{"status":"completed","values":{"account":"production"}}"# + "\n"
        )
        XCTAssertEqual(
            try String(contentsOf: target, encoding: .utf8),
            "first\nTOKEN=highly-secret\nlast\nACCOUNT=production\n"
        )
        XCTAssertFalse(
            String(decoding: execution.standardOutput, as: UTF8.self)
                .contains("highly-secret")
        )
    }

    func testInvalidDeliveryRequestDoesNotOpenAdapterOrModifyTargets() throws {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("only line\n".utf8).write(to: target)
        defer { try? FileManager.default.removeItem(at: target) }

        let requestJSON = """
        {
          "id": "credential-input",
          "title": "Add credentials",
          "fields": [
            { "id": "api_token", "label": "API token", "type": "secret" }
          ],
          "deliveries": [
            {
              "id": "insert-token",
              "path": "\(target.path)",
              "operation": "insert_line",
              "line": 3,
              "template": "TOKEN={{ api_token }}"
            }
          ]
        }
        """
        let adapter = RecordingAdapter(
            outcome: .submitted(["api_token": .text("highly-secret")])
        )

        let execution = KeyKongCommand(adapter: adapter).run(
            arguments: ["request", "--request", "-"],
            standardInput: Data(requestJSON.utf8)
        )

        XCTAssertEqual(execution.exitCode, 1)
        XCTAssertEqual(adapter.requests, [])
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "only line\n")
        XCTAssertFalse(
            String(decoding: execution.standardError, as: UTF8.self)
                .contains("highly-secret")
        )
    }

    func testSecretDeliveryFailureDoesNotLeakSubmittedValue() throws {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: target)
        defer { try? FileManager.default.removeItem(at: target) }

        let requestJSON = """
        {
          "id": "credential-input",
          "title": "Add credentials",
          "fields": [
            { "id": "api_token", "label": "API token", "type": "secret" }
          ],
          "deliveries": [
            {
              "id": "append-token",
              "path": "\(target.path)",
              "operation": "append",
              "template": "{{ api_token }}"
            }
          ]
        }
        """
        let adapter = RemovingAdapter(
            target: target,
            outcome: .submitted(["api_token": .text("highly-secret")])
        )

        let execution = KeyKongCommand(adapter: adapter).run(
            arguments: ["request", "--request", "-"],
            standardInput: Data(requestJSON.utf8)
        )
        let combinedOutput = execution.standardOutput + execution.standardError

        XCTAssertEqual(execution.exitCode, 1)
        XCTAssertEqual(
            String(decoding: execution.standardOutput, as: UTF8.self),
            #"{"status":"failed","values":{}}"# + "\n"
        )
        XCTAssertEqual(
            String(decoding: execution.standardError, as: UTF8.self),
            "all deliveries failed\n"
        )
        XCTAssertFalse(String(decoding: combinedOutput, as: UTF8.self).contains("highly-secret"))
    }

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

private let responseOnlyRequestJSON = """
{
  "id": "release-input",
  "title": "Prepare release",
  "fields": [
    { "id": "environment", "label": "Environment", "type": "text" }
  ]
}
"""

private func twoDeliveryRequestJSON(
    firstTarget: URL,
    secondTarget: URL
) -> String {
    """
    {
      "id": "partial-delivery",
      "title": "Add credentials",
      "fields": [
        { "id": "environment", "label": "Environment", "type": "text" },
        { "id": "api_token", "label": "API token", "type": "secret" }
      ],
      "deliveries": [
        {
          "id": "write-environment",
          "path": "\(firstTarget.path)",
          "operation": "append",
          "template": "{{ environment }}\\n"
        },
        {
          "id": "write-token",
          "path": "\(secondTarget.path)",
          "operation": "append",
          "template": "{{ api_token }}"
        }
      ]
    }
    """
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

private final class RemovingAdapter: InputAdapter {
    private let target: URL
    private let outcome: InputOutcome

    init(target: URL, outcome: InputOutcome) {
        self.target = target
        self.outcome = outcome
    }

    func collectInput(for request: InputRequest) -> InputOutcome {
        try? FileManager.default.removeItem(at: target)
        return outcome
    }
}
