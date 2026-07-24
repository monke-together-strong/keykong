import Foundation
import XCTest
@testable import KeyKongPrompt

final class PromptTests: XCTestCase {
    func testProtocolRepresentsStableOptionsSecretsAndSanitizedDeliveries() throws {
        let request = try JSONDecoder().decode(
            PromptRequest.self,
            from: Data(
                """
                {
                  "title": "Prompt",
                  "fields": [
                    {"id":"region","label":"Region","type":"select",
                     "options":[{"label":"Oregon","value":"us-west-2"}]},
                    {"id":"token","label":"Token","type":"secret"}
                  ],
                  "deliveries": [
                    {"path":"/tmp/config","operation":"insert_line","line":2}
                  ]
                }
                """.utf8
            )
        )

        XCTAssertEqual(request.fields.first?.options?.first?.value, "us-west-2")
        XCTAssertEqual(request.fields.last?.type, .secret)
        XCTAssertEqual(request.deliveries.first?.line, 2)

        let encoded = try JSONEncoder().encode(
            PromptOutcome.submitted(["region": .text("us-west-2")])
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(object["status"] as? String, "submitted")
        XCTAssertEqual(
            (object["values"] as? [String: String])?["region"],
            "us-west-2"
        )
    }
}
