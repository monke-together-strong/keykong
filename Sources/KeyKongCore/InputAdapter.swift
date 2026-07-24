import Foundation

public protocol InputAdapter {
    func collectInput(
        for request: InputRequest,
        deadline: RequestDeadline
    ) -> InputOutcome
}

public enum InputOutcome: Equatable, Sendable {
    case submitted([String: ResponseValue])
    case cancelled
    case expired
}

public enum ResponseValue: Equatable, Sendable {
    case text(String)
    case selection([String])
}

extension ResponseValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .text(value)
        } else {
            self = .selection(try container.decode([String].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(value):
            try container.encode(value)
        case let .selection(values):
            try container.encode(values)
        }
    }
}
