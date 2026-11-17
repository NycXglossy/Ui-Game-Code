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
- The remote-ingress audit now covers the repository's server-side RemoteEvent/RemoteFunction handlers: ClubMusic action/query/purchase-diagnostic endpoints, Tiki Tide Settings, Utility Bar avatar refresh/actions, Tool Shop, and the Kohl's regular-command security adapter. Utility Bar malformed/unsupported actions and unsupported Tool Shop operations now submit fixed-name signals through `ReportSignal`; the Kohl's regular-command adapter already reports blocked dangerous commands, denied permissions, and invalid targets.
- ClubMusic Creator Hub audio validation now reports only deterministic invalid-ID and configured-allowlist rejections through `ReportSignal`; successfully queued Creator Hub audio is recorded as Info. Metadata lookup failures, private/unplayable assets, normal queue/cooldown denials, and ordinary track requests are not scored as security signals.
- Text validation now records informational outcomes after successful Roblox filtering for custom titles, Tiki Tide AFK text, overhead bubbles, and announcements. Only event type and actor are retained; filtered text is never copied into replay metadata.
- Social teleport validation is already wired through `TeleportValidationService` `onSignal`: verified destination events and ticket/identity/position failures enter replay; the adapter also forwards the fixed signal name to the existing global security monitor. It does not use the generic `ReportSignal` endpoint.
- `GetMusicCatalog`, `GetMusicPlaylists`, and `GetState` are bounded read-only queries, not security events. `PurchaseDiagnostic` remains explicitly untrusted client telemetry and is not treated as proof of purchase; `ProcessReceipt` remains the authoritative purchase source. `RefreshOwnAvatar` has no caller-supplied payload. No dedicated player chat remote was found in the audited source; Roblox `TextService` filtering is used for the identified title/AFK/announcement paths.
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
- Source audit and adapters cover CharacterPhysicsGuard, TeleportValidationService failure/success signals, AvatarAccessoryValidationService, authoritative ProcessReceipt outcomes, StaffSpectatorService lifecycle, global `ReportSignal` submissions and moderation changes, malformed/exceptional ClubMusic and Tiki Tide Settings requests, Utility Bar malformed/unsupported requests, Tool Shop unsupported operations, deterministic Creator Hub audio validation rejections, and successful filtered text/audio outcomes. Read-only queries and untrusted purchase-prompt telemetry are intentionally excluded. The audit is limited to the repository snapshot; external Kohl's Admin internals and other scripts/assets not present in this repository remain outside its proof.
- The phase performs no threat-score changes, kicks, bans, automatic restrictions, or enforcement.
- No Roblox runtime test is claimed by this source change.

## Studio test plan

1. Install with simulation stopped and verify SecurityReplayService is present under ServerStorage/ClubMusicSecurityCore.
2. Verify the two BindableFunctions are under ServerStorage and no replay RemoteEvent/RemoteFunction is replicated.
3. Trigger controlled CharacterPhysicsGuard, teleport-validation, and avatar/accessory test signals and verify sanitized events are retained.
4. Exercise receipt callback retry, failure, success, and duplicate paths in a controlled test environment; verify ProductId/outcome only and confirm PurchaseId is absent.
5. Complete an authorized teleport and verify `TeleportVerified` appears as Info; test mismatch/expiry paths and verify warning events.
6. Trigger malformed action envelopes and controlled handler exceptions at ClubMusic and Tiki Tide Settings; trigger malformed/unsupported Utility Bar requests and unsupported Tool Shop operations. Verify fixed event names only and no raw payloads.
7. Trigger deterministic invalid audio IDs/allowlist rejection, a filtered title, AFK message, bubble, and announcement; verify event type/actor only. Trigger a sanitized `ReportSignal`, Kohl's regular-command denial/invalid target, and a committed moderation update; verify each is retained.
8. Enter, switch, and exit StaffSpectatorService and verify lifecycle events appear.
9. Run `;cmreplay` and `;cmreplay UserId 20` as authorized staff; verify output is bounded and filtered. Verify ordinary players and non-Player actors cannot query.
10. Test target, event-type, timestamp, and limit filters, including invalid and extreme inputs.
11. Fill beyond 2,048 events and verify the ring remains bounded and newest events remain queryable.
12. Verify PlayerRemoving/server shutdown behavior and confirm no new persistence writes or background loops were introduced.
13. Regression-test CharacterPhysicsGuard, staff spectator, Kohl's Admin, Tiki Tide Settings, Utility Bar, ClubMusic playback/queue, and PC/mobile/console behavior.

**Exit criteria:** bounded memory, server-only record access, permission-checked staff queries, correct selected event adapters, and successful Studio/published-server tests. Source review alone is not runtime verification.
