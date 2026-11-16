# Phase 9 — Chat & Text Integrity

## Goal

Ensure player-authored text is filtered by Roblox TextService before it is stored or broadcast, prevent custom title attributes from exposing legacy/unfiltered profile text, and keep announcement authority server-side.

## Repository audit

The audited branch already had several important protections:
- Tiki Tide AFK messages, overhead bubble broadcasts, and local announcements use `TextService:FilterStringAsync` followed by `GetNonChatStringForBroadcastAsync`.
- Custom title save paths filter text before saving or replicating it.
- Legacy single-title migration re-filters text and does not fall back to the raw saved value on failure.
- Announcement and overhead broadcast actions require the SecurityCore `GlobalAnnouncement` permission and have server-side cooldowns.
- The overhead title renderer reads server-replicated Player attributes only. It creates no remote, saves no data, and does not grant permissions.
- Collection title tags are server-equipped profile cosmetics selected from a fixed allowlist. The renderer maps known IDs to fixed labels/colors rather than displaying arbitrary client text.

## Implemented changes

### 1. Re-filter persisted title slots before replication

File: `UI_Server_Controller_server (1).lua`

Previously, new-format saved title slots were structurally validated on profile load, but the active slot was not re-filtered before its text was copied into replicated Player attributes.

Now:
- The active persisted title is re-filtered through Roblox TextService before profile attributes are published.
- Other saved slots are filtered lazily when the player selects them, avoiding up to three TextService calls on every join.
- The same helper is used when selecting a saved slot and when clearing the active slot causes another saved slot to become active.
- A session-local per-user/per-slot cache records only text that passed broadcast filtering.
- `applyTitleAttributes` publishes only the cached filtered string. If filtering fails or the safe value is missing, it publishes an empty custom title and safe default styling.
- Saved profile text is not deleted if TextService is temporarily unavailable. The raw value remains server-side and hidden until a later filtering attempt succeeds.
- Cache entries are cleared on PlayerRemoving.

New and legacy title save paths remain filtered before storage. Existing title style/font/color allowlists, slot ownership, Tiki Tide entitlement, and profile schema are unchanged.

### 2. UTF-8-safe Tiki Tide broadcasts

File: `TikiTideSettings/TikiTideSettingsService.server.lua`

- Filtered broadcast output is now truncated by UTF-8 character boundaries rather than raw byte slicing.
- Invalid UTF-8 input is rejected.
- Text filtering failures continue to fail closed; no raw text fallback is broadcast.
- Existing GlobalAnnouncement permission checks, post-filter reauthorization, per-player bubble cooldown, global announcement cooldown, and remote ingress budgets are preserved.

### 3. Filter cross-server announcements at the publishing server

File: `ClubMusic_Global_Service_server_1.lua`

The global announcement BindableFunction now:
- Requires a positive finite integer actor UserId within the safe integer range.
- Requires that actor to be a live Player in the publishing server.
- Checks the actor's `GlobalAnnouncement` permission before filtering.
- Filters the message using Roblox TextService for broadcast.
- Re-checks that the actor is still present and still authorized after the yielding filter call.
- Publishes only the filtered result. If filtering fails, nothing is published.

Receiving servers continue to validate the MessagingService envelope and message schema. The receiving servers do not re-filter the same text independently.

## Preserved systems

- No profile schema or DataStore key changes.
- No new DataStore, MemoryStore, or MessagingService topics.
- No new polling loops or background workers.
- Existing profile write serialization, coalesced saves, session leases, and receipt journals are unchanged.
- Existing announcement permissions and cooldowns are unchanged.
- Existing ClubMusic audio, modern AudioPlayer, queue, and playback-only sync are untouched.
- No client remote was added for text filtering or role assignment.

## Explicit scope limits

- Roblox's built-in TextChatService filtering remains a platform responsibility; this phase does not replace Roblox chat.
- The audited repo's Tiki Tide announcement, bubble, AFK message, and ClubMusic custom-title paths are covered. Third-party scripts that create their own chat/broadcast remotes must be audited separately.
- Kohl's Admin native announcement handlers are external to this repository snapshot. The supplied adapter permission-gates announcement commands, but this phase does not claim to rewrite or verify the installed Kohl's handlers' text-filtering implementation.
- Server-owned title/collection attributes cannot grant staff permissions. Actual staff roles and command authority continue to come from SecurityCore/Kohl's server-side authorization, not displayed text.
- Client-only UI spoofing on an exploit user's own screen cannot be prevented by server code; it does not change other players' replicated server state.

## Verification checklist

### Source-level
- [x] Persisted active custom titles are re-filtered before replication.
- [x] Inactive title slots are filtered before selection/replication.
- [x] Filter failures never fall back to raw profile text.
- [x] Session title-filter cache is bounded by three slots per active player and cleaned on departure.
- [x] Tiki Tide filtered broadcasts are UTF-8-safe.
- [x] Cross-server announcement publisher verifies a live actor and permission before and after filtering.
- [x] Existing rate limits, cooldowns, profile persistence and entitlement checks are preserved.
- [x] No new remotes, persistent stores, polling loops or background workers.

### Required Roblox Studio tests
1. Join with an existing profile containing a normal saved title and confirm it displays after filtering.
2. Use a test profile with legacy/unfiltered title text; confirm only TextService output is replicated.
3. Make TextService filtering fail in a controlled test and confirm the title is hidden, not displayed raw, and profile data is not deleted.
4. Select an inactive saved title slot and confirm it is filtered before the title appears.
5. Clear the active slot and confirm the fallback slot is filtered before display.
6. Save normal titles with ASCII, emoji and multi-byte characters; confirm no broken UTF-8 output.
7. Submit invalid UTF-8 or oversized title payloads through a test harness; confirm rejection.
8. Send Tiki Tide AFK, overhead bubble, and local announcement text; confirm filtering and existing permission/cooldown behavior.
9. Attempt those actions without GlobalAnnouncement permission; confirm denial.
10. Test global announcement with authorized actor, unauthorized actor, departed actor, empty text, over-limit text and TextService failure; only authorized filtered text should publish.
11. Verify normal Roblox TextChatService filtering remains enabled and unaffected.
12. Verify title tags and staff role permissions remain server-authoritative.

## Verification status

- Repository source integration: completed.
- Roblox Studio tests: not performed.
- Published-server tests: not performed.
- External Kohl's Admin announcement handler filtering: not verified in this repository snapshot.

No live player profiles or persistent storage were read or modified by this phase.
