# Phase 12 — Replay & Behavioral Analytics

**Status:** Bounded server-local replay timeline, staff authorization, installer wiring, and selected event adapters are implemented in source. Roblox Studio and published-server verification remain outstanding.

## Scope delivered

- `ClubMusicSecurityCore/SecurityReplayService.lua` stores a bounded ring of at most 2,048 structured events per server.
- Events include a monotonic event ID, server timestamp/clock, JobId, actor UserId, optional target UserId, event type, severity, source, and sanitized scalar metadata.
- Metadata is restricted to a small number of short keys and scalar values. Non-finite numbers, Instances, arbitrary tables, long strings, and raw text payloads are not retained.
- The service exposes staff-authorized queries through the existing SecurityCore `GlobalModeration` permission.
- The installer places the service in ServerStorage and creates the server-only `TikiTideSecurityReplay` BindableFunction plus `GetTikiTideSecurityReplayStatus`.
- CharacterPhysicsGuard signals are recorded in the timeline when the replay endpoint is available.
- TeleportValidationService rejection/verification-failure signals are recorded through the Tiki Tide Settings adapter; successful teleport operations are not currently emitted as replay events.
- AvatarAccessoryValidationService detection signals are recorded through the main controller adapter; observations remain detection-only.
- MarketplaceService.ProcessReceipt records authoritative receipt lifecycle outcomes (received, retry pending, unknown product, activation/persistence failure, granted, duplicate). Replay metadata contains ProductId and a bounded outcome label only; PurchaseId is never copied into replay.
- Staff spectator entry, target switch, and exit lifecycle events are recorded in the same timeline; existing global audit behavior remains in place.
- No new RemoteEvent/RemoteFunction, DataStore, MemoryStore map, background worker, frame capture, or persistent per-event write is introduced.

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
- Current adapters cover CharacterPhysicsGuard, TeleportValidationService failure signals, AvatarAccessoryValidationService signals, authoritative ProcessReceipt lifecycle outcomes, and StaffSpectatorService lifecycle events. General remote validation failures, successful teleport events, audio/chat/social validation, and moderation decisions are not yet wired.
- The phase performs no threat-score changes, kicks, bans, automatic restrictions, or enforcement.
- No Roblox runtime test is claimed by this source change.

## Studio test plan

1. Install with simulation stopped and verify SecurityReplayService is present under ServerStorage/ClubMusicSecurityCore.
2. Verify the two BindableFunctions are under ServerStorage and no replay RemoteEvent/RemoteFunction is replicated.
3. Trigger controlled CharacterPhysicsGuard, teleport-validation, and avatar/accessory test signals and verify sanitized events are retained.
4. Exercise receipt callback retry, failure, success, and duplicate paths in a controlled test environment; verify ProductId/outcome only and confirm PurchaseId is absent.
5. Enter, switch, and exit StaffSpectatorService and verify lifecycle events appear.
6. Query as an authorized staff Player; verify an unauthorized player and a non-Player actor are denied.
7. Test target, event-type, timestamp, and limit filters, including invalid and extreme inputs.
8. Fill beyond 2,048 events and verify the ring remains bounded and newest events remain queryable.
9. Verify PlayerRemoving/server shutdown behavior and confirm no new persistence writes or background loops were introduced.
10. Regression-test CharacterPhysicsGuard, staff spectator, Kohl's Admin, Tiki Tide Settings, Utility Bar, ClubMusic playback/queue, and PC/mobile/console behavior.

**Exit criteria:** bounded memory, server-only record access, permission-checked staff queries, correct selected event adapters, and successful Studio/published-server tests. Source review alone is not runtime verification.
