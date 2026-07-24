import Foundation

public struct CLIExecution: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: Data

    public init(exitCode: Int32, standardOutput: Data, standardError: Data) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public struct KeyKongCommand {
    private let adapter: any InputAdapter

    public init(adapter: any InputAdapter) {
        self.adapter = adapter
    }

    public func run(arguments: [String], standardInput: Data = Data()) -> CLIExecution {
        guard arguments.count == 3,
              arguments[0] == "request",
              arguments[1] == "--request"
        else {
            return failure("usage: key-kong request --request <file|->")
        }

        do {
            let requestData = try readRequest(arguments[2], standardInput: standardInput)
            let request = try JSONDecoder().decode(InputRequest.self, from: requestData)
            try RequestValidator.validate(request)

            switch adapter.collectInput(for: request) {
            case let .submitted(values):
                let validated = try SubmissionValidator.validate(values, for: request)
                try DeliveryExecutor.execute(request.deliveries, values: validated)
                let responseValues = validated.filter { fieldID, _ in
                    request.fields.first { $0.id == fieldID }?.type != .secret
                }
                return result(status: .completed, values: responseValues, exitCode: 0)
            case .cancelled:
                return result(status: .cancelled, values: [:], exitCode: 1)
            }
        } catch {
            return failure("request failed: \(error.localizedDescription)")
        }
    }

    private func readRequest(_ source: String, standardInput: Data) throws -> Data {
        if source == "-" {
            return standardInput
        }
        return try Data(contentsOf: URL(fileURLWithPath: source))
    }

    private func result(
        status: CommandStatus,
        values: [String: ResponseValue],
        exitCode: Int32
    ) -> CLIExecution {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let output = try! encoder.encode(CommandResult(status: status, values: values)) + Data([0x0A])
        return CLIExecution(
            exitCode: exitCode,
            standardOutput: output,
            standardError: Data()
        )
    }

    private func failure(_ diagnostic: String) -> CLIExecution {
        let output = result(status: .failed, values: [:], exitCode: 1).standardOutput
        return CLIExecution(
            exitCode: 1,
            standardOutput: output,
            standardError: Data((diagnostic + "\n").utf8)
        )
    }
}

private struct CommandResult: Encodable {
    let status: CommandStatus
    let values: [String: ResponseValue]
}

private enum CommandStatus: String, Encodable {
    case completed
    case failed
    case cancelled
}
