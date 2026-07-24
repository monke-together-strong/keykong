import Darwin
import Foundation
import KeyKongPrompt

guard let brokerMonitor = ParentProcessMonitor(
    processID: getppid(),
    onExit: { @Sendable in
        Darwin._exit(0)
    }
) else {
    exit(1)
}
defer {
    brokerMonitor.cancel()
}

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let request = try JSONDecoder().decode(PromptRequest.self, from: input)
    let outcome = PromptRunner.run(request)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(outcome) + Data([0x0A]))
} catch {
    FileHandle.standardError.write(Data("native prompt failed\n".utf8))
    exit(1)
}
