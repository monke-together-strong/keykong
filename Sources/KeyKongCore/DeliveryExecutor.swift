import Foundation

enum DeliveryExecutor {
    static func validateTargets(_ deliveries: [Delivery]) throws {
        var simulatedTargets: [String: Data] = [:]

        for delivery in deliveries {
            try validateMetadata(delivery)

            var target = try simulatedTargets[delivery.path]
                ?? readTarget(delivery)
            let template = try FieldTemplate(delivery.template)
            let rendered = Data(template.validationRendering.utf8)
            try apply(delivery, rendered: rendered, to: &target)
            simulatedTargets[delivery.path] = target
        }
    }

    private static func validateMetadata(_ delivery: Delivery) throws {
        guard delivery.path.hasPrefix("/") else {
            throw ValidationError(
                "delivery '\(delivery.id)' path must be absolute"
            )
        }

        let attributes = try? FileManager.default.attributesOfItem(
            atPath: delivery.path
        )
        guard attributes?[.type] as? FileAttributeType == .typeRegular else {
            throw ValidationError(
                "delivery '\(delivery.id)' target must be an existing regular file"
            )
        }
        guard FileManager.default.isReadableFile(atPath: delivery.path),
              FileManager.default.isWritableFile(atPath: delivery.path)
        else {
            throw ValidationError(
                "delivery '\(delivery.id)' target must be readable and writable"
            )
        }

        switch delivery.operation {
        case .append:
            guard delivery.line == nil else {
                throw ValidationError(
                    "append delivery '\(delivery.id)' must not define a line"
                )
            }

        case .insertLine:
            guard delivery.line.map({ $0 > 0 }) == true else {
                throw ValidationError(
                    "insert_line delivery '\(delivery.id)' needs a positive line"
                )
            }
        }
    }

    static func execute(
        _ deliveries: [Delivery],
        values: [String: ResponseValue]
    ) throws {
        for delivery in deliveries {
            do {
                let template = try FieldTemplate(delivery.template)
                let rendered = Data(try template.render(values: values).utf8)
                var target = try readTarget(delivery)
                try apply(delivery, rendered: rendered, to: &target)
                try target.write(to: URL(fileURLWithPath: delivery.path))
            } catch {
                throw ValidationError("delivery '\(delivery.id)' failed")
            }
        }
    }

    private static func readTarget(_ delivery: Delivery) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: delivery.path))
    }

    private static func apply(
        _ delivery: Delivery,
        rendered: Data,
        to target: inout Data
    ) throws {
        switch delivery.operation {
        case .append:
            target.append(rendered)

        case .insertLine:
            guard let line = delivery.line,
                  let offset = insertionOffset(before: line, in: target)
            else {
                throw ValidationError(
                    "delivery '\(delivery.id)' line is outside the target"
                )
            }
            var lineData = rendered
            if lineData.last != 0x0A {
                lineData.append(0x0A)
            }
            target.insert(contentsOf: lineData, at: offset)
        }
    }

    private static func insertionOffset(before line: Int, in data: Data) -> Int? {
        guard line > 0 else { return nil }
        if line == 1 { return 0 }

        var currentLine = 1
        for (offset, byte) in data.enumerated() where byte == 0x0A {
            currentLine += 1
            if currentLine == line {
                return offset + 1
            }
        }
        return nil
    }
}
