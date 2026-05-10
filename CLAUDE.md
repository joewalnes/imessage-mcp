# imessage-mcp

Native macOS MCP server for reading and sending iMessages. Single Swift binary, packaged as a `.app` bundle for TCC/Full Disk Access.

## Build

```bash
make          # builds release binary, assembles + signs iMessageMCP.app
make clean    # removes .app, .build, swift package artifacts
```

Requires macOS 13+ and the Swift toolchain (Xcode or Command Line Tools).

## Project layout

```
Sources/imessage-mcp/main.swift   — entire server (JSON-RPC transport, SQLite queries, AppleScript send)
Resources/Info.plist              — app bundle metadata
Scripts/make_icon.swift           — generates the app icon at build time
Makefile                          — builds, bundles, and adhoc-signs the .app
```

## Architecture

- **Read path:** opens `~/Library/Messages/chat.db` directly via the SQLite3 C API (read-only).
- **Send path:** shells out to `osascript` with an inline AppleScript. Recipient and message are passed as argv, not interpolated.
- **Transport:** newline-delimited JSON-RPC 2.0 over stdio.
- **TCC:** the `.app` bundle is the FDA subject; child processes inherit access via macOS responsibility chain.

## Bug tracking

Bugs and tasks are tracked in `TODO.md`. Use `/todo` to add entries and `/bug-bash` to work through them.

## Engineering diary

Maintain `DIARY.md` — add an entry when making significant changes, architectural decisions, or non-obvious tradeoffs. Latest entries at top. Write in narrative form, not bullet dumps. Focus on *why* and *context*, not *what* (that's in the commits).

## Changelog

Update `CHANGELOG.md` with every commit. Format: grouped by date (newest first), one bullet per change with a short description. Keep it human-readable — no commit hashes, no authors.

## Code quality

Run `/scorecard` periodically — after completing a feature, before major PRs, or when onboarding to assess health. Address critical findings before moving on.

## Commits

Break work into small atomic commits — one logical change per commit. Don't bundle unrelated changes. A bug fix, a new feature, and a refactor are three commits, not one.

## Pre-commit checks

Always build before committing:
```bash
swift build    # ensure it compiles
```
This project does not yet have tests or a linter. When tests are added, run them before every commit.

## Test-first

Before implementing a feature or fix:
1. Write a test that captures the expected behavior
2. Run it — verify it **fails** (if it passes, the test isn't testing the right thing)
3. Implement until the test passes
4. Keep a healthy mix: fast unit tests for logic, end-to-end integration tests to validate it actually works in context

Don't skip step 2 — a test that never failed never caught anything.

## Documentation

Update README.md (and any relevant docs) before committing if the change affects:
- Public API, CLI interface, or configuration
- Setup/installation steps
- Feature behavior visible to users

## Evolving preferences

When the user expresses a coding preference, convention, or correction during a session, offer to encode it into this CLAUDE.md file so it persists across sessions. Examples: naming conventions, preferred libraries, architecture patterns, things to avoid.

## Mistake retrospectives

When you make a mistake (especially forgetting something the user asked for):
1. Acknowledge it directly
2. Identify the root cause — why did this happen?
3. Suggest a concrete project change to prevent recurrence (add a rule to CLAUDE.md, add a pre-commit check, create a checklist)
Don't just apologize — fix the system.
