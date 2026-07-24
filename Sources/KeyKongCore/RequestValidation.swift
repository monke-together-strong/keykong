import Foundation

enum RequestValidator {
    static func validate(_ request: InputRequest) throws {
        guard isValidID(request.id) else {
            throw ValidationError("request ID is invalid")
        }
        guard Validation.isNonEmptySingleLine(request.title) else {
            throw ValidationError("request title must be a non-empty single line")
        }
        guard !request.fields.isEmpty else {
            throw ValidationError("at least one field is required")
        }

        let fieldIDs = request.fields.map(\.id)
        guard Set(fieldIDs).count == fieldIDs.count else {
            throw ValidationError("field IDs must be unique")
        }

        for field in request.fields {
            try validate(field)
        }
    }

    private static func validate(_ field: InputField) throws {
        guard isValidID(field.id) else {
            throw ValidationError("field ID '\(field.id)' is invalid")
        }
        guard Validation.isNonEmptySingleLine(field.label) else {
            throw ValidationError(
                "field '\(field.id)' label must be a non-empty single line"
            )
        }

        switch field.type {
        case .text:
            guard field.options == nil else {
                throw ValidationError(
                    "text field '\(field.id)' must not define options"
                )
            }

        case .select, .multiSelect:
            guard let options = field.options, !options.isEmpty else {
                throw ValidationError(
                    "field '\(field.id)' must define at least one option"
                )
            }
            let values = options.map(\.value)
            guard Set(values).count == values.count else {
                throw ValidationError(
                    "field '\(field.id)' option values must be unique"
                )
            }
            for option in options {
                guard Validation.isNonEmptySingleLine(option.label),
                      Validation.isNonEmptySingleLine(option.value)
                else {
                    throw ValidationError(
                        "field '\(field.id)' options need non-empty single-line labels and values"
                    )
                }
            }
        }
    }

    private static func isValidID(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(first)
        else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
    }

}
