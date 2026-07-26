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

private func descendants(of element: AXUIElement) -> [AXUIElement] {
    guard let children = attribute(
        kAXChildrenAttribute as CFString,
        of: element,
        as: [AXUIElement].self
    ) else {
        return []
    }
    return children + children.flatMap(descendants)
}

private func postKey(
    _ virtualKey: CGKeyCode,
    modifiers: CGEventFlags = [],
    to processID: pid_t
) {
    let source = CGEventSource(stateID: .combinedSessionState)
    let keyDown = CGEvent(
        keyboardEventSource: source,
        virtualKey: virtualKey,
        keyDown: true
    )
    keyDown?.flags = modifiers
    let keyUp = CGEvent(
        keyboardEventSource: source,
        virtualKey: virtualKey,
        keyDown: false
    )
    keyUp?.flags = modifiers
    keyDown?.postToPid(processID)
    keyUp?.postToPid(processID)
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
}

private enum Key {
    static let a: CGKeyCode = 0
    static let z: CGKeyCode = 6
    static let x: CGKeyCode = 7
    static let c: CGKeyCode = 8
    static let v: CGKeyCode = 9
}

private func focus(_ element: AXUIElement, named name: String) throws {
    guard AXUIElementSetAttributeValue(
        element,
        kAXFocusedAttribute as CFString,
        kCFBooleanTrue
    ) == .success else {
        try fail("packaged Prompt Adapter \(name) could not be focused")
    }
    guard wait(until: {
        attribute(
            kAXFocusedAttribute as CFString,
            of: element,
            as: Bool.self
        ) == true
    }) else {
        try fail("packaged Prompt Adapter \(name) did not become focused")
    }
}

private func value(of element: AXUIElement) -> String? {
    attribute(
        kAXValueAttribute as CFString,
        of: element,
        as: String.self
    )
}

private func expectValue(
    _ expected: String,
    in element: AXUIElement,
    failure: String
) throws {
    guard wait(timeout: 1, until: { value(of: element) == expected }) else {
        try fail(
            "\(failure) (value: \((value(of: element) ?? "").debugDescription))"
        )
    }
}

private func expectValueLength(
    _ expected: Int,
    in element: AXUIElement,
    failure: String
) throws {
    guard wait(timeout: 1, until: {
        value(of: element)?.count == expected
    }) else {
        try fail(failure)
    }
}

private func setClipboard(_ value: String, on pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    pasteboard.setString(value, forType: .string)
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
            {"id":"name","label":"Name","type":"text"},
            {"id":"token","label":"Token","type":"secret"}
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

guard runningApplication.activate(options: [.activateAllWindows]) else {
    try fail("packaged Prompt Adapter could not be activated")
}
guard wait(until: { runningApplication.isActive }) else {
    try fail("packaged Prompt Adapter did not become active")
}

let pasteboard = NSPasteboard.general
let originalPasteboardItems: [NSPasteboardItem] =
    pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
        let copy = NSPasteboardItem()
        for type in item.types {
            if let data = item.data(forType: type) {
                copy.setData(data, forType: type)
            }
        }
        return copy
    } ?? []
defer {
    pasteboard.clearContents()
    pasteboard.writeObjects(originalPasteboardItems as [NSPasteboardWriting])
}
let pastedValue = "keykong-original"
setClipboard(pastedValue, on: pasteboard)

guard let textField = descendants(of: originalWindow).first(where: {
    attribute(kAXRoleAttribute as CFString, of: $0, as: String.self)
        == (kAXTextFieldRole as String)
}) else {
    try fail("packaged Prompt Adapter has no accessible text field")
}
try focus(textField, named: "text field")
postKey(Key.v, modifiers: .maskCommand, to: process.processIdentifier)
try expectValue(
    pastedValue,
    in: textField,
    failure: "Paste did not update the packaged text field"
)

let replacementValue = "keykong-replacement"
setClipboard(replacementValue, on: pasteboard)
postKey(Key.a, modifiers: .maskCommand, to: process.processIdentifier)
postKey(Key.v, modifiers: .maskCommand, to: process.processIdentifier)
try expectValue(
    replacementValue,
    in: textField,
    failure: "Select All did not replace the packaged text field"
)

postKey(Key.z, modifiers: .maskCommand, to: process.processIdentifier)
try expectValue(
    "",
    in: textField,
    failure: "Undo did not revert the packaged text field"
)

postKey(
    Key.z,
    modifiers: [.maskCommand, .maskShift],
    to: process.processIdentifier
)
try expectValue(
    replacementValue,
    in: textField,
    failure: "Redo did not restore the packaged text field"
)

let clipboardGuard = "keykong-clipboard-guard"
setClipboard(clipboardGuard, on: pasteboard)
postKey(Key.a, modifiers: .maskCommand, to: process.processIdentifier)
postKey(Key.c, modifiers: .maskCommand, to: process.processIdentifier)
guard wait(timeout: 1, until: {
    pasteboard.string(forType: .string) == replacementValue
}) else {
    try fail("Copy did not write the selected packaged text field")
}

postKey(Key.x, modifiers: .maskCommand, to: process.processIdentifier)
guard wait(timeout: 1, until: {
    value(of: textField) == ""
        && pasteboard.string(forType: .string) == replacementValue
}) else {
    try fail("Cut did not remove and copy the selected packaged text field")
}

postKey(Key.z, modifiers: .maskCommand, to: process.processIdentifier)
try expectValue(
    replacementValue,
    in: textField,
    failure: "Undo did not restore the cut packaged text field"
)

guard let secureField = descendants(of: originalWindow).first(where: {
    attribute(kAXSubroleAttribute as CFString, of: $0, as: String.self)
        == (kAXSecureTextFieldSubrole as String)
}) else {
    try fail("packaged Prompt Adapter has no accessible secure field")
}
try focus(secureField, named: "secure field")

let secureOriginal = "keykong-secret-one"
setClipboard(secureOriginal, on: pasteboard)
postKey(Key.v, modifiers: .maskCommand, to: process.processIdentifier)
try expectValueLength(
    secureOriginal.count,
    in: secureField,
    failure: "Paste did not update the packaged secure field"
)

let secureReplacement = "keykong-secret-replacement"
setClipboard(secureReplacement, on: pasteboard)
postKey(Key.a, modifiers: .maskCommand, to: process.processIdentifier)
postKey(Key.v, modifiers: .maskCommand, to: process.processIdentifier)
try expectValueLength(
    secureReplacement.count,
    in: secureField,
    failure: "Select All did not replace the packaged secure field"
)

postKey(Key.z, modifiers: .maskCommand, to: process.processIdentifier)
try expectValue(
    "",
    in: secureField,
    failure: "Undo did not revert the packaged secure field"
)
postKey(
    Key.z,
    modifiers: [.maskCommand, .maskShift],
    to: process.processIdentifier
)
try expectValueLength(
    secureReplacement.count,
    in: secureField,
    failure: "Redo did not restore the packaged secure field"
)

setClipboard(clipboardGuard, on: pasteboard)
postKey(Key.a, modifiers: .maskCommand, to: process.processIdentifier)
postKey(Key.c, modifiers: .maskCommand, to: process.processIdentifier)
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
guard pasteboard.string(forType: .string) == clipboardGuard else {
    try fail("Copy exposed the packaged secure field")
}

postKey(Key.x, modifiers: .maskCommand, to: process.processIdentifier)
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
guard pasteboard.string(forType: .string) == clipboardGuard,
      value(of: secureField)?.count == secureReplacement.count else {
    try fail("Cut exposed or removed the packaged secure field")
}

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
guard wait(until: { runningApplication.isActive }) else {
    try fail("packaged Prompt Adapter did not become active after reactivation")
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

guard let sendButton = descendants(of: originalWindow).first(where: {
    attribute(kAXRoleAttribute as CFString, of: $0, as: String.self)
        == (kAXButtonRole as String)
        && attribute(
            kAXTitleAttribute as CFString,
            of: $0,
            as: String.self
        ) == "Send"
}) else {
    try fail("packaged Prompt Adapter has no accessible Send button")
}
guard AXUIElementPerformAction(
    sendButton,
    kAXPressAction as CFString
) == .success else {
    try fail("packaged Prompt Adapter Send button could not be pressed")
}
guard wait(until: { !process.isRunning }) else {
    try fail("packaged Prompt Adapter did not exit after submission")
}
guard process.terminationStatus == 0 else {
    try fail("packaged Prompt Adapter exited unsuccessfully")
}
let response = output.fileHandleForReading.readDataToEndOfFile()
let expectedResponse = Data(
    """
    {"status":"submitted","values":{"name":"keykong-replacement","token":"keykong-secret-replacement"}}
    """.utf8
) + Data([0x0A])
guard response == expectedResponse else {
    try fail(
        "packaged Prompt Adapter returned an unexpected response: "
            + (String(data: response, encoding: .utf8) ?? "<non-UTF-8>")
    )
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
