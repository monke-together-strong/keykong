import Foundation

enum SubmissionValidator {
    static func validate(
        _ values: [String: ResponseValue],
        for request: InputRequest
    ) throws -> [String: ResponseValue] {
        guard Set(values.keys) == Set(request.fields.map(\.id)) else {
            throw ValidationError(
                "adapter did not return exactly the requested fields"
            )
        }

        var validated: [String: ResponseValue] = [:]
        for field in request.fields {
            guard let value = values[field.id] else {
                throw ValidationError(
                    "adapter did not return exactly the requested fields"
                )
            }

            switch (field.type, value) {
            case let (type, .text(text))
                where (type == .text || type == .secret)
                    && Validation.isNonEmptySingleLine(text):
                validated[field.id] = value

            case let (.select, .text(selected))
                where field.options?.contains(where: { $0.value == selected }) == true:
                validated[field.id] = value

            case let (.multiSelect, .selection(selected))
                where isValidMultiSelection(selected, options: field.options ?? []):
                let selectedSet = Set(selected)
                validated[field.id] = .selection(
                    (field.options ?? [])
                        .map(\.value)
                        .filter(selectedSet.contains)
                )

            default:
                throw ValidationError(
                    "adapter returned an invalid value for field '\(field.id)'"
                )
            }
        }
        return validated
    }

    private static func isValidMultiSelection(
        _ selected: [String],
        options: [InputOption]
    ) -> Bool {
        let selectedSet = Set(selected)
        let optionValues = Set(options.map(\.value))
        return !selected.isEmpty
            && selectedSet.count == selected.count
            && selectedSet.isSubset(of: optionValues)
    }
}
