-- Synthetic iMessage chat.db for testing.
-- Schema matches the real macOS chat.db (Tahoe / macOS 26).
-- All data is fake — no real messages, contacts, or identifiers.

-- ============================================================
-- Schema (subset: only tables the server reads or may read)
-- ============================================================

CREATE TABLE handle (
    ROWID INTEGER PRIMARY KEY AUTOINCREMENT UNIQUE,
    id TEXT NOT NULL,
    country TEXT,
    service TEXT NOT NULL,
    uncanonicalized_id TEXT,
    person_centric_id TEXT,
    UNIQUE (id, service)
);

CREATE TABLE chat (
    ROWID INTEGER PRIMARY KEY AUTOINCREMENT,
    guid TEXT UNIQUE NOT NULL,
    style INTEGER,
    state INTEGER,
    account_id TEXT,
    properties BLOB,
    chat_identifier TEXT,
    service_name TEXT,
    room_name TEXT,
    account_login TEXT,
    is_archived INTEGER DEFAULT 0,
    last_addressed_handle TEXT,
    display_name TEXT,
    group_id TEXT,
    is_filtered INTEGER,
    successful_query INTEGER,
    engram_id TEXT,
    server_change_token TEXT,
    ck_sync_state INTEGER DEFAULT 0,
    original_group_id TEXT,
    last_read_message_timestamp INTEGER DEFAULT 0,
    cloudkit_record_id TEXT,
    last_addressed_sim_id TEXT,
    is_blackholed INTEGER DEFAULT 0,
    syndication_date INTEGER DEFAULT 0,
    syndication_type INTEGER DEFAULT 0,
    is_recovered INTEGER DEFAULT 0,
    is_deleting_incoming_messages INTEGER DEFAULT 0,
    is_pending_review INTEGER DEFAULT 0
);

CREATE TABLE message (
    ROWID INTEGER PRIMARY KEY AUTOINCREMENT,
    guid TEXT UNIQUE NOT NULL,
    text TEXT,
    replace INTEGER DEFAULT 0,
    service_center TEXT,
    handle_id INTEGER DEFAULT 0,
    subject TEXT,
    country TEXT,
    attributedBody BLOB,
    version INTEGER DEFAULT 0,
    type INTEGER DEFAULT 0,
    service TEXT,
    account TEXT,
    account_guid TEXT,
    error INTEGER DEFAULT 0,
    date INTEGER,
    date_read INTEGER,
    date_delivered INTEGER,
    is_delivered INTEGER DEFAULT 0,
    is_finished INTEGER DEFAULT 0,
    is_emote INTEGER DEFAULT 0,
    is_from_me INTEGER DEFAULT 0,
    is_empty INTEGER DEFAULT 0,
    is_delayed INTEGER DEFAULT 0,
    is_auto_reply INTEGER DEFAULT 0,
    is_prepared INTEGER DEFAULT 0,
    is_read INTEGER DEFAULT 0,
    is_system_message INTEGER DEFAULT 0,
    is_sent INTEGER DEFAULT 0,
    has_dd_results INTEGER DEFAULT 0,
    is_service_message INTEGER DEFAULT 0,
    is_forward INTEGER DEFAULT 0,
    was_downgraded INTEGER DEFAULT 0,
    is_archive INTEGER DEFAULT 0,
    cache_has_attachments INTEGER DEFAULT 0,
    cache_roomnames TEXT,
    was_data_detected INTEGER DEFAULT 0,
    was_deduplicated INTEGER DEFAULT 0,
    is_audio_message INTEGER DEFAULT 0,
    is_played INTEGER DEFAULT 0,
    date_played INTEGER,
    item_type INTEGER DEFAULT 0,
    other_handle INTEGER DEFAULT 0,
    group_title TEXT,
    group_action_type INTEGER DEFAULT 0,
    share_status INTEGER DEFAULT 0,
    share_direction INTEGER DEFAULT 0,
    is_expirable INTEGER DEFAULT 0,
    expire_state INTEGER DEFAULT 0,
    message_action_type INTEGER DEFAULT 0,
    message_source INTEGER DEFAULT 0,
    associated_message_guid TEXT,
    associated_message_type INTEGER DEFAULT 0,
    balloon_bundle_id TEXT,
    payload_data BLOB,
    expressive_send_style_id TEXT,
    associated_message_range_location INTEGER DEFAULT 0,
    associated_message_range_length INTEGER DEFAULT 0,
    time_expressive_send_played INTEGER,
    message_summary_info BLOB,
    ck_sync_state INTEGER DEFAULT 0,
    ck_record_id TEXT,
    ck_record_change_tag TEXT,
    destination_caller_id TEXT,
    is_corrupt INTEGER DEFAULT 0,
    reply_to_guid TEXT,
    sort_id INTEGER,
    is_spam INTEGER DEFAULT 0,
    has_unseen_mention INTEGER DEFAULT 0,
    thread_originator_guid TEXT,
    thread_originator_part TEXT,
    syndication_ranges TEXT,
    synced_syndication_ranges TEXT,
    was_delivered_quietly INTEGER DEFAULT 0,
    did_notify_recipient INTEGER DEFAULT 0,
    date_retracted INTEGER,
    date_edited INTEGER,
    date_recovered INTEGER,
    was_detonated INTEGER DEFAULT 0,
    part_count INTEGER,
    is_stewie INTEGER DEFAULT 0,
    is_sos INTEGER DEFAULT 0,
    is_critical INTEGER DEFAULT 0,
    bia_reference_id TEXT,
    is_kt_verified INTEGER DEFAULT 0,
    fallback_hash TEXT,
    associated_message_emoji TEXT,
    is_pending_satellite_send INTEGER DEFAULT 0,
    needs_relay INTEGER DEFAULT 0,
    schedule_type INTEGER DEFAULT 0,
    schedule_state INTEGER DEFAULT 0,
    sent_or_received_off_grid INTEGER DEFAULT 0,
    is_time_sensitive INTEGER DEFAULT 0,
    ck_chat_id TEXT
);

CREATE TABLE chat_message_join (
    chat_id INTEGER REFERENCES chat (ROWID) ON DELETE CASCADE,
    message_id INTEGER REFERENCES message (ROWID) ON DELETE CASCADE,
    message_date INTEGER DEFAULT 0,
    PRIMARY KEY (chat_id, message_id)
);

CREATE TABLE attachment (
    ROWID INTEGER PRIMARY KEY AUTOINCREMENT,
    guid TEXT UNIQUE NOT NULL,
    filename TEXT,
    mime_type TEXT,
    transfer_name TEXT,
    total_bytes INTEGER DEFAULT 0,
    created_date INTEGER DEFAULT 0
);

CREATE TABLE message_attachment_join (
    message_id INTEGER REFERENCES message (ROWID),
    attachment_id INTEGER REFERENCES attachment (ROWID),
    PRIMARY KEY (message_id, attachment_id)
);

-- ============================================================
-- Synthetic test data
--
-- Timestamps: nanoseconds since 2001-01-01 UTC (macOS reference date).
-- Base: 2026-05-09 12:00:00 UTC = 800_366_400 seconds = 800_366_400_000_000_000 ns
-- Each message offset by N minutes (60_000_000_000 ns).
-- ============================================================

-- Contacts
INSERT INTO handle (ROWID, id, service) VALUES (1, '+15551001001', 'iMessage');
INSERT INTO handle (ROWID, id, service) VALUES (2, '+15551002002', 'iMessage');
INSERT INTO handle (ROWID, id, service) VALUES (3, 'alice@example.com', 'iMessage');
INSERT INTO handle (ROWID, id, service) VALUES (4, '+15551003003', 'SMS');
INSERT INTO handle (ROWID, id, service) VALUES (5, '+15551004004', 'RCS');

-- Chats: 1:1 iMessage, 1:1 email, group, SMS, RCS
INSERT INTO chat (ROWID, guid, chat_identifier, display_name, service_name, style)
    VALUES (1, 'iMessage;-;+15551001001', '+15551001001', NULL, 'iMessage', 45);
INSERT INTO chat (ROWID, guid, chat_identifier, display_name, service_name, style)
    VALUES (2, 'iMessage;-;alice@example.com', 'alice@example.com', NULL, 'iMessage', 45);
INSERT INTO chat (ROWID, guid, chat_identifier, display_name, service_name, style)
    VALUES (3, 'iMessage;+;chat100200300', 'chat100200300', 'Weekend Plans', 'iMessage', 43);
INSERT INTO chat (ROWID, guid, chat_identifier, display_name, service_name, style)
    VALUES (4, 'SMS;-;+15551003003', '+15551003003', NULL, 'SMS', 45);
INSERT INTO chat (ROWID, guid, chat_identifier, display_name, service_name, style)
    VALUES (5, 'RCS;-;+15551004004', '+15551004004', NULL, 'RCS', 45);

-- ==== 1:1 iMessage with +15551001001 ====

-- Plain text, received
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me, service, is_finished, is_sent)
    VALUES (1, 'AAAAAA-0001', 'Hey, are you free later?', 1,
            800366400000000000, 0, 'iMessage', 1, 0);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (1, 1, 800366400000000000);

-- Plain text, sent
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me, service, is_finished, is_sent)
    VALUES (2, 'AAAAAA-0002', 'Yeah, after 3pm works', 1,
            800366460000000000, 1, 'iMessage', 1, 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (1, 2, 800366460000000000);

-- Rich content (attributedBody only, text IS NULL) — reader should skip this
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me, attributedBody, service, is_finished)
    VALUES (3, 'AAAAAA-0003', NULL, 1,
            800366520000000000, 0, X'62706C697374303044', 'iMessage', 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (1, 3, 800366520000000000);

-- Tapback: "Loved" (type 2000) on msg 1
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me,
                     associated_message_type, associated_message_guid, service, is_finished)
    VALUES (4, 'AAAAAA-0004', 'Loved "Hey, are you free later?"', 1,
            800366580000000000, 1, 2000, 'p:0/AAAAAA-0001', 'iMessage', 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (1, 4, 800366580000000000);

-- ==== 1:1 iMessage with alice@example.com ====

INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me, service, is_finished)
    VALUES (5, 'BBBBBB-0001', 'Did you see the PR?', 3,
            800366640000000000, 0, 'iMessage', 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (2, 5, 800366640000000000);

INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me, service, is_finished, is_sent)
    VALUES (6, 'BBBBBB-0002', 'Yep, LGTM. Merging now.', 3,
            800366700000000000, 1, 'iMessage', 1, 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (2, 6, 800366700000000000);

-- Message with attachment (has text caption)
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me, service,
                     cache_has_attachments, is_finished)
    VALUES (7, 'BBBBBB-0003', 'Screenshot of the build output', 3,
            800366760000000000, 0, 'iMessage', 1, 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (2, 7, 800366760000000000);
INSERT INTO attachment (ROWID, guid, filename, mime_type, transfer_name, total_bytes)
    VALUES (1, 'ATT-0001',
            '~/Library/Messages/Attachments/ab/cd/ATT-0001/screenshot.png',
            'image/png', 'screenshot.png', 245000);
INSERT INTO message_attachment_join (message_id, attachment_id) VALUES (7, 1);

-- Attachment-only (text IS NULL, no attributedBody) — reader skips this
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me, service,
                     cache_has_attachments, is_finished)
    VALUES (8, 'BBBBBB-0004', NULL, 3,
            800366820000000000, 0, 'iMessage', 1, 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (2, 8, 800366820000000000);
INSERT INTO attachment (ROWID, guid, filename, mime_type, transfer_name, total_bytes)
    VALUES (2, 'ATT-0002',
            '~/Library/Messages/Attachments/ef/gh/ATT-0002/photo.heic',
            'image/heic', 'photo.heic', 3200000);
INSERT INTO message_attachment_join (message_id, attachment_id) VALUES (8, 2);

-- ==== Group chat: "Weekend Plans" ====

INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me,
                     cache_roomnames, service, is_finished)
    VALUES (9, 'CCCCCC-0001', 'Who is bringing drinks?', 1,
            800366880000000000, 0, 'chat100200300', 'iMessage', 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (3, 9, 800366880000000000);

INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me,
                     cache_roomnames, service, is_finished)
    VALUES (10, 'CCCCCC-0002', 'I can grab some on the way', 2,
            800366940000000000, 0, 'chat100200300', 'iMessage', 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (3, 10, 800366940000000000);

-- Sent by the user in the group (handle_id=0 for sent messages in groups)
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me,
                     cache_roomnames, service, is_finished, is_sent)
    VALUES (11, 'CCCCCC-0003', 'I will get the food covered', 0,
            800367000000000000, 1, 'chat100200300', 'iMessage', 1, 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (3, 11, 800367000000000000);

-- Tapback: "Liked" (2001) on msg 9 in group
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me,
                     associated_message_type, associated_message_guid,
                     cache_roomnames, service, is_finished)
    VALUES (12, 'CCCCCC-0004', 'Liked "Who is bringing drinks?"', 2,
            800367060000000000, 0, 2001, 'p:0/CCCCCC-0001', 'chat100200300', 'iMessage', 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (3, 12, 800367060000000000);

-- ==== SMS conversation ====

INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me, service, is_finished)
    VALUES (13, 'DDDDDD-0001', 'Your package has been delivered', 4,
            800367120000000000, 0, 'SMS', 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (4, 13, 800367120000000000);

INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me, service, is_finished, is_sent)
    VALUES (14, 'DDDDDD-0002', 'Thanks!', 4,
            800367180000000000, 1, 'SMS', 1, 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (4, 14, 800367180000000000);

-- ==== RCS conversation ====

INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me, service, is_finished)
    VALUES (15, 'EEEEEE-0001', 'Hey this is RCS now', 5,
            800367240000000000, 0, 'RCS', 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (5, 15, 800367240000000000);

-- ==== Edge cases ====

-- Empty string text (non-NULL) — reader should include this
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me, service, is_finished)
    VALUES (16, 'FFFFFF-0001', '', 1,
            800367300000000000, 0, 'iMessage', 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (1, 16, 800367300000000000);

-- Very old message (outside any reasonable hours window)
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me, service, is_finished)
    VALUES (17, 'FFFFFF-0002', 'Ancient message', 1,
            700000000000000000, 0, 'iMessage', 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (1, 17, 700000000000000000);

-- System message (handle_id=0, not from_me) — e.g. group rename
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me,
                     is_system_message, group_title, cache_roomnames, service, is_finished)
    VALUES (18, 'FFFFFF-0003', 'You named the conversation "Weekend Plans"', 0,
            800367360000000000, 0, 1, 'Weekend Plans', 'chat100200300', 'iMessage', 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (3, 18, 800367360000000000);

-- Emphasized tapback (2004)
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me,
                     associated_message_type, associated_message_guid, service, is_finished)
    VALUES (19, 'FFFFFF-0004', 'Emphasized "Yep, LGTM."', 3,
            800367420000000000, 0, 2004, 'p:0/BBBBBB-0002', 'iMessage', 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (2, 19, 800367420000000000);

-- Removed tapback (3001 = removed like) — text IS NULL
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me,
                     associated_message_type, associated_message_guid, service, is_finished)
    VALUES (20, 'FFFFFF-0005', NULL, 2,
            800367480000000000, 0, 3001, 'p:0/CCCCCC-0002', 'iMessage', 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (3, 20, 800367480000000000);

-- Thread reply (reply_to_guid + thread_originator_guid set)
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me,
                     reply_to_guid, thread_originator_guid, thread_originator_part,
                     service, is_finished)
    VALUES (21, 'FFFFFF-0006', 'Replying to the drinks question', 1,
            800367540000000000, 0,
            'CCCCCC-0001', 'CCCCCC-0001', '0',
            'iMessage', 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (3, 21, 800367540000000000);

-- Message with multiple attachments
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me, service,
                     cache_has_attachments, is_finished)
    VALUES (22, 'FFFFFF-0007', 'Check out this clip', 1,
            800367600000000000, 0, 'iMessage', 1, 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (1, 22, 800367600000000000);
INSERT INTO attachment (ROWID, guid, filename, mime_type, transfer_name, total_bytes)
    VALUES (3, 'ATT-0003',
            '~/Library/Messages/Attachments/ij/kl/ATT-0003/clip.mov',
            'video/quicktime', 'clip.mov', 15000000);
INSERT INTO attachment (ROWID, guid, filename, mime_type, transfer_name, total_bytes)
    VALUES (4, 'ATT-0004',
            '~/Library/Messages/Attachments/ij/kl/ATT-0003/clip.jpg',
            'image/jpeg', 'clip.jpg', 85000);
INSERT INTO message_attachment_join (message_id, attachment_id) VALUES (22, 3);
INSERT INTO message_attachment_join (message_id, attachment_id) VALUES (22, 4);

-- Emoji tapback (type 1000, with associated_message_emoji)
INSERT INTO message (ROWID, guid, text, handle_id, date, is_from_me,
                     associated_message_type, associated_message_guid,
                     associated_message_emoji, service, is_finished)
    VALUES (23, 'FFFFFF-0008', NULL, 1,
            800367660000000000, 0, 1000, 'p:0/AAAAAA-0002',
            '👍', 'iMessage', 1);
INSERT INTO chat_message_join (chat_id, message_id, message_date)
    VALUES (1, 23, 800367660000000000);

-- Tapback types reference:
--   1000 = Emoji sticker tapback (with associated_message_emoji)
--   2000 = Loved        3000 = Removed love
--   2001 = Liked        3001 = Removed like
--   2002 = Disliked     3002 = Removed dislike
--   2003 = Laughed      3003 = Removed laugh
--   2004 = Emphasized   3004 = Removed emphasis
--   2005 = Questioned   3005 = Removed question
--   2006 = (newer type observed in real data)
