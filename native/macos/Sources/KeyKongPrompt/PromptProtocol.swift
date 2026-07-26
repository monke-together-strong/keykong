import Foundation

public struct PromptRequest: Codable, Equatable, Sendable {
    public let title: String
    public let fields: [PromptField]
    public let deliveries: [PromptDelivery]

    public init(
        title: String,
        fields: [PromptField],
        deliveries: [PromptDelivery] = []
    ) {
        self.title = title
        self.fields = fields
        self.deliveries = deliveries
    }
}

public struct PromptField: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let type: FieldType
    public let options: [PromptOption]?

    public init(
        id: String,
        label: String,
        type: FieldType,
        options: [PromptOption]? = nil
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.options = options
    }
}

public enum FieldType: String, Codable, Equatable, Sendable {
    case text
    case secret
    case select
    case multiSelect = "multi_select"
}

public struct PromptOption: Codable, Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct PromptDelivery: Codable, Equatable, Sendable {
    public let path: String
    public let operation: DeliveryOperation
    public let line: Int?
    public let key: String?
    public let field: String?

    public init(
        path: String,
        operation: DeliveryOperation,
        line: Int? = nil,
        key: String? = nil,
        field: String? = nil
    ) {
        self.path = path
        self.operation = operation
        self.line = line
        self.key = key
        self.field = field
    }
}

public enum DeliveryOperation: String, Codable, Equatable, Sendable {
    case append
    case insertLine = "insert_line"
    case setEnv = "set_env"
}

public enum ResponseValue: Equatable, Sendable {
    case text(String)
    case selection([String])
}

extension ResponseValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
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

public enum PromptOutcome: Equatable, Sendable {
    case submitted([String: ResponseValue])
    case cancelled
}

extension PromptOutcome: Codable {
    private enum CodingKeys: String, CodingKey {
        case status
        case values
    }

    private enum Status: String, Codable {
        case submitted
        case cancelled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Status.self, forKey: .status) {
        case .submitted:
            self = .submitted(
                try container.decode(
                    [String: ResponseValue].self,
                    forKey: .values
                )
            )
        case .cancelled:
            self = .cancelled
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .submitted(values):
            try container.encode(Status.submitted, forKey: .status)
            try container.encode(values, forKey: .values)
        case .cancelled:
            try container.encode(Status.cancelled, forKey: .status)
        }
    }
}
