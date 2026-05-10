// imessage-mcp — Native macOS MCP server for reading/sending iMessages.
//
// Speaks JSON-RPC 2.0 (MCP) over stdio (newline-delimited JSON).
// Reads ~/Library/Messages/chat.db live; sends via Messages.app + osascript.
//
// Designed to be packaged as a .app bundle (see Makefile) so macOS TCC
// can grant Full Disk Access at the bundle level. Child processes (osascript)
// inherit access via macOS's responsibility chain.

import Foundation
import SQLite3

// MARK: - Errors

public enum MCPError: LocalizedError, Equatable {
    case databaseOpen(String)
    case queryFailed(String)
    case encodingFailed
    case sendFailed(status: Int32, stderr: String)
    case invalidRecipient(String)

    public var errorDescription: String? {
        switch self {
        case .databaseOpen(let msg): return "Failed to open chat database: \(msg)"
        case .queryFailed(let msg): return "Query failed: \(msg)"
        case .encodingFailed: return "JSON UTF-8 encoding failed"
        case .sendFailed(let status, let stderr): return "osascript exit \(status): \(stderr)"
        case .invalidRecipient(let r): return "Invalid recipient '\(r)': expected E.164 phone or email"
        }
    }
}

// MARK: - JSON-RPC types

public enum JSONRPCId: Equatable {
    case int(Int)
    case string(String)
    case null

    static func from(_ value: Any?) -> JSONRPCId? {
        guard let value = value else { return nil }
        if value is NSNull { return .null }
        if let n = value as? NSNumber { return .int(n.intValue) }
        if let s = value as? String { return .string(s) }
        return nil
    }
}

extension JSONRPCId: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let n): try container.encode(n)
        case .string(let s): try container.encode(s)
        case .null: try container.encodeNil()
        }
    }
}

struct JSONRPCSuccess<T: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: JSONRPCId
    let result: T
}

struct JSONRPCError: Encodable {
    let jsonrpc = "2.0"
    let id: JSONRPCId
    let error: JSONRPCErrorDetail
}

struct JSONRPCErrorDetail: Encodable {
    let code: Int
    let message: String
}

// MARK: - MCP types

public struct IMessageRow: Encodable, Equatable {
    public let timestampUtc: String
    public let fromMe: Bool
    public let contact: String?
    public let chatIdentifier: String?
    public let chatDisplayName: String?
    public let text: String

    public init(timestampUtc: String, fromMe: Bool, contact: String?,
                chatIdentifier: String?, chatDisplayName: String?, text: String) {
        self.timestampUtc = timestampUtc
        self.fromMe = fromMe
        self.contact = contact
        self.chatIdentifier = chatIdentifier
        self.chatDisplayName = chatDisplayName
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case timestampUtc = "timestamp_utc"
        case fromMe = "from_me"
        case contact
        case chatIdentifier = "chat_identifier"
        case chatDisplayName = "chat_display_name"
        case text
    }

    // Encode nil as null rather than omitting the key.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(timestampUtc, forKey: .timestampUtc)
        try c.encode(fromMe, forKey: .fromMe)
        try c.encode(contact, forKey: .contact)
        try c.encode(chatIdentifier, forKey: .chatIdentifier)
        try c.encode(chatDisplayName, forKey: .chatDisplayName)
        try c.encode(text, forKey: .text)
    }
}

struct ToolContent: Encodable {
    let type = "text"
    let text: String
}

struct ToolCallResult: Encodable {
    let content: [ToolContent]
    let isError: Bool

    init(text: String, isError: Bool = false) {
        self.content = [ToolContent(text: text)]
        self.isError = isError
    }
}

struct InitializeResult: Encodable {
    let protocolVersion: String
    let capabilities: InitCapabilities
    let serverInfo: ServerInfo
}

struct InitCapabilities: Encodable {
    let tools = [String: String]()
}

struct ServerInfo: Encodable {
    let name: String
    let version: String
}

struct ToolsListResult: Encodable {
    let tools: [ToolDef]
}

public struct ToolDef: Encodable {
    let name: String
    let description: String
    let inputSchema: ToolInputSchema
}

struct ToolInputSchema: Encodable {
    let type = "object"
    let properties: [String: ToolProperty]
    var required: [String]?
}

struct ToolProperty: Encodable {
    let type: String
    let description: String
    var defaultValue: Int?

    enum CodingKeys: String, CodingKey {
        case type, description
        case defaultValue = "default"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(description, forKey: .description)
        if let d = defaultValue { try c.encode(d, forKey: .defaultValue) }
    }
}

// MARK: - Protocols

public protocol MessageReader {
    func readRecent(hours: Int, limit: Int) throws -> [IMessageRow]
}

public protocol MessageSender {
    func send(recipient: String, message: String) throws -> String
}

// MARK: - MCPServer

public final class MCPServer {
    private let reader: MessageReader
    private let sender: MessageSender

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()

    public static let tools: [ToolDef] = [
        ToolDef(
            name: "read_recent_imessages",
            description: "Return recent iMessage / SMS messages from the live "
                + "~/Library/Messages/chat.db, newest first. Each row: timestamp_utc, "
                + "from_me, contact, chat_identifier, chat_display_name, text. Messages "
                + "with NULL text (some rich-content iMessages whose body lives in "
                + "attributedBody) are skipped.",
            inputSchema: ToolInputSchema(properties: [
                "hours": ToolProperty(type: "integer", description: "How far back to look (1–8760). Default 24.", defaultValue: 24),
                "limit": ToolProperty(type: "integer", description: "Max messages, newest-first (1–1000). Default 50.", defaultValue: 50),
            ])
        ),
        ToolDef(
            name: "send_imessage",
            description: "Send an iMessage (or SMS fallback) to a phone number or "
                + "iCloud email via Messages.app on the host Mac.",
            inputSchema: ToolInputSchema(
                properties: [
                    "recipient": ToolProperty(type: "string", description: "Phone in E.164 (e.g. \"+13125551234\") or iCloud email."),
                    "message": ToolProperty(type: "string", description: "Plain-text body."),
                ],
                required: ["recipient", "message"]
            )
        ),
    ]

    public init(reader: MessageReader, sender: MessageSender) {
        self.reader = reader
        self.sender = sender
    }

    /// Process one line of NDJSON input. Returns response bytes (with trailing newline)
    /// or nil for notifications / unparseable input.
    public func handleLine(_ line: String) -> Data? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let hasId = obj.keys.contains("id")
        let id = JSONRPCId.from(obj["id"]) ?? .null

        guard let method = obj["method"] as? String else {
            return hasId ? encodeError(id: id, code: -32600, message: "Missing 'method'") : nil
        }

        let params = obj["params"] as? [String: Any]

        switch method {
        case "initialize":
            return handleInitialize(id: id, params: params)
        case "notifications/initialized":
            return nil
        case "tools/list":
            return encodeSuccess(id: id, result: ToolsListResult(tools: MCPServer.tools))
        case "tools/call":
            return handleToolsCall(id: id, params: params)
        case "ping":
            return encodeSuccess(id: id, result: [String: String]())
        default:
            return hasId ? encodeError(id: id, code: -32601, message: "Method not found: \(method)") : nil
        }
    }

    // MARK: - Handlers

    private func handleInitialize(id: JSONRPCId, params: [String: Any]?) -> Data? {
        let version = (params?["protocolVersion"] as? String) ?? "2024-11-05"
        return encodeSuccess(id: id, result: InitializeResult(
            protocolVersion: version,
            capabilities: InitCapabilities(),
            serverInfo: ServerInfo(name: "imessage-mcp", version: "1.0.0")
        ))
    }

    private func handleToolsCall(id: JSONRPCId, params: [String: Any]?) -> Data? {
        guard let name = params?["name"] as? String else {
            return encodeError(id: id, code: -32602, message: "Missing 'name' in params")
        }
        let args = (params?["arguments"] as? [String: Any]) ?? [:]

        switch name {
        case "read_recent_imessages":
            return handleReadMessages(id: id, args: args)
        case "send_imessage":
            return handleSendMessage(id: id, args: args)
        default:
            return encodeError(id: id, code: -32601, message: "Unknown tool: \(name)")
        }
    }

    private func handleReadMessages(id: JSONRPCId, args: [String: Any]) -> Data? {
        let hours = Self.intArg(args, "hours", default: 24)
        let limit = Self.intArg(args, "limit", default: 50)
        do {
            let rows = try reader.readRecent(hours: hours, limit: limit)
            let json = try Self.encoder.encode(rows)
            guard let text = String(data: json, encoding: .utf8) else { throw MCPError.encodingFailed }
            return encodeSuccess(id: id, result: ToolCallResult(text: text))
        } catch {
            return encodeSuccess(id: id, result: ToolCallResult(text: "Error: \(error.localizedDescription)", isError: true))
        }
    }

    private func handleSendMessage(id: JSONRPCId, args: [String: Any]) -> Data? {
        guard let recipient = args["recipient"] as? String,
              let message = args["message"] as? String
        else {
            return encodeSuccess(id: id, result: ToolCallResult(
                text: "Missing required arguments: recipient and message", isError: true))
        }
        do {
            let confirmation = try sender.send(recipient: recipient, message: message)
            return encodeSuccess(id: id, result: ToolCallResult(text: confirmation))
        } catch {
            return encodeSuccess(id: id, result: ToolCallResult(
                text: "Error: \(error.localizedDescription)", isError: true))
        }
    }

    // MARK: - Helpers

    static func intArg(_ args: [String: Any], _ key: String, default defaultValue: Int) -> Int {
        if let n = args[key] as? NSNumber { return n.intValue }
        if let s = args[key] as? String, let i = Int(s) { return i }
        return defaultValue
    }

    private func encodeSuccess<T: Encodable>(id: JSONRPCId, result: T) -> Data? {
        guard var data = try? Self.encoder.encode(JSONRPCSuccess(id: id, result: result)) else { return nil }
        data.append(0x0A)
        return data
    }

    private func encodeError(id: JSONRPCId, code: Int, message: String) -> Data? {
        guard var data = try? Self.encoder.encode(
            JSONRPCError(id: id, error: JSONRPCErrorDetail(code: code, message: message))
        ) else { return nil }
        data.append(0x0A)
        return data
    }
}

// MARK: - SQLiteMessageReader

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

public final class SQLiteMessageReader: MessageReader {
    public init() {}

    public func readRecent(hours: Int, limit: Int) throws -> [IMessageRow] {
        let chatDbPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Messages/chat.db")
        let uri = "file:\(chatDbPath)?mode=ro"

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        if sqlite3_open_v2(uri, &db, flags, nil) != SQLITE_OK {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let db = db { sqlite3_close(db) }
            throw MCPError.databaseOpen(msg)
        }
        defer { sqlite3_close(db) }

        let cutoffSeconds = Date().timeIntervalSinceReferenceDate - Double(max(hours, 1)) * 3600
        let cutoffNs = Int64(cutoffSeconds * 1_000_000_000)

        let sql = """
        SELECT m.date, m.is_from_me, h.id, c.chat_identifier, c.display_name, m.text
        FROM message m
        LEFT JOIN handle h            ON m.handle_id = h.ROWID
        LEFT JOIN chat_message_join j ON m.ROWID    = j.message_id
        LEFT JOIN chat c              ON j.chat_id  = c.ROWID
        WHERE m.date > ?
          AND m.text IS NOT NULL
        ORDER BY m.date DESC
        LIMIT ?
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw MCPError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, cutoffNs)
        sqlite3_bind_int(stmt, 2, Int32(min(limit, 1000)))

        var rows: [IMessageRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let dateNs = sqlite3_column_int64(stmt, 0)
            let fromMe = sqlite3_column_int(stmt, 1) != 0
            let contact = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) }
            let chatId = sqlite3_column_text(stmt, 3).flatMap { String(cString: $0) }
            let displayName = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) }
            let text = sqlite3_column_text(stmt, 5).flatMap { String(cString: $0) } ?? ""

            let date = Date(timeIntervalSinceReferenceDate: TimeInterval(dateNs) / 1_000_000_000)
            rows.append(IMessageRow(
                timestampUtc: isoFormatter.string(from: date),
                fromMe: fromMe,
                contact: contact,
                chatIdentifier: chatId,
                chatDisplayName: displayName,
                text: text
            ))
        }
        return rows
    }
}

// MARK: - AppleScriptMessageSender

public final class AppleScriptMessageSender: MessageSender {
    public init() {}

    private static let recipientPattern = try! NSRegularExpression(
        pattern: #"^\+[1-9]\d{6,14}$|^[^@\s]+@[^@\s]+\.[^@\s]+$"#
    )

    public func send(recipient: String, message: String) throws -> String {
        let range = NSRange(recipient.startIndex..., in: recipient)
        guard Self.recipientPattern.firstMatch(in: recipient, range: range) != nil else {
            throw MCPError.invalidRecipient(recipient)
        }

        let script = """
        on run argv
          set targetBuddy to item 1 of argv
          set targetMessage to item 2 of argv
          tell application "Messages"
            set targetService to 1st account whose service type = iMessage
            set targetCell to participant targetBuddy of targetService
            send targetMessage to targetCell
          end tell
        end run
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-", recipient, message]

        let stdinPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardError = stderrPipe
        proc.standardOutput = FileHandle.nullDevice

        try proc.run()
        if let scriptData = script.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(scriptData)
        }
        try? stdinPipe.fileHandleForWriting.close()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "(no stderr)"
            throw MCPError.sendFailed(status: proc.terminationStatus, stderr: errStr)
        }
        return "Sent iMessage to \(recipient) (\(message.count) chars)."
    }
}
