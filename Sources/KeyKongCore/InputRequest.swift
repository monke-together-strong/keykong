import Foundation

public struct InputRequest: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let fields: [InputField]
    public let deliveries: [Delivery]

    public init(
        id: String,
        title: String,
        fields: [InputField],
        deliveries: [Delivery] = []
    ) {
        self.id = id
        self.title = title
        self.fields = fields
        self.deliveries = deliveries
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case fields
        case deliveries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        fields = try container.decode([InputField].self, forKey: .fields)
        deliveries = try container.decodeIfPresent(
            [Delivery].self,
            forKey: .deliveries
        ) ?? []
    }
}

public struct InputField: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let type: FieldType
    public let options: [InputOption]?

    public init(
        id: String,
        label: String,
        type: FieldType,
        options: [InputOption]? = nil
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

public struct InputOption: Codable, Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct Delivery: Codable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let operation: DeliveryOperation
    public let line: Int?
    public let template: String

    public init(
        id: String,
        path: String,
        operation: DeliveryOperation,
        line: Int? = nil,
        template: String
    ) {
        self.id = id
        self.path = path
        self.operation = operation
        self.line = line
        self.template = template
    }
}

public enum DeliveryOperation: String, Codable, Equatable, Sendable {
    case insertLine = "insert_line"
    case append
}
