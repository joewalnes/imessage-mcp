import XCTest
import SQLite3
@testable import IMMessageMCPLib

/// Creates an in-memory SQLite database from the fixture SQL, writes it to a
/// temp file, and returns the path. The caller is responsible for cleanup.
func createFixtureDB() throws -> String {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("fixtures/chat.sql")
    let sql = try String(contentsOf: fixtureURL, encoding: .utf8)

    let tmpDir = NSTemporaryDirectory()
    let dbPath = (tmpDir as NSString).appendingPathComponent("test-chat-\(UUID().uuidString).db")

    var db: OpaquePointer?
    guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
        throw NSError(domain: "Test", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Failed to create test DB"])
    }
    defer { sqlite3_close(db) }

    var errMsg: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(db, sql, nil, nil, &errMsg) == SQLITE_OK else {
        let msg = errMsg.map { String(cString: $0) } ?? "unknown"
        sqlite3_free(errMsg)
        throw NSError(domain: "Test", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "SQL error: \(msg)"])
    }
    return dbPath
}

final class SQLiteReaderTests: XCTestCase {
    var dbPath: String!
    var reader: SQLiteMessageReader!

    override func setUpWithError() throws {
        dbPath = try createFixtureDB()
        reader = SQLiteMessageReader(dbPath: dbPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    // MARK: - Basic read

    func testReadsAllRecentMessages() throws {
        // All fixture messages have dates around 800_366_400s (May 2026).
        // Use a huge hours window to get them all.
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        // 23 total messages minus 4 NULL text minus 1 ancient (outside 8760h window) = 18
        XCTAssertEqual(rows.count, 18)
    }

    func testOrderIsNewestFirst() throws {
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        for i in 0..<(rows.count - 1) {
            XCTAssertGreaterThanOrEqual(rows[i].timestampUtc, rows[i + 1].timestampUtc,
                                        "Row \(i) should be >= row \(i+1)")
        }
    }

    func testLimitCapsResults() throws {
        let rows = try reader.readRecent(hours: 8760, limit: 5)
        XCTAssertEqual(rows.count, 5)
    }

    // MARK: - NULL text filtering

    func testSkipsAttributedBodyOnlyMessages() throws {
        // msg 3: text=NULL, attributedBody=blob → should be skipped
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        let texts = rows.map { $0.text }
        XCTAssertEqual(rows.count, 18)
        XCTAssertFalse(texts.contains(where: { $0.isEmpty == false && $0.contains("bplist") }))
    }

    func testSkipsAttachmentOnlyMessages() throws {
        // msg 8: text=NULL, has attachment but no text → should be skipped
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        XCTAssertEqual(rows.count, 18)
    }

    func testIncludesEmptyStringText() throws {
        // msg 16: text="" (empty but not NULL) → should be included
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        XCTAssertTrue(rows.contains(where: { $0.text == "" }))
    }

    // MARK: - Field mapping

    func testFromMeField() throws {
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        let sent = rows.filter { $0.fromMe }
        let received = rows.filter { !$0.fromMe }
        XCTAssertGreaterThan(sent.count, 0)
        XCTAssertGreaterThan(received.count, 0)
    }

    func testContactField() throws {
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        let contacts = Set(rows.compactMap { $0.contact })
        XCTAssertTrue(contacts.contains("+15551001001"))
        XCTAssertTrue(contacts.contains("alice@example.com"))
        XCTAssertTrue(contacts.contains("+15551003003"))
    }

    func testChatIdentifierField() throws {
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        let chatIds = Set(rows.compactMap { $0.chatIdentifier })
        XCTAssertTrue(chatIds.contains("+15551001001"), "Should have 1:1 phone chat")
        XCTAssertTrue(chatIds.contains("alice@example.com"), "Should have 1:1 email chat")
        XCTAssertTrue(chatIds.contains("chat100200300"), "Should have group chat")
    }

    func testGroupChatDisplayName() throws {
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        let groupRows = rows.filter { $0.chatDisplayName == "Weekend Plans" }
        XCTAssertGreaterThan(groupRows.count, 0)
    }

    func testOneToOneChatDisplayNameIsNil() throws {
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        let directRows = rows.filter { $0.chatIdentifier == "+15551001001" }
        for row in directRows {
            XCTAssertNil(row.chatDisplayName)
        }
    }

    func testTimestampIsISO8601() throws {
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        let first = rows.first!
        // Should match ISO 8601 with fractional seconds
        XCTAssertTrue(first.timestampUtc.contains("T"))
        XCTAssertTrue(first.timestampUtc.contains("Z"))
    }

    // MARK: - Hours window

    func testHoursWindowFiltersOldMessages() throws {
        // The "Ancient message" is at 700_000_000s ≈ 2023.
        // With hours=1, only very recent messages should appear.
        // Since fixture data is from May 2026 and we're running now,
        // the hours filter depends on current time. Use a small window
        // that definitely excludes everything.
        let rows = try reader.readRecent(hours: 1, limit: 100)
        // All fixture messages are from a fixed date in 2026, not "now",
        // so with hours=1 from actual current time, they may or may not appear.
        // But the ancient message at 700_000_000_000_000_000 ns should never appear.
        let ancient = rows.filter { $0.text == "Ancient message" }
        XCTAssertEqual(ancient.count, 0)
    }

    // MARK: - Service types

    func testIncludesSMSMessages() throws {
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        let sms = rows.filter { $0.text == "Your package has been delivered" }
        XCTAssertEqual(sms.count, 1)
    }

    func testIncludesRCSMessages() throws {
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        let rcs = rows.filter { $0.text == "Hey this is RCS now" }
        XCTAssertEqual(rcs.count, 1)
    }

    // MARK: - Messages with attachments

    func testIncludesMessageWithAttachmentAndCaption() throws {
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        let withCaption = rows.filter { $0.text == "Screenshot of the build output" }
        XCTAssertEqual(withCaption.count, 1)
    }

    // MARK: - Tapbacks

    func testIncludesTapbacksWithText() throws {
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        let tapbacks = rows.filter { $0.text.contains("Loved") || $0.text.contains("Liked") }
        XCTAssertGreaterThan(tapbacks.count, 0)
    }

    // MARK: - System messages

    func testIncludesSystemMessages() throws {
        let rows = try reader.readRecent(hours: 8760, limit: 100)
        let system = rows.filter { $0.text.contains("named the conversation") }
        XCTAssertEqual(system.count, 1)
        // System messages have handle_id=0, so contact should be nil
        XCTAssertNil(system.first?.contact)
    }

    // MARK: - Error handling

    func testThrowsOnBadPath() {
        let reader = SQLiteMessageReader(dbPath: "/nonexistent/chat.db")
        XCTAssertThrowsError(try reader.readRecent(hours: 24, limit: 50)) { error in
            XCTAssertTrue(error is MCPError)
        }
    }
}
