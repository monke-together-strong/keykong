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
    private let deliveryExecutor: any DeliveryExecuting

    public init(adapter: any InputAdapter) {
        self.adapter = adapter
        self.deliveryExecutor = DeliveryExecutor()
    }

    public init(adapter: any InputAdapter, deliveryExecutor: any DeliveryExecuting) {
        self.adapter = adapter
        self.deliveryExecutor = deliveryExecutor
    }

    public func run(
        arguments: [String],
        standardInput: Data = Data(),
        deadline: RequestDeadline = RequestDeadline(timeout: 10 * 60)
    ) -> CLIExecution {
        guard arguments.count == 3,
              arguments[0] == "request",
              arguments[1] == "--request"
        else {
            return failure("usage: key-kong request --request <file|->")
        }

        do {
            try requireTimeRemaining(deadline)
            let requestData = try readRequest(arguments[2], standardInput: standardInput)
            try requireTimeRemaining(deadline)
            let request = try JSONDecoder().decode(InputRequest.self, from: requestData)
            let expectedTargets = try RequestValidator.validate(request)
            try requireTimeRemaining(deadline)

            switch adapter.collectInput(for: request, deadline: deadline) {
            case let .submitted(values):
                try requireTimeRemaining(deadline)
                let validated = try SubmissionValidator.validate(values, for: request)
                let responseValues = validated.filter { fieldID, _ in
                    request.fields.first { $0.id == fieldID }?.type != .secret
                }
                let failedDeliveryIDs: [String]
                do {
                    failedDeliveryIDs = try deliveryExecutor.execute(
                        request.deliveries,
                        values: validated,
                        expectedTargets: expectedTargets,
                        deadline: deadline
                    )
                    try requireTimeRemaining(deadline)
                } catch RequestTimeoutError.expired {
                    return result(status: .expired, values: [:])
                } catch {
                    return result(
                        status: .failed,
                        values: responseValues,
                        diagnostic: "delivery worker failed"
                    )
                }

                if failedDeliveryIDs.isEmpty {
                    return result(status: .completed, values: responseValues, exitCode: 0)
                }
                if failedDeliveryIDs.count == request.deliveries.count {
                    return result(
                        status: .failed,
                        values: responseValues,
                        diagnostic: "all deliveries failed"
                    )
                }
                return result(
                    status: .partial,
                    values: responseValues,
                    failedDeliveries: failedDeliveryIDs,
                    diagnostic: "some deliveries failed"
                )
            case .cancelled:
                try requireTimeRemaining(deadline)
                return result(status: .cancelled, values: [:], exitCode: 1)
            case .expired:
                return result(status: .expired, values: [:], exitCode: 1)
            }
        } catch RequestTimeoutError.expired {
            return result(status: .expired, values: [:], exitCode: 1)
        } catch {
            if deadline.isExpired {
                return result(status: .expired, values: [:], exitCode: 1)
            }
            return failure("request failed: \(error.localizedDescription)")
        }
    }

    private func readRequest(_ source: String, standardInput: Data) throws -> Data {
        if source == "-" {
            return standardInput
        }
        return try Data(contentsOf: URL(fileURLWithPath: source))
    }

    private func requireTimeRemaining(_ deadline: RequestDeadline) throws {
        guard !deadline.isExpired else {
            throw RequestTimeoutError.expired
        }
    }

    private func result(
        status: CommandStatus,
        values: [String: ResponseValue],
        failedDeliveries: [String]? = nil,
        diagnostic: String? = nil,
        exitCode: Int32 = 1
    ) -> CLIExecution {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let output = try! encoder.encode(
            CommandResult(
                status: status,
                values: values,
                failedDeliveries: failedDeliveries
            )
        ) + Data([0x0A])
        return CLIExecution(
            exitCode: exitCode,
            standardOutput: output,
            standardError: diagnostic.map { Data(($0 + "\n").utf8) } ?? Data()
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
    let failedDeliveries: [String]?
}

private enum CommandStatus: String, Encodable {
    case completed
    case partial
    case failed
    case cancelled
    case expired
}
