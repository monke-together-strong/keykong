import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

private let bundleIdentifier = "dev.keykong.prompt"
private let expectedName = "KeyKong"

private struct SmokeFailure: Error, CustomStringConvertible {
    let description: String
}

private struct SmokeSkip: Error {}

private func fail(_ message: String) throws -> Never {
    throw SmokeFailure(description: message)
}

private func wait(
    timeout: TimeInterval = 5,
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

private func attribute<T>(
    _ name: CFString,
    of element: AXUIElement,
    as type: T.Type
) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
        return nil
    }
    return value as? T
}

private func windows(of application: AXUIElement) -> [AXUIElement] {
    var count: CFIndex = 0
    guard AXUIElementGetAttributeValueCount(
        application,
        kAXWindowsAttribute as CFString,
        &count
    ) == .success else {
        return []
    }
    var values: CFArray?
    guard AXUIElementCopyAttributeValues(
        application,
        kAXWindowsAttribute as CFString,
        0,
        count,
        &values
    ) == .success else {
        return []
    }
    return values as? [AXUIElement] ?? []
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

private func runSmoke() throws {
guard CommandLine.arguments.count == 2 else {
    try fail("usage: smoke-macos-ui.swift <helper>")
}

let helper = URL(fileURLWithPath: CommandLine.arguments[1])
let process = Process()
let input = Pipe()
let output = Pipe()
let errors = Pipe()
process.executableURL = helper
process.standardInput = input
process.standardOutput = output
process.standardError = errors

do {
    try process.run()
} catch {
    try fail("packaged Prompt Adapter could not be launched: \(error)")
}
defer {
    if process.isRunning {
        process.terminate()
        if !wait(timeout: 1, until: { !process.isRunning }) {
            kill(process.processIdentifier, SIGKILL)
            _ = wait(timeout: 1, until: { !process.isRunning })
        }
    }
}

input.fileHandleForWriting.write(
    Data(
        """
        {
          "title": "Packaged UI smoke",
          "fields": [
            {"id":"name","label":"Name","type":"text"}
          ],
          "deliveries": []
        }
        """.utf8
    )
)
try input.fileHandleForWriting.close()

var runningApplication: NSRunningApplication?
guard wait(until: {
    runningApplication = NSRunningApplication(
        processIdentifier: process.processIdentifier
    )
    return runningApplication?.bundleIdentifier == bundleIdentifier
}) else {
    try fail("packaged Prompt Adapter did not acquire its bundle identity")
}
guard let runningApplication else {
    try fail("packaged Prompt Adapter is not a running application")
}
guard runningApplication.localizedName == expectedName else {
    try fail("packaged Prompt Adapter has an unexpected display name")
}
guard runningApplication.activationPolicy == .regular else {
    try fail("packaged Prompt Adapter does not use regular activation policy")
}

guard AXIsProcessTrusted() else {
    throw SmokeSkip()
}

let application = AXUIElementCreateApplication(process.processIdentifier)
guard wait(until: { windows(of: application).count == 1 }) else {
    let windowInfo = CGWindowListCopyWindowInfo(
        .optionAll,
        kCGNullWindowID
    ) as? [[String: Any]]
    let coreGraphicsCount = windowInfo?.filter {
        $0[kCGWindowOwnerPID as String] as? pid_t
            == process.processIdentifier
    }.count ?? 0
    try fail(
        "packaged Prompt Adapter window mismatch "
            + "(AX: \(windows(of: application).count), "
            + "CoreGraphics: \(coreGraphicsCount))"
    )
}
let originalWindow = windows(of: application)[0]

guard AXUIElementSetAttributeValue(
    originalWindow,
    kAXMinimizedAttribute as CFString,
    kCFBooleanTrue
) == .success else {
    try fail("packaged Prompt Adapter window could not be miniaturized")
}
guard wait(until: {
    attribute(
        kAXMinimizedAttribute as CFString,
        of: originalWindow,
        as: Bool.self
    ) == true
}) else {
    try fail("packaged Prompt Adapter window did not miniaturize")
}

if let finder = NSRunningApplication
    .runningApplications(withBundleIdentifier: "com.apple.finder")
    .first {
    _ = finder.activate(options: [.activateAllWindows])
    _ = wait(timeout: 1, until: { !runningApplication.isActive })
}
guard runningApplication.activate(options: [.activateAllWindows]) else {
    try fail("packaged Prompt Adapter could not be reactivated")
}
guard wait(until: {
    attribute(
        kAXMinimizedAttribute as CFString,
        of: originalWindow,
        as: Bool.self
    ) == false
}) else {
    try fail("reactivation did not restore the packaged prompt")
}

let reactivatedWindows = windows(of: application)
guard reactivatedWindows.count == 1,
      CFEqual(originalWindow, reactivatedWindows[0]) else {
    try fail("reactivation created a second prompt window")
}

postEscape(to: process.processIdentifier)
guard wait(until: { !process.isRunning }) else {
    try fail("packaged Prompt Adapter did not exit after cancellation")
}
guard process.terminationStatus == 0 else {
    try fail("packaged Prompt Adapter exited unsuccessfully")
}
guard output.fileHandleForReading.readDataToEndOfFile()
    == Data(#"{"status":"cancelled"}"#.utf8) + Data([0x0A]) else {
    try fail("packaged Prompt Adapter returned an unexpected response")
}
guard errors.fileHandleForReading.readDataToEndOfFile().isEmpty else {
    try fail("packaged Prompt Adapter wrote to stderr")
}
}

do {
    try runSmoke()
} catch is SmokeSkip {
    print("Skipping interactive Prompt Adapter smoke: Accessibility is unavailable")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
