import Foundation

public struct InputRequest: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let fields: [InputField]

    public init(id: String, title: String, fields: [InputField]) {
        self.id = id
        self.title = title
        self.fields = fields
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
