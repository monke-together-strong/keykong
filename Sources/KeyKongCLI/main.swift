import Darwin
import Foundation
import KeyKongCore
import KeyKongMacOS

let arguments = Array(CommandLine.arguments.dropFirst())
let standardInput: Data

if arguments.count == 3, arguments[2] == "-" {
    standardInput = FileHandle.standardInput.readDataToEndOfFile()
} else {
    standardInput = Data()
}

let execution = KeyKongCommand(adapter: MacOSInputAdapter()).run(
    arguments: arguments,
    standardInput: standardInput
)

FileHandle.standardOutput.write(execution.standardOutput)
FileHandle.standardError.write(execution.standardError)
exit(execution.exitCode)
