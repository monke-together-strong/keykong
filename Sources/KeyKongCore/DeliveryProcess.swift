import Foundation

public protocol DeliveryExecuting {
    func execute(
        _ deliveries: [Delivery],
        values: [String: ResponseValue]
    ) throws -> [String]
}

public struct ChildProcessDeliveryExecutor: DeliveryExecuting {
    private let executableURL: URL

    public init(executableURL: URL) {
        self.executableURL = executableURL
    }

    public func execute(
        _ deliveries: [Delivery],
        values: [String: ResponseValue]
    ) throws -> [String] {
        let input = try JSONEncoder().encode(
            DeliveryWorkRequest(deliveries: deliveries, values: values)
        )
        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executableURL
        process.arguments = ["_delivery-worker"]
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        standardInput.fileHandleForWriting.write(input)
        try standardInput.fileHandleForWriting.close()

        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        _ = standardError.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationReason == .exit,
              process.terminationStatus == 0,
              let result = try? JSONDecoder().decode(
                DeliveryWorkResult.self,
                from: output
              )
        else {
            throw DeliveryProcessError.workerFailed
        }
        return result.failedDeliveryIDs
    }
}

public enum DeliveryWorker {
    public static func run(standardInput: Data) -> CLIExecution {
        do {
            let request = try JSONDecoder().decode(
                DeliveryWorkRequest.self,
                from: standardInput
            )
            let failedDeliveryIDs = DeliveryExecutor().execute(
                request.deliveries,
                values: request.values
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let output = try encoder.encode(
                DeliveryWorkResult(failedDeliveryIDs: failedDeliveryIDs)
            ) + Data([0x0A])
            return CLIExecution(
                exitCode: 0,
                standardOutput: output,
                standardError: Data()
            )
        } catch {
            return CLIExecution(
                exitCode: 1,
                standardOutput: Data(),
                standardError: Data("delivery worker failed\n".utf8)
            )
        }
    }
}

private struct DeliveryWorkRequest: Codable {
    let deliveries: [Delivery]
    let values: [String: ResponseValue]
}

private struct DeliveryWorkResult: Codable {
    let failedDeliveryIDs: [String]
}

private enum DeliveryProcessError: Error {
    case workerFailed
}
