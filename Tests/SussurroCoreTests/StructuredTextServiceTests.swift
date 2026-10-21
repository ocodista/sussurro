import XCTest
@testable import SussurroCore

final class StructuredTextServiceTests: XCTestCase {
    func testStructureTextExtractsLabeledFieldsAndValidatesRequiredTypes() throws {
        let schema = """
        {"type":"object","properties":{"speaker":{"type":"string"},"minutes":{"type":"integer"},"approved":{"type":"boolean"}},"required":["speaker","minutes","approved"],"additionalProperties":false}
        """.data(using: .utf8)!

        let result = try StructuredTextService().structure(
            text: "speaker: Ana\nminutes: 12\napproved: true",
            schemaData: schema
        )

        XCTAssertEqual(result["speaker"] as? String, "Ana")
        XCTAssertEqual(result["minutes"] as? Int, 12)
        XCTAssertEqual(result["approved"] as? Bool, true)
        XCTAssertNoThrow(try JSONSchemaValidator().validate(instance: result, schemaData: schema))
    }

    func testExtractedValueOverridesSchemaDefault() throws {
        let schema = """
        {"type":"object","properties":{"speaker":{"type":"string","default":"Unknown"}},"required":["speaker"]}
        """.data(using: .utf8)!

        let result = try StructuredTextService().structure(text: "speaker: Ana", schemaData: schema)

        XCTAssertEqual(result["speaker"] as? String, "Ana")
    }
}