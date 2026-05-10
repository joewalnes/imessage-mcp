import XCTest
@testable import IMMessageMCPLib

final class IntArgTests: XCTestCase {
    func testReturnsIntFromNumber() {
        let args: [String: Any] = ["hours": 12]
        XCTAssertEqual(intArg(args, "hours", default: 24), 12)
    }

    func testReturnsIntFromString() {
        let args: [String: Any] = ["hours": "48"]
        XCTAssertEqual(intArg(args, "hours", default: 24), 48)
    }

    func testReturnsDefaultWhenMissing() {
        let args: [String: Any] = [:]
        XCTAssertEqual(intArg(args, "hours", default: 24), 24)
    }

    func testReturnsDefaultForNonNumericString() {
        let args: [String: Any] = ["hours": "abc"]
        XCTAssertEqual(intArg(args, "hours", default: 24), 24)
    }

    func testReturnsDefaultForWrongType() {
        let args: [String: Any] = ["hours": [1, 2, 3]]
        XCTAssertEqual(intArg(args, "hours", default: 24), 24)
    }

    func testZeroValue() {
        let args: [String: Any] = ["limit": 0]
        XCTAssertEqual(intArg(args, "limit", default: 50), 0)
    }

    func testNegativeValue() {
        let args: [String: Any] = ["hours": -5]
        XCTAssertEqual(intArg(args, "hours", default: 24), -5)
    }
}

final class ResponseBuildersTests: XCTestCase {
    func testSuccessResponseShape() {
        let resp = successResponse(id: 1, result: ["key": "value"])
        XCTAssertEqual(resp["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(resp["id"] as? Int, 1)
        let result = resp["result"] as? [String: Any]
        XCTAssertEqual(result?["key"] as? String, "value")
        XCTAssertNil(resp["error"])
    }

    func testErrorResponseShape() {
        let resp = errorResponse(id: 42, code: -32600, message: "Bad request")
        XCTAssertEqual(resp["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(resp["id"] as? Int, 42)
        let error = resp["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? Int, -32600)
        XCTAssertEqual(error?["message"] as? String, "Bad request")
        XCTAssertNil(resp["result"])
    }

    func testNullIdWhenNil() {
        let resp = successResponse(id: nil, result: [:])
        XCTAssertTrue(resp["id"] is NSNull)
    }

    func testStringId() {
        let resp = successResponse(id: "req-1", result: [:])
        XCTAssertEqual(resp["id"] as? String, "req-1")
    }

    func testToolResultSuccess() {
        let tr = toolResult(text: "hello")
        XCTAssertEqual(tr["isError"] as? Bool, false)
        let content = tr["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 1)
        XCTAssertEqual(content?[0]["type"] as? String, "text")
        XCTAssertEqual(content?[0]["text"] as? String, "hello")
    }

    func testToolResultError() {
        let tr = toolResult(text: "something broke", isError: true)
        XCTAssertEqual(tr["isError"] as? Bool, true)
    }
}

final class ToolsRegistryTests: XCTestCase {
    func testTwoToolsDefined() {
        XCTAssertEqual(TOOLS.count, 2)
    }

    func testReadToolName() {
        XCTAssertEqual(TOOLS[0]["name"] as? String, "read_recent_imessages")
    }

    func testSendToolName() {
        XCTAssertEqual(TOOLS[1]["name"] as? String, "send_imessage")
    }

    func testSendToolRequiredFields() {
        let schema = TOOLS[1]["inputSchema"] as? [String: Any]
        let required = schema?["required"] as? [String]
        XCTAssertEqual(required, ["recipient", "message"])
    }

    func testToolsSerializeToJSON() throws {
        // Verify the TOOLS array is valid JSON (catches schema shape bugs)
        let data = try JSONSerialization.data(withJSONObject: TOOLS, options: [])
        XCTAssertGreaterThan(data.count, 0)
    }
}

final class WriteJSONTests: XCTestCase {
    func testWritesValidNDJSON() throws {
        let pipe = Pipe()
        let obj: [String: Any] = ["jsonrpc": "2.0", "id": 1, "result": ["ok": true]]
        writeJSON(obj, to: pipe.fileHandleForWriting)
        try pipe.fileHandleForWriting.close()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let str = String(data: data, encoding: .utf8)!

        // Must end with newline
        XCTAssertTrue(str.hasSuffix("\n"))

        // Must be valid JSON
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(parsed?["jsonrpc"] as? String, "2.0")
    }
}
