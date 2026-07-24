import Darwin
import Foundation
import KeyKongCore
import KeyKongMacOS

let arguments = Array(CommandLine.arguments.dropFirst())
let execution: CLIExecution

if arguments == ["_delivery-worker"] {
    execution = DeliveryWorker.run(
        standardInput: FileHandle.standardInput.readDataToEndOfFile()
    )
} else {
    let standardInput = arguments.count == 3 && arguments[2] == "-"
        ? FileHandle.standardInput.readDataToEndOfFile()
        : Data()
    guard let executableURL = Bundle.main.executableURL else {
        FileHandle.standardError.write(Data("cannot locate key-kong executable\n".utf8))
        exit(1)
    }
    execution = KeyKongCommand(
        adapter: MacOSInputAdapter(),
        deliveryExecutor: ChildProcessDeliveryExecutor(
            executableURL: executableURL
        )
    ).run(
        arguments: arguments,
        standardInput: standardInput
    )
}

FileHandle.standardOutput.write(execution.standardOutput)
FileHandle.standardError.write(execution.standardError)
exit(execution.exitCode)
