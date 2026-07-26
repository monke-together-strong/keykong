import Darwin
import Dispatch

public final class ParentProcessMonitor {
    private let source: any DispatchSourceProcess

    public init?(
        processID: pid_t,
        onExit: @escaping @Sendable () -> Void
    ) {
        guard processID > 1 else { return nil }
        let queue = DispatchQueue(
            label: "dev.keykong.parent-process-monitor"
        )
        source = DispatchSource.makeProcessSource(
            identifier: processID,
            eventMask: .exit,
            queue: queue
        )
        source.setEventHandler(handler: onExit)
        source.resume()
    }

    public func cancel() {
        source.cancel()
    }

    deinit {
        source.cancel()
    }
}
