import Foundation

struct FieldTemplate {
    private enum Part {
        case literal(String)
        case field(String)
    }

    let references: [String]
    private let parts: [Part]

    init(_ source: String) throws {
        var parts: [Part] = []
        var references: [String] = []
        var cursor = source.startIndex

        while let opening = source[cursor...].range(of: "{{") {
            let literal = String(source[cursor..<opening.lowerBound])
            guard !literal.contains("}}") else {
                throw ValidationError("delivery template has invalid braces")
            }
            if !literal.isEmpty {
                parts.append(.literal(literal))
            }

            guard let closing = source[opening.upperBound...].range(of: "}}") else {
                throw ValidationError("delivery template has an unclosed field reference")
            }
            let fieldID = source[opening.upperBound..<closing.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard Validation.isValidID(fieldID) else {
                throw ValidationError("delivery template has an invalid field reference")
            }

            parts.append(.field(fieldID))
            references.append(fieldID)
            cursor = closing.upperBound
        }

        let trailing = String(source[cursor...])
        guard !trailing.contains("}}") else {
            throw ValidationError("delivery template has invalid braces")
        }
        if !trailing.isEmpty {
            parts.append(.literal(trailing))
        }

        self.parts = parts
        self.references = references
    }

    func render(values: [String: ResponseValue]) throws -> String {
        try render { fieldID in
            guard case let .text(value)? = values[fieldID] else {
                throw ValidationError(
                    "delivery template value for field '\(fieldID)' is unavailable"
                )
            }
            return value
        }
    }

    var validationRendering: String {
        render { _ in "" }
    }

    private func render(
        resolving field: (String) throws -> String
    ) rethrows -> String {
        try parts.map { part in
            switch part {
            case let .literal(value):
                return value
            case let .field(fieldID):
                return try field(fieldID)
            }
        }.joined()
    }
}
