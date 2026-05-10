# Changelog

## 2026-05-09

- Refactor to protocol-based DI with MCPServer class, MockReader/MockSender for testing
- Replace all `[String: Any]` response construction with Encodable types (JSONRPCId, ToolDef, IMessageRow, etc.)
- Add typed MCPError enum replacing NSError
- Add recipient validation (E.164 phone or email) in AppleScriptMessageSender
- Add 58 unit tests covering JSON-RPC protocol, tool dispatch, error handling, encoding
- Fix: remove redundant COALESCE in SQL, fix stdout pipe deadlock, static ISO8601DateFormatter
- Add project setup files (CLAUDE.md, TODO.md, DIARY.md, CHANGELOG.md)

## 2026-05-09 (initial)

- Initial release: MCP server with `read_recent_imessages` and `send_imessage` tools
- Makefile-based build producing `iMessageMCP.app` bundle
- Adhoc code signing for TCC/Full Disk Access
