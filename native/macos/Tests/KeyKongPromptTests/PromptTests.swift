import AppKit
import Darwin
import Foundation
import XCTest
@testable import KeyKongPrompt

final class PromptTests: XCTestCase {
    @MainActor
    func testParentProcessMonitorUsesAQueueSafeExitHandler() throws {
        let parent = Process()
        parent.executableURL = URL(fileURLWithPath: "/bin/sleep")
        parent.arguments = ["30"]
        try parent.run()
        defer {
            stop(parent)
        }
        let callback = DispatchSemaphore(value: 0)
        let monitor = try XCTUnwrap(
            ParentProcessMonitor(
                processID: parent.processIdentifier,
                onExit: { @Sendable in
                    callback.signal()
                }
            )
        )
        parent.terminate()

        XCTAssertEqual(
            callback.wait(timeout: .now() + 2),
            .success
        )
        parent.waitUntilExit()
        monitor.cancel()
    }

    @MainActor
    func testMainMenuExposesStandardEditingCommands() throws {
        let menu = PromptRunner.makeMainMenu()
        let applicationMenu = try XCTUnwrap(menu.items.first?.submenu)
        let quitItem = try XCTUnwrap(applicationMenu.items.first)
        XCTAssertEqual(quitItem.title, "Quit KeyKong")
        XCTAssertEqual(quitItem.action, #selector(NSApplication.terminate(_:)))
        XCTAssertEqual(quitItem.keyEquivalent, "q")
        XCTAssertEqual(quitItem.keyEquivalentModifierMask, [.command])
        XCTAssertNil(quitItem.target)

        let editMenu = try XCTUnwrap(menu.item(withTitle: "Edit")?.submenu)
        let items = editMenu.items.filter { !$0.isSeparatorItem }

        XCTAssertEqual(
            items.map(\.title),
            ["Undo", "Redo", "Cut", "Copy", "Paste", "Select All"]
        )
        XCTAssertEqual(
            items.compactMap(\.action).map(NSStringFromSelector),
            ["undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:"]
        )
        XCTAssertEqual(
            items.map(\.keyEquivalent),
            ["z", "z", "x", "c", "v", "a"]
        )
        XCTAssertEqual(
            items.map(\.keyEquivalentModifierMask),
            [
                [.command],
                [.command, .shift],
                [.command],
                [.command],
                [.command],
                [.command]
            ]
        )
        XCTAssertTrue(items.allSatisfy { $0.target == nil })
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
                    {"path":"/tmp/config","operation":"insert_line","line":2,
                     "template":"TOKEN={{ token }}\\n"},
                    {"path":"/tmp/.env","operation":"set_env",
                     "key":"API_TOKEN","field":"token"}
                  ]
                }
                """.utf8
            )
        )

        XCTAssertEqual(request.fields.first?.options?.first?.value, "us-west-2")
        XCTAssertEqual(request.fields.last?.type, .secret)
        XCTAssertEqual(request.deliveries.first?.line, 2)
        XCTAssertEqual(
            request.deliveries.first?.template,
            "TOKEN={{ token }}\n"
        )
        XCTAssertEqual(request.deliveries.last?.operation, .setEnv)
        XCTAssertEqual(request.deliveries.last?.key, "API_TOKEN")
        XCTAssertEqual(request.deliveries.last?.field, "token")

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
