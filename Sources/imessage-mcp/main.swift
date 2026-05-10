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

// MARK: - JSON-RPC stdio transport

func writeJSON(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A])) // '\n'
}

func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
    return [
        "jsonrpc": "2.0",
        "id": id ?? NSNull(),
        "error": ["code": code, "message": message],
    ]
}

func successResponse(id: Any?, result: [String: Any]) -> [String: Any] {
    return [
        "jsonrpc": "2.0",
        "id": id ?? NSNull(),
        "result": result,
    ]
}

func toolResult(text: String, isError: Bool = false) -> [String: Any] {
    return [
        "content": [["type": "text", "text": text]],
        "isError": isError,
    ]
}

// MARK: - Tool: read_recent_imessages

struct IMessageRow {
    let timestampUtc: String
    let fromMe: Bool
    let contact: String?
    let chatIdentifier: String?
    let chatDisplayName: String?
    let text: String
}

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

func readRecentIMessages(hours: Int, limit: Int) throws -> [IMessageRow] {
    let chatDbPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/Messages/chat.db")
    let uri = "file:\(chatDbPath)?mode=ro"

    var db: OpaquePointer?
    let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
    if sqlite3_open_v2(uri, &db, flags, nil) != SQLITE_OK {
        let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 failed"
        if let db = db { sqlite3_close(db) }
        throw NSError(domain: "ChatDB", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
    defer { sqlite3_close(db) }

    // Apple's reference date is 2001-01-01 UTC.
    // chat.db stores timestamps in nanoseconds since that date.
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
        let msg = String(cString: sqlite3_errmsg(db))
        throw NSError(domain: "ChatDB", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
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

// MARK: - Tool: send_imessage

func sendIMessage(recipient: String, message: String) throws -> String {
    // Pass recipient + message as argv to avoid AppleScript quoting injection.
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
        throw NSError(
            domain: "Send",
            code: Int(proc.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "osascript exit \(proc.terminationStatus): \(errStr)"]
        )
    }
    return "Sent iMessage to \(recipient) (\(message.count) chars)."
}

// MARK: - MCP method dispatch

let TOOLS: [[String: Any]] = [
    [
        "name": "read_recent_imessages",
        "description":
            "Return recent iMessage / SMS messages from the live ~/Library/Messages/chat.db, "
            + "newest first. Each row: timestamp_utc, from_me, contact, chat_identifier, "
            + "chat_display_name, text. Messages with NULL text (some rich-content iMessages "
            + "whose body lives in attributedBody) are skipped.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "hours": ["type": "integer", "default": 24, "description": "How far back to look (1–8760). Default 24."],
                "limit": ["type": "integer", "default": 50, "description": "Max messages, newest-first (1–1000). Default 50."],
            ],
        ],
    ],
    [
        "name": "send_imessage",
        "description":
            "Send an iMessage (or SMS fallback) to a phone number or iCloud email via "
            + "Messages.app on the host Mac.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "recipient": ["type": "string", "description": "Phone in E.164 (e.g. \"+13125551234\") or iCloud email."],
                "message": ["type": "string", "description": "Plain-text body."],
            ],
            "required": ["recipient", "message"],
        ],
    ],
]

func handleInitialize(id: Any?, params: [String: Any]?) {
    let protocolVersion = (params?["protocolVersion"] as? String) ?? "2024-11-05"
    let result: [String: Any] = [
        "protocolVersion": protocolVersion,
        "capabilities": ["tools": [String: Any]()],
        "serverInfo": ["name": "imessage-mcp", "version": "1.0.0"],
    ]
    writeJSON(successResponse(id: id, result: result))
}

func handleToolsList(id: Any?) {
    writeJSON(successResponse(id: id, result: ["tools": TOOLS]))
}

func intArg(_ args: [String: Any], _ key: String, default defaultValue: Int) -> Int {
    if let n = args[key] as? NSNumber { return n.intValue }
    if let s = args[key] as? String, let i = Int(s) { return i }
    return defaultValue
}

func handleToolsCall(id: Any?, params: [String: Any]?) {
    guard let name = params?["name"] as? String else {
        writeJSON(errorResponse(id: id, code: -32602, message: "Missing 'name' in params"))
        return
    }
    let args = (params?["arguments"] as? [String: Any]) ?? [:]

    do {
        switch name {
        case "read_recent_imessages":
            let hours = intArg(args, "hours", default: 24)
            let limit = intArg(args, "limit", default: 50)
            let rows = try readRecentIMessages(hours: hours, limit: limit)
            let dicts: [[String: Any]] = rows.map { r in
                [
                    "timestamp_utc": r.timestampUtc,
                    "from_me": r.fromMe,
                    "contact": r.contact ?? NSNull(),
                    "chat_identifier": r.chatIdentifier ?? NSNull(),
                    "chat_display_name": r.chatDisplayName ?? NSNull(),
                    "text": r.text,
                ]
            }
            let json = try JSONSerialization.data(withJSONObject: dicts, options: [.sortedKeys])
            guard let text = String(data: json, encoding: .utf8) else {
                throw NSError(domain: "Encoding", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "JSON UTF-8 encoding failed"])
            }
            writeJSON(successResponse(id: id, result: toolResult(text: text)))

        case "send_imessage":
            guard let recipient = args["recipient"] as? String,
                  let message = args["message"] as? String
            else {
                writeJSON(successResponse(
                    id: id,
                    result: toolResult(text: "Missing required arguments: recipient and message", isError: true)
                ))
                return
            }
            let confirmation = try sendIMessage(recipient: recipient, message: message)
            writeJSON(successResponse(id: id, result: toolResult(text: confirmation)))

        default:
            writeJSON(errorResponse(id: id, code: -32601, message: "Unknown tool: \(name)"))
        }
    } catch {
        writeJSON(successResponse(
            id: id,
            result: toolResult(text: "Error: \(error.localizedDescription)", isError: true)
        ))
    }
}

func handleRequest(_ line: String) {
    guard let data = line.data(using: .utf8) else { return }
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        FileHandle.standardError.write(Data("Failed to parse JSON: \(line)\n".utf8))
        return
    }

    let id = obj["id"]
    guard let method = obj["method"] as? String else {
        writeJSON(errorResponse(id: id, code: -32600, message: "Missing 'method'"))
        return
    }
    let params = obj["params"] as? [String: Any]

    switch method {
    case "initialize":
        handleInitialize(id: id, params: params)
    case "notifications/initialized":
        // JSON-RPC notification — no response expected.
        break
    case "tools/list":
        handleToolsList(id: id)
    case "tools/call":
        handleToolsCall(id: id, params: params)
    case "ping":
        writeJSON(successResponse(id: id, result: [:]))
    default:
        if id != nil {
            writeJSON(errorResponse(id: id, code: -32601, message: "Method not found: \(method)"))
        }
        // Unknown notifications: silently ignore.
    }
}

// MARK: - Main loop

while let line = readLine() {
    if line.isEmpty { continue }
    handleRequest(line)
}
