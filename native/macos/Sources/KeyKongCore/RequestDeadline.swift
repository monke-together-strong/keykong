import Dispatch
import Foundation

public struct RequestDeadline: Sendable {
    private let uptimeNanoseconds: UInt64

    public init(timeout: TimeInterval) {
        let now = DispatchTime.now().uptimeNanoseconds
        let finiteTimeout = timeout.isFinite ? timeout : 0
        let timeoutNanoseconds = UInt64(
            min(
                max(finiteTimeout, 0) * 1_000_000_000,
                Double(UInt64.max - now)
            )
        )
        uptimeNanoseconds = now + timeoutNanoseconds
    }

    public var remainingTimeInterval: TimeInterval {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < uptimeNanoseconds else { return 0 }
        return TimeInterval(uptimeNanoseconds - now) / 1_000_000_000
    }

    public var isExpired: Bool {
        remainingTimeInterval == 0
    }
}

public enum RequestTimeoutError: Error, Equatable {
    case expired
}
