# Engineering Diary

Latest entries first. Record significant decisions, architecture changes, and non-obvious context.

---

## 2026-05-09 — Project setup

Single-file Swift MCP server that reads `~/Library/Messages/chat.db` and sends
via AppleScript. Packaged as a `.app` bundle because that's the only way to get
a stable TCC/Full Disk Access grant on macOS — shell scripts, copied binaries,
and Docker mounts all fail for different reasons (see README for details).

Key decisions:
- **Single source file** — the server is small enough that splitting it would
  add complexity without benefit. JSON-RPC transport, SQLite queries, and
  AppleScript send all live in `main.swift`.
- **Makefile over `install.sh`** — the app bundle builds in-place next to the
  source. No `/Applications` install step needed; FDA grant survives rebuilds as
  long as the path and bundle ID stay the same.
- **Adhoc signing** — no Apple Developer account needed. TCC accepts adhoc-signed
  bundles for FDA grants.
- **argv for AppleScript** — recipient and message are passed as process arguments
  rather than interpolated into the script source, preventing AppleScript injection.
