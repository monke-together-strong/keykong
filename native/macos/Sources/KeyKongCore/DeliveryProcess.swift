import Darwin
import Foundation

public protocol DeliveryExecuting {
    func execute(
        _ deliveries: [Delivery],
        values: [String: ResponseValue],
        expectedTargets: [String: DeliveryTargetIdentity],
        deadline: RequestDeadline
    ) throws -> [String]
}

public struct ChildProcessDeliveryExecutor: DeliveryExecuting {
    private let executableURL: URL

    public init(executableURL: URL) {
        self.executableURL = executableURL
    }

    public func execute(
        _ deliveries: [Delivery],
        values: [String: ResponseValue],
        expectedTargets: [String: DeliveryTargetIdentity],
        deadline: RequestDeadline
    ) throws -> [String] {
        guard !deadline.isExpired else {
            throw RequestTimeoutError.expired
        }

        let input = try JSONEncoder().encode(
            DeliveryWorkRequest(
                deliveries: deliveries,
                values: values,
                expectedTargets: expectedTargets
            )
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

        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        try process.run()
        let inputWriter = PipeWriter(
            input,
            handle: standardInput.fileHandleForWriting
        )
        let outputReader = PipeReader(
            handle: standardOutput.fileHandleForReading
        )
        let errorReader = PipeReader(
            handle: standardError.fileHandleForReading
        )
        inputWriter.start()
        outputReader.start()
        errorReader.start()

        let terminationMargin = min(
            0.25,
            deadline.remainingTimeInterval / 2
        )
        guard terminated.wait(
            timeout: .now()
                + max(0, deadline.remainingTimeInterval - terminationMargin)
        ) == .success else {
            try? standardInput.fileHandleForWriting.close()
            process.terminate()
            if terminated.wait(timeout: .now() + 0.2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = terminated.wait(timeout: .now() + 0.2)
            }
            throw RequestTimeoutError.expired
        }

        guard inputWriter.wait(until: deadline),
              outputReader.wait(until: deadline),
              errorReader.wait(until: deadline),
              !deadline.isExpired
        else {
            throw RequestTimeoutError.expired
        }

        guard process.terminationReason == .exit,
              process.terminationStatus == 0,
              let result = try? JSONDecoder().decode(
                DeliveryWorkResult.self,
                from: outputReader.data
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
                values: request.values,
                expectedTargets: request.expectedTargets,
                deadline: RequestDeadline(timeout: 10 * 60)
            )
            return try success(failedDeliveryIDs)
        } catch {
            return CLIExecution(
                exitCode: 1,
                standardOutput: Data(),
                standardError: Data("delivery worker failed\n".utf8)
            )
        }
    }

    public static func runInChildProcess(
        executableURL: URL,
        standardInput: Data,
        deadline: RequestDeadline
    ) -> CLIExecution {
        do {
            let request = try JSONDecoder().decode(
                DeliveryWorkRequest.self,
                from: standardInput
            )
            let failedDeliveryIDs = try ChildProcessDeliveryExecutor(
                executableURL: executableURL
            ).execute(
                request.deliveries,
                values: request.values,
                expectedTargets: request.expectedTargets,
                deadline: deadline
            )
            return try success(failedDeliveryIDs)
        } catch {
            return CLIExecution(
                exitCode: 1,
                standardOutput: Data(),
                standardError: Data("delivery parent failed\n".utf8)
            )
        }
    }

    private static func success(
        _ failedDeliveryIDs: [String]
    ) throws -> CLIExecution {
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
    }
}

private struct DeliveryWorkRequest: Codable {
    let deliveries: [Delivery]
    let values: [String: ResponseValue]
    let expectedTargets: [String: DeliveryTargetIdentity]
}

private struct DeliveryWorkResult: Codable {
    let failedDeliveryIDs: [String]
}

private enum DeliveryProcessError: Error {
    case workerFailed
}

private final class PipeWriter: @unchecked Sendable {
    private let data: Data
    private let handle: FileHandle
    private let completed = DispatchSemaphore(value: 0)

    init(_ data: Data, handle: FileHandle) {
        self.data = data
        self.handle = handle
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async {
            try? self.handle.write(contentsOf: self.data)
            try? self.handle.close()
            self.completed.signal()
        }
    }

    func wait(until deadline: RequestDeadline) -> Bool {
        completed.wait(
            timeout: .now() + deadline.remainingTimeInterval
        ) == .success
    }
}

private final class PipeReader: @unchecked Sendable {
    private let handle: FileHandle
    private let completed = DispatchSemaphore(value: 0)
    private(set) var data = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.data = self.handle.readDataToEndOfFile()
            self.completed.signal()
        }
    }

    func wait(until deadline: RequestDeadline) -> Bool {
        completed.wait(
            timeout: .now() + deadline.remainingTimeInterval
        ) == .success
    }
}
