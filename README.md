# imessage-mcp

A native macOS [MCP](https://modelcontextprotocol.io/) server that lets a local
LLM agent read and send iMessages on your own Mac.

It's a single Swift binary, packaged as a `.app` bundle so macOS can grant it
Full Disk Access (and therefore read access to `~/Library/Messages/chat.db`)
cleanly. Speaks plain JSON-RPC 2.0 over stdio, so it works with any MCP client
(Claude Desktop, custom agents, etc.).

## Why this exists

`~/Library/Messages/chat.db` is protected by macOS TCC under "Full Disk Access".
Granting FDA to:

- `/usr/bin/sqlite3` — silently rejected by TCC (Apple-shipped binary, sealed
  `com.apple.provenance` xattr).
- a shell-script wrapper — TCC doesn't honor script-level grants.
- a copy of `sqlite3` — provenance xattr survives copy and can't be removed
  from userspace.
- a Docker volume mount — works, but ties chat.db reads to a container runtime
  and breaks when the runtime changes.

A proper `.app` bundle with its own `CFBundleIdentifier` is the abstraction TCC
was actually designed for. Adhoc-signed bundles are grantable (Hammerspoon and
Karabiner-Elements use the same pattern). Once the bundle has FDA, the binary
inside it can open chat.db directly.

## Tools

### `read_recent_imessages`

Returns recent messages from the live `~/Library/Messages/chat.db`,
newest-first.

Args:
- `hours` (int, default 24) — how far back to look.
- `limit` (int, default 50) — max messages.

Each row contains: `timestamp_utc`, `from_me`, `contact`, `chat_identifier`,
`chat_display_name`, `text`.

Messages whose body lives in the `attributedBody` blob (some rich-content
iMessages) have NULL `text` and are skipped.

### `send_imessage`

Sends an iMessage (or SMS fallback) via Messages.app on the host.

Args:
- `recipient` — phone in E.164 (`+13125551234`) or iCloud email.
- `message` — plain-text body.

Implemented by piping a tiny AppleScript to `osascript`, with the recipient and
message passed as `argv` (not interpolated into the script source) so there's
no AppleScript injection.

## Build

Requires macOS 13+ and the Swift toolchain (Xcode or Command Line Tools).

```bash
git clone https://github.com/joewalnes/imessage-mcp
cd imessage-mcp
make
```

That produces `iMessageMCP.app` in the checkout. There is no separate install
step — the `.app` lives next to the source.

## Setup

1. **Grant Full Disk Access** to the `.app`:
   System Settings → Privacy & Security → Full Disk Access → `+` → pick or
   paste the absolute path to `iMessageMCP.app` in your checkout.

2. **Point your MCP client** at the binary inside the bundle. Example for
   Claude Desktop (`~/Library/Application Support/Claude/claude_desktop_config.json`):

   ```json
   {
     "mcpServers": {
       "imessage": {
         "command": "/absolute/path/to/imessage-mcp/iMessageMCP.app/Contents/MacOS/iMessageMCP"
       }
     }
   }
   ```

   Other MCP clients: spawn `iMessageMCP.app/Contents/MacOS/iMessageMCP` as a
   stdio child process. No args.

3. Restart your MCP client.

4. Test:
   > what are my last 5 texts?

### Optional: install to /Applications

If you'd rather not have the bundle in your dev tree:

```bash
cp -R iMessageMCP.app /Applications/
```

Then grant FDA to `/Applications/iMessageMCP.app` and point your MCP client at
that path. Re-running `make` won't update `/Applications` — you'd need to copy
again.

## Requirements

- macOS 13+ (Ventura or newer; tested on Tahoe / 26).
- Swift toolchain (Apple's, via Xcode or Command Line Tools).
- Messages.app signed in to iMessage for `send_imessage`.

## Known limitations

- **`attributedBody` is not parsed.** iMessages with rich content (effects,
  some replies) store their body as an `NSKeyedArchiver` blob in
  `attributedBody`. Decoding it from Swift would mean unarchiving Foundation
  classes; for now those rows are skipped. Plain text messages are unaffected.
- **No attachments.** Attachment metadata isn't surfaced.
- **No reactions / tapbacks.** They're stored as separate messages with
  `associated_message_*` columns, currently not joined in.
- **FDA grant survives rebuilds.** As long as the bundle stays at the same
  path with the same bundle ID (`io.github.joewalnes.imessage-mcp`), `make`
  rebuilds preserve the FDA grant. If you move the checkout, you'll need to
  re-grant.
- **Send is synchronous and trusts Messages.app.** If Messages.app isn't
  signed in or the buddy isn't reachable, you'll get an `osascript exit N`
  error back through the tool result.

## Architecture

```
┌──────────────────┐ stdio (NDJSON JSON-RPC) ┌──────────────────────┐
│   MCP client     │ ───────────────────────▶│   iMessageMCP.app/   │
│   (Claude        │ ◀───────────────────────│   Contents/MacOS/    │
│    Desktop, ...) │                         │   iMessageMCP        │
└──────────────────┘                         └─────────┬────────────┘
                                                       │
                            ┌──────────────────────────┴─────────────┐
                            ▼                                        ▼
                  ~/Library/Messages/chat.db          /usr/bin/osascript
                  (sqlite3 C API, read-only)         (send via Messages.app)
```

The bundle is the TCC subject. The binary inside it inherits the bundle's FDA
grant. `osascript` is launched as a child process and inherits TCC
responsibility via macOS's responsibility chain, so it can drive Messages.app
without its own grant.

## License

MIT — see [LICENSE](LICENSE).
