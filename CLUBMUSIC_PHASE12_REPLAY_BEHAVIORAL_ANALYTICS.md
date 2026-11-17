# Phase 12 — Replay & Behavioral Analytics

**Status:** Bounded server-local replay timeline, staff authorization, installer wiring, and selected event adapters are implemented in source. Roblox Studio and published-server verification remain outstanding.

## Scope delivered

- `ClubMusicSecurityCore/SecurityReplayService.lua` stores a bounded ring of at most 2,048 structured events per server.
- Events include a monotonic event ID, server timestamp/clock, JobId, actor UserId, optional target UserId, event type, severity, source, and sanitized scalar metadata.
- Metadata is restricted to a small number of short keys and scalar values. Non-finite numbers, Instances, arbitrary tables, long strings, and raw text payloads are not retained.
- The service exposes staff-authorized queries through the existing SecurityCore `GlobalModeration` permission.
- The installer places the service in ServerStorage and creates the server-only `TikiTideSecurityReplay` BindableFunction plus `GetTikiTideSecurityReplayStatus`.
- CharacterPhysicsGuard signals are recorded in the timeline when the replay endpoint is available.
- TeleportValidationService failure signals and successful destination verification (`TeleportVerified`) are recorded through the Tiki Tide Settings adapter. Successful events are informational; validation failures remain warnings.
- AvatarAccessoryValidationService detection signals are recorded through the main controller adapter; observations remain detection-only.
- The global `ReportSignal` path records sanitized server-submitted security signals, and successful global moderation state changes (ban/request-block) are mirrored into the local timeline.
- The ClubMusic `RequestAction` and Tiki Tide Settings `OnServerInvoke` adapters record malformed action envelopes and handler exceptions only; ordinary gameplay rejections and cooldown responses are not treated as exploit evidence.
- MarketplaceService.ProcessReceipt records authoritative receipt lifecycle outcomes (received, retry pending, unknown product, activation/persistence failure, granted, duplicate). Replay metadata contains ProductId and a bounded outcome label only; PurchaseId is never copied into replay.
- Staff spectator entry, target switch, and exit lifecycle events are recorded in the same timeline; existing global audit behavior remains in place.
- No new RemoteEvent/RemoteFunction, DataStore, MemoryStore map, background worker, frame capture, or persistent per-event write is introduced.

## Staff review command

Authorized staff can use the Kohl's Admin command `;cmreplay` to review the newest retained events on the current server. `;cmreplay 123456 20` filters to a UserId and returns up to 20 events (limit 1–30). The command is registered in Kohl's Admin's Administration group, then the server bridge independently requires a live staff player and SecurityCore `GlobalModeration` permission. It queries the ServerStorage BindableFunction directly; no replay RemoteEvent or RemoteFunction is added. Results are bounded and newest-first. This is a current-server review, not a cross-server lookup.

## Server-only API

The endpoint lives under ServerStorage and is intended for trusted server scripts:

```lua
local replay = game:GetService("ServerStorage"):WaitForChild("TikiTideSecurityReplay")

-- Record from a trusted server-side detector/validator:
replay:Invoke("Record", "movement_limit_exceeded", player.UserId, 0,
    "Warning", "CharacterPhysicsGuard", {property = "WalkSpeed"})

-- Staff query; actor must be a live Player with GlobalModeration:
local ok, events, reason = replay:Invoke("Query", staffPlayer,
    targetUserId, 50, nil, nil)

-- Operational counters:
local status = replay:Invoke("Status")
```

Query parameters are actor Player, optional target UserId, limit (1–100), optional inclusive upper timestamp, and optional exact event type. Results are newest-first and include events where the target is either the actor or the target user.

## Guardrails and limitations

- The timeline is per-server memory only. It is not durable across server shutdowns and is not a cross-server account history.
- The ring is globally capped at 2,048 events; oldest events are overwritten when full. The dropped counter reports overwritten/rejected events.
- No every-frame position, camera, chat, or full-session video capture is performed.
- No raw user-generated message text, credentials, receipt IDs, secrets, or full Instance trees are stored.
- Staff queries are permission checked on every request. The endpoint itself is server-only; do not expose it directly to clients.
- Current adapters cover CharacterPhysicsGuard, TeleportValidationService failure and successful-verification signals, AvatarAccessoryValidationService signals, authoritative ProcessReceipt lifecycle outcomes, StaffSpectatorService lifecycle events, sanitized events submitted through `ReportSignal`, committed global ban/request-block changes, and malformed/exceptional requests at the ClubMusic and Tiki Tide Settings remote boundaries. This does not prove every audio/chat/social validator submits a signal; each source still needs a place-by-place audit.
- The phase performs no threat-score changes, kicks, bans, automatic restrictions, or enforcement.
- No Roblox runtime test is claimed by this source change.

## Studio test plan

1. Install with simulation stopped and verify SecurityReplayService is present under ServerStorage/ClubMusicSecurityCore.
2. Verify the two BindableFunctions are under ServerStorage and no replay RemoteEvent/RemoteFunction is replicated.
3. Trigger controlled CharacterPhysicsGuard, teleport-validation, and avatar/accessory test signals and verify sanitized events are retained.
4. Exercise receipt callback retry, failure, success, and duplicate paths in a controlled test environment; verify ProductId/outcome only and confirm PurchaseId is absent.
5. Complete an authorized teleport and verify `TeleportVerified` appears as Info; test mismatch/expiry paths and verify warning events.
6. Trigger malformed action envelopes and controlled handler exceptions at both remote boundaries; verify replay entries contain only action type/name metadata.
7. Trigger a sanitized `ReportSignal` and a committed moderation update; verify each is retained.
8. Enter, switch, and exit StaffSpectatorService and verify lifecycle events appear.
9. Run `;cmreplay` and `;cmreplay UserId 20` as authorized staff; verify output is bounded and filtered. Verify ordinary players and non-Player actors cannot query.
10. Test target, event-type, timestamp, and limit filters, including invalid and extreme inputs.
11. Fill beyond 2,048 events and verify the ring remains bounded and newest events remain queryable.
12. Verify PlayerRemoving/server shutdown behavior and confirm no new persistence writes or background loops were introduced.
13. Regression-test CharacterPhysicsGuard, staff spectator, Kohl's Admin, Tiki Tide Settings, Utility Bar, ClubMusic playback/queue, and PC/mobile/console behavior.

**Exit criteria:** bounded memory, server-only record access, permission-checked staff queries, correct selected event adapters, and successful Studio/published-server tests. Source review alone is not runtime verification.
