import Foundation

enum Validation {
    static func isNonEmptySingleLine(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.contains(where: \.isNewline)
    }
}

struct ValidationError: LocalizedError {
    let errorDescription: String?

    init(_ description: String) {
        self.errorDescription = description
    }
}
