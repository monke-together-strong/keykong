import Darwin
import Dispatch
import Foundation
import KeyKongPrompt

let brokerPID = getppid()
guard brokerPID > 1 else {
    exit(1)
}
let brokerMonitorQueue = DispatchQueue(
    label: "dev.key-kong.parent-process-monitor"
)
let brokerMonitor = DispatchSource.makeProcessSource(
    identifier: brokerPID,
    eventMask: .exit,
    queue: brokerMonitorQueue
)
brokerMonitor.setEventHandler {
    Darwin._exit(0)
}
brokerMonitor.resume()
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
