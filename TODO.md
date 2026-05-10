# Todo

<!-- Format: [status] P<priority> (category) Title -->
<!-- Status: [ ] open, [~] in progress, [x] done, [-] won't fix -->
<!-- Priority: P0 critical, P1 high, P2 medium, P3 low -->
<!-- Category: bug, feature, chore, docs -->

## Open

- [ ] **P2** (feature) Parse `attributedBody` blob for rich-content iMessages
  Currently these rows are skipped (NULL text). Would require `NSKeyedUnarchiver`.

- [ ] **P2** (feature) Surface attachment metadata
  Attachment info exists in chat.db but isn't queried.

- [ ] **P3** (feature) Include reactions / tapbacks
  Stored as separate messages with `associated_message_*` columns.

- [x] **P2** (chore) Add tests — 2026-05-09
  Resolved: Split into IMMessageMCPLib + executable. 19 tests covering intArg, response builders, tool registry, writeJSON.

## Done
