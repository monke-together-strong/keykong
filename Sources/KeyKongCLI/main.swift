import Darwin
import Foundation
import KeyKongCore
import KeyKongMacOS

let arguments = Array(CommandLine.arguments.dropFirst())
let execution: CLIExecution
private let outputGuard: (
    deadline: RequestDeadline,
    watchdog: RequestWatchdog
)?
let requestTimeout: TimeInterval

#if DEBUG
requestTimeout = ProcessInfo.processInfo.environment[
    "KEY_KONG_TEST_TIMEOUT_SECONDS"
].flatMap(TimeInterval.init).map { min(max($0, 0.01), 10 * 60) } ?? 10 * 60
#else
requestTimeout = 10 * 60
#endif

if arguments == ["_delivery-worker"] {
    outputGuard = nil
    execution = DeliveryWorker.run(
        standardInput: FileHandle.standardInput.readDataToEndOfFile()
    )
} else {
#if DEBUG
    if arguments == ["_test-delivery-parent"] {
        outputGuard = nil
        let executableURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0])
        execution = DeliveryWorker.runInChildProcess(
            executableURL: executableURL,
            standardInput: FileHandle.standardInput.readDataToEndOfFile(),
            deadline: RequestDeadline(timeout: requestTimeout)
        )
    } else {
        let request = runNormalRequest(
            arguments: arguments,
            requestTimeout: requestTimeout
        )
        execution = request.execution
        outputGuard = (request.deadline, request.watchdog)
    }
#else
    let request = runNormalRequest(
        arguments: arguments,
        requestTimeout: requestTimeout
    )
    execution = request.execution
    outputGuard = (request.deadline, request.watchdog)
#endif
}

if let outputGuard {
    outputGuard.watchdog.beginOutput()
    _ = write(
        execution.standardOutput,
        to: STDOUT_FILENO,
        before: outputGuard.deadline
    )
    _ = write(
        execution.standardError,
        to: STDERR_FILENO,
        before: outputGuard.deadline
    )
    outputGuard.watchdog.complete()
} else {
    FileHandle.standardOutput.write(execution.standardOutput)
    FileHandle.standardError.write(execution.standardError)
}
exit(execution.exitCode)

private final class RequestWatchdog: @unchecked Sendable {
    private let deadline: RequestDeadline
    private let lock = NSLock()
    private let timer: DispatchSourceTimer
    private var completed = false
    private var outputStarted = false

    init(deadline: RequestDeadline) {
        self.deadline = deadline
        timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        timer.schedule(
            deadline: .now() + deadline.remainingTimeInterval
        )
        timer.setEventHandler { [weak self] in
            self?.expire()
        }
        timer.resume()
    }

    func beginOutput() {
        lock.lock()
        guard !deadline.isExpired else {
            expireWhileLocked()
        }
        outputStarted = true
        lock.unlock()
    }

    func complete() {
        lock.lock()
        guard !deadline.isExpired else {
            expireWhileLocked()
        }
        completed = true
        timer.cancel()
        lock.unlock()
    }

    private func expire() {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        expireWhileLocked()
    }

    private func expireWhileLocked() -> Never {
        if !outputStarted {
            let output = Data(#"{"status":"expired","values":{}}"#.utf8)
                + Data([0x0A])
            writeNonBlocking(output, to: STDOUT_FILENO)
        }
        _exit(1)
    }
}

private func runNormalRequest(
    arguments: [String],
    requestTimeout: TimeInterval
) -> (
    execution: CLIExecution,
    deadline: RequestDeadline,
    watchdog: RequestWatchdog
) {
    let processDeadline = RequestDeadline(timeout: requestTimeout)
    let outputMargin = min(0.25, requestTimeout / 2)
    let commandDeadline = RequestDeadline(
        timeout: max(0, requestTimeout - outputMargin)
    )
    let watchdog = RequestWatchdog(deadline: processDeadline)
    let standardInput = arguments.count == 3 && arguments[2] == "-"
        ? FileHandle.standardInput.readDataToEndOfFile()
        : Data()
    let executableURL = Bundle.main.executableURL
        ?? URL(fileURLWithPath: CommandLine.arguments[0])
    let execution = KeyKongCommand(
        adapter: MacOSInputAdapter(),
        deliveryExecutor: ChildProcessDeliveryExecutor(
            executableURL: executableURL
        )
    ).run(
        arguments: arguments,
        standardInput: standardInput,
        deadline: commandDeadline
    )
    return (execution, processDeadline, watchdog)
}

private func write(
    _ data: Data,
    to descriptor: Int32,
    before deadline: RequestDeadline
) -> Bool {
    guard !data.isEmpty else { return true }

    let originalFlags = fcntl(descriptor, F_GETFL)
    guard originalFlags >= 0,
          fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0
    else {
        return false
    }
    defer { _ = fcntl(descriptor, F_SETFL, originalFlags) }

    return data.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(
                descriptor,
                bytes.baseAddress?.advanced(by: offset),
                bytes.count - offset
            )
            if count > 0 {
                offset += count
                continue
            }
            if count < 0, errno != EAGAIN, errno != EWOULDBLOCK {
                if errno == EINTR {
                    continue
                }
                return false
            }

            let remaining = deadline.remainingTimeInterval
            guard remaining > 0 else { return false }
            var writable = pollfd(
                fd: descriptor,
                events: Int16(POLLOUT),
                revents: 0
            )
            let milliseconds = Int32(
                min(ceil(remaining * 1_000), Double(Int32.max))
            )
            let pollResult = Darwin.poll(&writable, 1, milliseconds)
            if pollResult == 0 {
                return false
            }
            if pollResult < 0, errno != EINTR {
                return false
            }
        }
        return true
    }
}

private func writeNonBlocking(_ data: Data, to descriptor: Int32) {
    let originalFlags = fcntl(descriptor, F_GETFL)
    guard originalFlags >= 0,
          fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0
    else {
        return
    }
    defer { _ = fcntl(descriptor, F_SETFL, originalFlags) }

    data.withUnsafeBytes {
        _ = Darwin.write(descriptor, $0.baseAddress, $0.count)
    }
}
