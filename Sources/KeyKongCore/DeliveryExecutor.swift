import Darwin
import Foundation

public struct DeliveryTargetIdentity: Codable, Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64

    init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

struct DeliveryExecutor: DeliveryExecuting {
    static func validateTargets(
        _ deliveries: [Delivery]
    ) throws -> [String: DeliveryTargetIdentity] {
        var simulatedTargets: [String: Data] = [:]
        var identitiesByPath: [String: DeliveryTargetIdentity] = [:]
        var expectedTargets: [String: DeliveryTargetIdentity] = [:]

        for delivery in deliveries {
            try validateMetadata(delivery)

            let identity: DeliveryTargetIdentity
            var target: Data
            if let simulatedTarget = simulatedTargets[delivery.path],
               let knownIdentity = identitiesByPath[delivery.path] {
                target = simulatedTarget
                identity = knownIdentity
            } else {
                let openedTarget = try OpenedDeliveryTarget(
                    path: delivery.path
                )
                target = try openedTarget.read()
                identity = openedTarget.identity
                identitiesByPath[delivery.path] = identity
            }

            let template = try FieldTemplate(delivery.template)
            let rendered = Data(template.validationRendering.utf8)
            try apply(delivery, rendered: rendered, to: &target)
            simulatedTargets[delivery.path] = target
            expectedTargets[delivery.id] = identity
        }

        return expectedTargets
    }

    private static func validateMetadata(_ delivery: Delivery) throws {
        guard delivery.path.hasPrefix("/") else {
            throw ValidationError(
                "delivery '\(delivery.id)' path must be absolute"
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

    func execute(
        _ deliveries: [Delivery],
        values: [String: ResponseValue],
        expectedTargets: [String: DeliveryTargetIdentity],
        deadline: RequestDeadline
    ) -> [String] {
        var failedDeliveryIDs: [String] = []

        for delivery in deliveries {
            guard !deadline.isExpired else { break }
            do {
                guard let expectedTarget = expectedTargets[delivery.id] else {
                    throw ValidationError(
                        "delivery '\(delivery.id)' target identity is unavailable"
                    )
                }
                let openedTarget = try OpenedDeliveryTarget(
                    path: delivery.path
                )
                guard openedTarget.identity == expectedTarget else {
                    throw ValidationError(
                        "delivery '\(delivery.id)' target changed"
                    )
                }

                let template = try FieldTemplate(delivery.template)
                let rendered = Data(try template.render(values: values).utf8)
                var target = try openedTarget.read()
                try Self.apply(delivery, rendered: rendered, to: &target)
                try openedTarget.replace(with: target)
            } catch {
                failedDeliveryIDs.append(delivery.id)
            }
        }

        return failedDeliveryIDs
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

private final class OpenedDeliveryTarget {
    let identity: DeliveryTargetIdentity
    private let descriptor: Int32

    init(path: String) throws {
        descriptor = open(path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw ValidationError(
                "delivery target must be an existing readable and writable regular file"
            )
        }

        var information = stat()
        guard fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG
        else {
            close(descriptor)
            throw ValidationError(
                "delivery target must be an existing readable and writable regular file"
            )
        }
        identity = DeliveryTargetIdentity(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino)
        )
    }

    deinit {
        close(descriptor)
    }

    func read() throws -> Data {
        guard lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw ValidationError("delivery target could not be read")
        }

        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                result.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                return result
            } else if errno != EINTR {
                throw ValidationError("delivery target could not be read")
            }
        }
    }

    func replace(with data: Data) throws {
        guard ftruncate(descriptor, 0) == 0,
              lseek(descriptor, 0, SEEK_SET) >= 0
        else {
            throw ValidationError("delivery target could not be written")
        }

        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    bytes.baseAddress?.advanced(by: offset),
                    bytes.count - offset
                )
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    throw ValidationError(
                        "delivery target could not be written"
                    )
                }
            }
        }
    }
}
