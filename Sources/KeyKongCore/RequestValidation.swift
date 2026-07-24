import Foundation

enum RequestValidator {
    static func validate(_ request: InputRequest) throws {
        guard Validation.isValidID(request.id) else {
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

        try validateDeliveries(request.deliveries, fields: request.fields)
    }

    private static func validate(_ field: InputField) throws {
        guard Validation.isValidID(field.id) else {
            throw ValidationError("field ID '\(field.id)' is invalid")
        }
        guard Validation.isNonEmptySingleLine(field.label) else {
            throw ValidationError(
                "field '\(field.id)' label must be a non-empty single line"
            )
        }

        switch field.type {
        case .text, .secret:
            guard field.options == nil else {
                throw ValidationError(
                    "field '\(field.id)' must not define options"
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

    private static func validateDeliveries(
        _ deliveries: [Delivery],
        fields: [InputField]
    ) throws {
        let deliveryIDs = deliveries.map(\.id)
        guard Set(deliveryIDs).count == deliveryIDs.count else {
            throw ValidationError("delivery IDs must be unique")
        }

        let fieldsByID = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0) })
        var referencedFieldIDs = Set<String>()

        for delivery in deliveries {
            guard Validation.isValidID(delivery.id) else {
                throw ValidationError("delivery ID '\(delivery.id)' is invalid")
            }

            let template = try FieldTemplate(delivery.template)
            guard !template.references.isEmpty else {
                throw ValidationError(
                    "delivery '\(delivery.id)' template must reference at least one field"
                )
            }

            for fieldID in template.references {
                guard let field = fieldsByID[fieldID] else {
                    throw ValidationError(
                        "delivery '\(delivery.id)' references unknown field '\(fieldID)'"
                    )
                }
                guard field.type != .multiSelect else {
                    throw ValidationError(
                        "delivery '\(delivery.id)' cannot reference multi-select field '\(fieldID)'"
                    )
                }
                referencedFieldIDs.insert(fieldID)
            }
        }

        for field in fields where field.type == .secret {
            guard referencedFieldIDs.contains(field.id) else {
                throw ValidationError(
                    "secret field '\(field.id)' must appear in a delivery template"
                )
            }
        }

        try DeliveryExecutor.validateTargets(deliveries)
    }
}
