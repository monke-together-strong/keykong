import CoreGraphics
import Darwin
import Foundation
import XCTest
@testable import KeyKongPrompt

final class PromptTests: XCTestCase {
    func testRealHelperReadsOneRequestAndWritesOneResponse() throws {
        let productsDirectory = Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent()
        let helper = productsDirectory.appendingPathComponent("key-kong-prompt")
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = helper
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        try process.run()
        defer {
            stop(process)
        }
        input.fileHandleForWriting.write(
            Data(
                """
                {
                  "title": "Contract check",
                  "fields": [
                    {"id":"name","label":"Name","type":"text"}
                  ],
                  "deliveries": []
                }
                """.utf8
            )
        )
        try input.fileHandleForWriting.close()
        guard waitForWindow(ownedBy: process.processIdentifier) else {
            XCTFail("the real helper did not present its AppKit window")
            return
        }
        postEscape(to: process.processIdentifier)
        guard waitForExit(process) else {
            XCTFail("the real helper did not exit after cancellation")
            return
        }

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(
            output.fileHandleForReading.readDataToEndOfFile(),
            Data(#"{"status":"cancelled"}"#.utf8) + Data([0x0A])
        )
        XCTAssertEqual(
            errors.fileHandleForReading.readDataToEndOfFile(),
            Data()
        )
    }

    private func waitForWindow(ownedBy processID: pid_t) -> Bool {
        let timeout = Date().addingTimeInterval(5)
        repeat {
            let windows = CGWindowListCopyWindowInfo(
                .optionAll,
                kCGNullWindowID
            ) as? [[String: Any]]
            if windows?.contains(where: {
                $0[kCGWindowOwnerPID as String] as? pid_t == processID
            }) == true {
                return true
            }
            Thread.sleep(forTimeInterval: 0.01)
        } while Date() < timeout
        return false
    }

    private func postEscape(to processID: pid_t) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: 53,
            keyDown: true
        )
        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: 53,
            keyDown: false
        )
        keyDown?.postToPid(processID)
        keyUp?.postToPid(processID)
    }

    private func waitForExit(
        _ process: Process,
        timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        return !process.isRunning
    }

    private func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        if waitForExit(process, timeout: 1) {
            return
        }
        kill(process.processIdentifier, SIGKILL)
        _ = waitForExit(process, timeout: 1)
    }

    func testProtocolRepresentsStableOptionsSecretsAndSanitizedDeliveries() throws {
        let request = try JSONDecoder().decode(
            PromptRequest.self,
            from: Data(
                """
                {
                  "title": "Prompt",
                  "fields": [
                    {"id":"region","label":"Region","type":"select",
                     "options":[{"label":"Oregon","value":"us-west-2"}]},
                    {"id":"token","label":"Token","type":"secret"}
                  ],
                  "deliveries": [
                    {"path":"/tmp/config","operation":"insert_line","line":2}
                  ]
                }
                """.utf8
            )
        )

        XCTAssertEqual(request.fields.first?.options?.first?.value, "us-west-2")
        XCTAssertEqual(request.fields.last?.type, .secret)
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
