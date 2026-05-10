import XCTest
@testable import IMMessageMCPLib

// MARK: - Mocks

final class MockReader: MessageReader {
    var rows: [IMessageRow] = []
    var error: Error?
    var lastHours: Int?
    var lastLimit: Int?

    func readRecent(hours: Int, limit: Int) throws -> [IMessageRow] {
        lastHours = hours
        lastLimit = limit
        if let error = error { throw error }
        return rows
    }
}

final class MockSender: MessageSender {
    var result: String = "Sent."
    var error: Error?
    var lastRecipient: String?
    var lastMessage: String?

    func send(recipient: String, message: String) throws -> String {
        lastRecipient = recipient
        lastMessage = message
        if let error = error { throw error }
        return result
    }
}

// MARK: - Test helpers

func makeServer(reader: MockReader = MockReader(), sender: MockSender = MockSender()) -> (MCPServer, MockReader, MockSender) {
    let server = MCPServer(reader: reader, sender: sender)
    return (server, reader, sender)
}

func jsonRequest(method: String, id: Any? = 1, params: [String: Any]? = nil) -> String {
    var obj: [String: Any] = ["jsonrpc": "2.0", "method": method]
    if let id = id { obj["id"] = id }
    if let params = params { obj["params"] = params }
    let data = try! JSONSerialization.data(withJSONObject: obj)
    return String(data: data, encoding: .utf8)!
}

func parseResponse(_ data: Data?) -> [String: Any]? {
    guard let data = data else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

// MARK: - IntArg tests

final class IntArgTests: XCTestCase {
    func testReturnsIntFromNumber() {
        XCTAssertEqual(MCPServer.intArg(["h": 12], "h", default: 24), 12)
    }

    func testReturnsIntFromString() {
        XCTAssertEqual(MCPServer.intArg(["h": "48"], "h", default: 24), 48)
    }

    func testReturnsDefaultWhenMissing() {
        XCTAssertEqual(MCPServer.intArg([:], "h", default: 24), 24)
    }

    func testReturnsDefaultForNonNumericString() {
        XCTAssertEqual(MCPServer.intArg(["h": "abc"], "h", default: 24), 24)
    }

    func testReturnsDefaultForWrongType() {
        XCTAssertEqual(MCPServer.intArg(["h": [1]], "h", default: 24), 24)
    }

    func testZeroValue() {
        XCTAssertEqual(MCPServer.intArg(["h": 0], "h", default: 50), 0)
    }

    func testNegativeValue() {
        XCTAssertEqual(MCPServer.intArg(["h": -5], "h", default: 24), -5)
    }
}

// MARK: - JSONRPCId tests

final class JSONRPCIdTests: XCTestCase {
    func testFromInt() {
        XCTAssertEqual(JSONRPCId.from(42 as NSNumber), .int(42))
    }

    func testFromString() {
        XCTAssertEqual(JSONRPCId.from("req-1"), .string("req-1"))
    }

    func testFromNSNull() {
        XCTAssertEqual(JSONRPCId.from(NSNull()), .null)
    }

    func testFromNilReturnsNil() {
        XCTAssertNil(JSONRPCId.from(nil))
    }

    func testEncodesInt() throws {
        let data = try JSONEncoder().encode(JSONRPCId.int(7))
        XCTAssertEqual(String(data: data, encoding: .utf8), "7")
    }

    func testEncodesString() throws {
        let data = try JSONEncoder().encode(JSONRPCId.string("abc"))
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"abc\"")
    }

    func testEncodesNull() throws {
        let data = try JSONEncoder().encode(JSONRPCId.null)
        XCTAssertEqual(String(data: data, encoding: .utf8), "null")
    }
}

// MARK: - IMessageRow encoding tests

final class IMessageRowTests: XCTestCase {
    func testEncodesSnakeCaseKeys() throws {
        let row = IMessageRow(
            timestampUtc: "2026-05-09T12:00:00.000Z",
            fromMe: true,
            contact: "+1234",
            chatIdentifier: "chat1",
            chatDisplayName: "Test",
            text: "hello"
        )
        let data = try JSONEncoder().encode(row)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(dict["timestamp_utc"])
        XCTAssertNotNil(dict["from_me"])
        XCTAssertNotNil(dict["chat_identifier"])
        XCTAssertNotNil(dict["chat_display_name"])
    }

    func testEncodesNilAsNull() throws {
        let row = IMessageRow(
            timestampUtc: "2026-05-09T12:00:00.000Z",
            fromMe: false,
            contact: nil,
            chatIdentifier: nil,
            chatDisplayName: nil,
            text: "hi"
        )
        let data = try JSONEncoder().encode(row)
        let json = String(data: data, encoding: .utf8)!
        // nil values should be present as null, not omitted
        XCTAssertTrue(json.contains("\"contact\":null"))
        XCTAssertTrue(json.contains("\"chat_identifier\":null"))
        XCTAssertTrue(json.contains("\"chat_display_name\":null"))
    }
}

// MARK: - Initialize tests

final class InitializeTests: XCTestCase {
    func testInitializeReturnsProtocolVersion() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(
            jsonRequest(method: "initialize", params: ["protocolVersion": "2024-11-05"])
        ))!
        let result = resp["result"] as! [String: Any]
        XCTAssertEqual(result["protocolVersion"] as? String, "2024-11-05")
    }

    func testInitializeDefaultsProtocolVersion() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(
            jsonRequest(method: "initialize")
        ))!
        let result = resp["result"] as! [String: Any]
        XCTAssertEqual(result["protocolVersion"] as? String, "2024-11-05")
    }

    func testInitializeReturnsServerInfo() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(
            jsonRequest(method: "initialize")
        ))!
        let result = resp["result"] as! [String: Any]
        let info = result["serverInfo"] as! [String: Any]
        XCTAssertEqual(info["name"] as? String, "imessage-mcp")
    }

    func testInitializeReturnsCapabilities() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(
            jsonRequest(method: "initialize")
        ))!
        let result = resp["result"] as! [String: Any]
        let caps = result["capabilities"] as! [String: Any]
        XCTAssertNotNil(caps["tools"])
    }
}

// MARK: - Ping tests

final class PingTests: XCTestCase {
    func testPingReturnsEmptyResult() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(jsonRequest(method: "ping")))!
        let result = resp["result"] as! [String: Any]
        XCTAssertTrue(result.isEmpty)
    }
}

// MARK: - Tools/list tests

final class ToolsListTests: XCTestCase {
    func testReturnsTwoTools() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(jsonRequest(method: "tools/list")))!
        let result = resp["result"] as! [String: Any]
        let tools = result["tools"] as! [[String: Any]]
        XCTAssertEqual(tools.count, 2)
    }

    func testToolNames() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(jsonRequest(method: "tools/list")))!
        let tools = (resp["result"] as! [String: Any])["tools"] as! [[String: Any]]
        XCTAssertEqual(tools[0]["name"] as? String, "read_recent_imessages")
        XCTAssertEqual(tools[1]["name"] as? String, "send_imessage")
    }

    func testToolsHaveInputSchema() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(jsonRequest(method: "tools/list")))!
        let tools = (resp["result"] as! [String: Any])["tools"] as! [[String: Any]]
        for tool in tools {
            XCTAssertNotNil(tool["inputSchema"])
        }
    }

    func testSendToolRequiredFields() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(jsonRequest(method: "tools/list")))!
        let tools = (resp["result"] as! [String: Any])["tools"] as! [[String: Any]]
        let sendTool = tools.first { $0["name"] as? String == "send_imessage" }!
        let schema = sendTool["inputSchema"] as! [String: Any]
        let required = schema["required"] as! [String]
        XCTAssertTrue(required.contains("recipient"))
        XCTAssertTrue(required.contains("message"))
    }

    func testToolsSerializeCleanly() {
        // Verifies the Encodable tool definitions produce valid JSON
        XCTAssertEqual(MCPServer.tools.count, 2)
        let data = try! JSONEncoder().encode(MCPServer.tools)
        XCTAssertGreaterThan(data.count, 0)
    }
}

// MARK: - Tools/call read tests

final class ReadToolTests: XCTestCase {
    func testReadCallsReaderWithDefaults() {
        let (server, reader, _) = makeServer()
        _ = server.handleLine(jsonRequest(method: "tools/call", params: [
            "name": "read_recent_imessages",
        ]))
        XCTAssertEqual(reader.lastHours, 24)
        XCTAssertEqual(reader.lastLimit, 50)
    }

    func testReadCallsReaderWithCustomArgs() {
        let (server, reader, _) = makeServer()
        _ = server.handleLine(jsonRequest(method: "tools/call", params: [
            "name": "read_recent_imessages",
            "arguments": ["hours": 48, "limit": 100],
        ]))
        XCTAssertEqual(reader.lastHours, 48)
        XCTAssertEqual(reader.lastLimit, 100)
    }

    func testReadReturnsRows() {
        let reader = MockReader()
        reader.rows = [
            IMessageRow(timestampUtc: "2026-05-09T12:00:00.000Z", fromMe: true,
                        contact: "+1234", chatIdentifier: "c1", chatDisplayName: "Test", text: "hi"),
        ]
        let (server, _, _) = makeServer(reader: reader)
        let resp = parseResponse(server.handleLine(jsonRequest(method: "tools/call", params: [
            "name": "read_recent_imessages",
        ])))!
        let result = resp["result"] as! [String: Any]
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = result["content"] as! [[String: Any]]
        let text = content[0]["text"] as! String
        XCTAssertTrue(text.contains("hi"))
    }

    func testReadReturnsErrorOnFailure() {
        let reader = MockReader()
        reader.error = MCPError.databaseOpen("no such file")
        let (server, _, _) = makeServer(reader: reader)
        let resp = parseResponse(server.handleLine(jsonRequest(method: "tools/call", params: [
            "name": "read_recent_imessages",
        ])))!
        let result = resp["result"] as! [String: Any]
        XCTAssertEqual(result["isError"] as? Bool, true)
        let content = result["content"] as! [[String: Any]]
        let text = content[0]["text"] as! String
        XCTAssertTrue(text.contains("Error:"))
    }
}

// MARK: - Tools/call send tests

final class SendToolTests: XCTestCase {
    func testSendCallsSenderWithArgs() {
        let (server, _, sender) = makeServer()
        _ = server.handleLine(jsonRequest(method: "tools/call", params: [
            "name": "send_imessage",
            "arguments": ["recipient": "+13125551234", "message": "hello"],
        ]))
        XCTAssertEqual(sender.lastRecipient, "+13125551234")
        XCTAssertEqual(sender.lastMessage, "hello")
    }

    func testSendReturnsConfirmation() {
        let sender = MockSender()
        sender.result = "Sent iMessage to +13125551234 (5 chars)."
        let (server, _, _) = makeServer(sender: sender)
        let resp = parseResponse(server.handleLine(jsonRequest(method: "tools/call", params: [
            "name": "send_imessage",
            "arguments": ["recipient": "+13125551234", "message": "hello"],
        ])))!
        let result = resp["result"] as! [String: Any]
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = result["content"] as! [[String: Any]]
        XCTAssertTrue((content[0]["text"] as! String).contains("Sent"))
    }

    func testSendMissingRecipient() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(jsonRequest(method: "tools/call", params: [
            "name": "send_imessage",
            "arguments": ["message": "hello"],
        ])))!
        let result = resp["result"] as! [String: Any]
        XCTAssertEqual(result["isError"] as? Bool, true)
    }

    func testSendMissingMessage() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(jsonRequest(method: "tools/call", params: [
            "name": "send_imessage",
            "arguments": ["recipient": "+13125551234"],
        ])))!
        let result = resp["result"] as! [String: Any]
        XCTAssertEqual(result["isError"] as? Bool, true)
    }

    func testSendReturnsErrorOnFailure() {
        let sender = MockSender()
        sender.error = MCPError.sendFailed(status: 1, stderr: "boom")
        let (server, _, _) = makeServer(sender: sender)
        let resp = parseResponse(server.handleLine(jsonRequest(method: "tools/call", params: [
            "name": "send_imessage",
            "arguments": ["recipient": "+13125551234", "message": "hello"],
        ])))!
        let result = resp["result"] as! [String: Any]
        XCTAssertEqual(result["isError"] as? Bool, true)
        let content = result["content"] as! [[String: Any]]
        XCTAssertTrue((content[0]["text"] as! String).contains("boom"))
    }
}

// MARK: - JSON-RPC protocol tests

final class ProtocolTests: XCTestCase {
    func testResponseMirrorsIntId() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(jsonRequest(method: "ping", id: 42)))!
        XCTAssertEqual(resp["id"] as? Int, 42)
    }

    func testResponseMirrorsStringId() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(jsonRequest(method: "ping", id: "req-7")))!
        XCTAssertEqual(resp["id"] as? String, "req-7")
    }

    func testResponseHasJsonrpcVersion() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(jsonRequest(method: "ping")))!
        XCTAssertEqual(resp["jsonrpc"] as? String, "2.0")
    }

    func testMissingMethodReturnsError() {
        let (server, _, _) = makeServer()
        let line = "{\"jsonrpc\":\"2.0\",\"id\":1}"
        let resp = parseResponse(server.handleLine(line))!
        XCTAssertNotNil(resp["error"])
        let err = resp["error"] as! [String: Any]
        XCTAssertEqual(err["code"] as? Int, -32600)
    }

    func testUnknownMethodReturnsError() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(jsonRequest(method: "bogus")))!
        XCTAssertNotNil(resp["error"])
        let err = resp["error"] as! [String: Any]
        XCTAssertEqual(err["code"] as? Int, -32601)
    }

    func testUnknownToolReturnsError() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(jsonRequest(method: "tools/call", params: [
            "name": "nonexistent",
        ])))!
        XCTAssertNotNil(resp["error"])
    }

    func testMissingToolNameReturnsError() {
        let (server, _, _) = makeServer()
        let resp = parseResponse(server.handleLine(jsonRequest(method: "tools/call", params: [:])))!
        XCTAssertNotNil(resp["error"])
    }

    func testNotificationReturnsNil() {
        let (server, _, _) = makeServer()
        // No "id" key → notification → no response
        let line = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
        XCTAssertNil(server.handleLine(line))
    }

    func testUnknownNotificationReturnsNil() {
        let (server, _, _) = makeServer()
        let line = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/whatever\"}"
        XCTAssertNil(server.handleLine(line))
    }

    func testInvalidJsonReturnsNil() {
        let (server, _, _) = makeServer()
        XCTAssertNil(server.handleLine("not json"))
    }

    func testEmptyObjectReturnsNil() {
        let (server, _, _) = makeServer()
        // No id and no method → nothing to respond to
        XCTAssertNil(server.handleLine("{}"))
    }

    func testResponseEndsWithNewline() {
        let (server, _, _) = makeServer()
        let data = server.handleLine(jsonRequest(method: "ping"))!
        XCTAssertEqual(data.last, 0x0A)
    }
}

// MARK: - MCPError tests

final class MCPErrorTests: XCTestCase {
    func testDatabaseOpenDescription() {
        let err = MCPError.databaseOpen("permission denied")
        XCTAssertTrue(err.localizedDescription.contains("permission denied"))
    }

    func testQueryFailedDescription() {
        let err = MCPError.queryFailed("no such table")
        XCTAssertTrue(err.localizedDescription.contains("no such table"))
    }

    func testEncodingFailedDescription() {
        let err = MCPError.encodingFailed
        XCTAssertTrue(err.localizedDescription.contains("UTF-8"))
    }

    func testSendFailedDescription() {
        let err = MCPError.sendFailed(status: 1, stderr: "error text")
        XCTAssertTrue(err.localizedDescription.contains("error text"))
    }

    func testInvalidRecipientDescription() {
        let err = MCPError.invalidRecipient("bad")
        XCTAssertTrue(err.localizedDescription.contains("bad"))
    }

    func testEquatable() {
        XCTAssertEqual(MCPError.encodingFailed, MCPError.encodingFailed)
        XCTAssertNotEqual(MCPError.encodingFailed, MCPError.databaseOpen("x"))
    }
}

// MARK: - Recipient validation tests

final class RecipientValidationTests: XCTestCase {
    func testValidE164PhonePassesValidation() {
        // Valid recipients should not throw invalidRecipient.
        // We test via the mock sender at the MCPServer level to avoid spawning osascript.
        let sender = MockSender()
        let server = MCPServer(reader: MockReader(), sender: sender)
        let resp = parseResponse(server.handleLine(jsonRequest(method: "tools/call", params: [
            "name": "send_imessage",
            "arguments": ["recipient": "+13125551234", "message": "hi"],
        ])))!
        let result = resp["result"] as! [String: Any]
        // Mock sender succeeds — no isError
        XCTAssertEqual(result["isError"] as? Bool, false)
        XCTAssertEqual(sender.lastRecipient, "+13125551234")
    }

    func testValidEmailPassesValidation() {
        let sender = MockSender()
        let server = MCPServer(reader: MockReader(), sender: sender)
        let resp = parseResponse(server.handleLine(jsonRequest(method: "tools/call", params: [
            "name": "send_imessage",
            "arguments": ["recipient": "user@example.com", "message": "hi"],
        ])))!
        let result = resp["result"] as! [String: Any]
        XCTAssertEqual(result["isError"] as? Bool, false)
        XCTAssertEqual(sender.lastRecipient, "user@example.com")
    }

    func testRejectsPlainText() {
        let sender = AppleScriptMessageSender()
        XCTAssertThrowsError(try sender.send(recipient: "not-a-number", message: "hi")) { error in
            XCTAssertEqual(error as? MCPError, MCPError.invalidRecipient("not-a-number"))
        }
    }

    func testRejectsEmptyString() {
        let sender = AppleScriptMessageSender()
        XCTAssertThrowsError(try sender.send(recipient: "", message: "hi")) { error in
            XCTAssertEqual(error as? MCPError, MCPError.invalidRecipient(""))
        }
    }

    func testRejectsPhoneWithoutPlus() {
        let sender = AppleScriptMessageSender()
        XCTAssertThrowsError(try sender.send(recipient: "13125551234", message: "hi")) { error in
            XCTAssertEqual(error as? MCPError, MCPError.invalidRecipient("13125551234"))
        }
    }
}
