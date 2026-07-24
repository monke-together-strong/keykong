import KeyKongCore
import KeyKongMacOS

public enum PromptRunner {
    @MainActor
    public static func run(_ request: PromptRequest) -> PromptOutcome {
        let input = InputRequest(
            id: "prompt",
            title: request.title,
            fields: request.fields.map {
                InputField(
                    id: $0.id,
                    label: $0.label,
                    type: KeyKongCore.FieldType(rawValue: $0.type.rawValue)!,
                    options: $0.options?.map {
                        InputOption(label: $0.label, value: $0.value)
                    }
                )
            },
            deliveries: request.deliveries.enumerated().map { index, delivery in
                Delivery(
                    id: "delivery-\(index)",
                    path: delivery.path,
                    operation: KeyKongCore.DeliveryOperation(
                        rawValue: delivery.operation.rawValue
                    )!,
                    line: delivery.line,
                    template: ""
                )
            }
        )

        switch MacOSInputAdapter().collectInput(
            for: input,
            deadline: RequestDeadline(timeout: 10 * 365 * 24 * 60 * 60)
        ) {
        case let .submitted(values):
            return .submitted(values.mapValues {
                switch $0 {
                case let .text(value):
                    .text(value)
                case let .selection(values):
                    .selection(values)
                }
            })
        case .cancelled, .expired:
            return .cancelled
        }
    }
}
