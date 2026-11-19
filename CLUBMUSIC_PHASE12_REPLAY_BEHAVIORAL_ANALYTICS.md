# Phase 12 — Replay & Behavioral Analytics

**Status:** Phase 12 functionality and applicable Phase 23 performance/compatibility hardening are implemented in repository source. The replay path has bounded event storage, bounded per-event metadata inspection, bounded query scanning/results, optional query budget gating, and no background capture loop. Roblox Studio profiling and device/server regression verification remain outstanding.

## Phase 12 objectives

Phase 12 provides staff with a privacy-limited, event-based security timeline for investigating selected server-side security and integrity signals. It is not a player surveillance recorder, a movement history recorder, or an automatic enforcement system.

The implementation retains the original boundaries:

- Record selected server-observed security events, not every gameplay action.
- Keep the timeline in bounded per-server memory.
- Require live staff authorization for every query.
- Retain only sanitized scalar metadata and fixed event labels.
- Do not retain raw chat, raw user-generated text, full Instance trees, credentials, receipt IDs, or secrets.
- Do not capture every-frame positions, camera data, or full-session video.
- Do not change threat scores, kick, ban, or automatically restrict players.

## 12.1 — Bounded Security Timeline

Implemented in `ClubMusicSecurityCore/SecurityReplayService.lua`.

- Circular buffer capped at 2,048 events per server.
- Monotonically increasing event IDs within the service instance.
- Event fields: server timestamp, monotonic clock, JobId, actor UserId, optional target UserId, event type, severity, source, and sanitized metadata.
- Metadata is restricted to at most 12 short keys and scalar values. Strings are bounded to 96 characters; numbers must be finite and are clamped to a bounded range.
- Event type, severity, source, and metadata keys are normalized before retention.
- The oldest event is overwritten when the ring is full. The dropped counter reports overwritten/rejected events.
- Event IDs and retained history are in-memory only and reset with the service/server lifecycle.

## 12.2 — Behavioral Signal Integration

The repository source audit and adapters cover selected, event-based signals from:

- CharacterPhysicsGuard movement-integrity detections.
- TeleportValidationService failure signals and successful destination verification.
- AvatarAccessoryValidationService detection signals.
- Authoritative MarketplaceService.ProcessReceipt lifecycle outcomes.
- StaffSpectatorService entry, target switch, and exit lifecycle events.
- Global ReportSignal submissions and successful global moderation state changes.
- Malformed action envelopes and handler exceptions for ClubMusic and Tiki Tide Settings.
- Malformed/unsupported Utility Bar requests and unsupported Tool Shop operations.
- Deterministic Creator Hub audio ID/allowlist validation outcomes.
- Successful filtered-text outcomes for custom titles, AFK messages, overhead bubbles, and announcements.

Normal gameplay denials, ordinary cooldown responses, metadata lookup failures, unplayable/private audio assets, ordinary track requests, read-only queries, and untrusted purchase-prompt telemetry are not treated as proof of abuse.

No dedicated player chat remote was found in the audited source. Roblox TextService filtering is used for the identified title, AFK, bubble, and announcement paths. Filtered text itself is never copied into replay metadata.

## 12.3 — Bounded Incident Context

Implemented as query-time context selection over the existing ring buffer; it does not create a second evidence store or capture new player data.

- Queries support an inclusive lower Unix timestamp and inclusive upper Unix timestamp.
- A time-bounded query returns only matching events already retained in the current server's ring buffer.
- Optional target UserId and exact event-type filters can be combined with the time window.
- Query results are newest-first and bounded to 100 events by the server API (the staff command caps output to 30).
- The time window cannot recover events overwritten by the ring buffer or events from another server.
- There is no durable incident snapshot, export file, cross-server history, or additional capture loop.

## 12.4 — Staff Investigation

The server-only `ServerStorage.TikiTideSecurityReplay` BindableFunction exposes Record, Query, and Status operations. The installer creates the service under ServerStorage and exposes the status BindableFunction. No replay RemoteEvent or RemoteFunction is added.

Every Query requires a live Player and a successful SecurityCore `GlobalModeration` authorization check. The main controller independently authorizes the staff command before invoking the endpoint.

Kohl's Admin command:

```text
;cmreplay
;cmreplay 123456 20
;cmreplay 0 30 1760000000 1760003600 teleport_verified
```

Syntax:

```text
;cmreplay [UserId] [Limit] [AfterUnix] [BeforeUnix] [EventType]
```

- UserId is optional; use `0` as a placeholder when supplying later positional filters without a target.
- Limit is optional and must be an integer from 1 to 30.
- AfterUnix and BeforeUnix are optional inclusive Unix timestamps; use `0` as a placeholder when omitting a bound.
- EventType is an optional exact event-type filter containing letters, numbers, underscores, or hyphens (maximum 48 characters).
- The original `;cmreplay UserId Limit` form remains supported.
- The displayed summary includes timestamp, severity, event type, actor, optional target, source, and bounded sanitized scalar metadata.
- Output remains bounded to 1,900 characters. Metadata is sorted by key for stable presentation and truncated per value.
- The command is registered in Kohl's Admin's Administration group; the server bridge independently requires a live staff player and SecurityCore permission.

The API query signature is:

```lua
local ok, events, reason = replay:Invoke("Query", staffPlayer,
    targetUserId, limit, beforeTimestamp, eventType, afterTimestamp)
```

The lower and upper timestamps are inclusive. Pass nil for an omitted API filter. Invalid target IDs, limits, timestamps, reversed time windows, and event-type filters are rejected instead of silently broadening the query.

## 12.5 — Data Integrity and Privacy

Implemented source hardening:

- Event types are trimmed, bounded, and restricted to a safe identifier character set before storage.
- Severity is normalized to the supported labels Info, Warning, Error, and Critical; unknown values become Info.
- Metadata keys are bounded and restricted to safe identifier characters. Values remain scalar-only.
- Query filters are explicitly validated. Invalid filters return an error instead of being ignored.
- Query limits must be integer values in the supported range; malformed limits are rejected rather than silently replaced with a default.
- Returned events and their metadata tables are cloned independently. A caller modifying a returned result cannot mutate the retained ring-buffer event.
- Query authorization is checked on every request and again requires the caller to remain a live Player.
- The replay endpoint remains in ServerStorage and is not exposed to clients.

The service does not store raw chat, raw filtered text, passwords, credentials, receipt PurchaseIds, arbitrary client payloads, Instance references, or nested metadata tables.

## 12.6 — Phase 23 Performance and Compatibility Application

The Phase 23 performance/compatibility requirements applicable to this event timeline are implemented:

- **Bounded recording cost:** one Record call performs bounded field normalization and inspects at most 24 metadata entries, retaining at most 12 scalar metadata fields. Raw chat, arbitrary nested tables, Instances, and unbounded payloads are not retained.
- **Bounded memory:** the per-server ring buffer remains capped at 2,048 events. No persistent storage, cross-server replication, or secondary evidence cache is created.
- **Bounded query work:** each query scans at most the 2,048 retained ring entries and returns at most 100 events. The staff command caps the result at 30 and the rendered response at 1,900 characters. Result allocation is sized to the requested bounded result count.
- **Optional workload budget:** the installer routes Query through the existing AdaptiveSecurityLoadManager `ReplayQueries` token bucket. Under load, an investigation query can be deferred with an explicit message. The service's Record operation is not routed through that budget and remains available in Normal, Reduced, and Critical modes.
- **No polling/capture loop:** the replay service creates no Heartbeat connection, task loop, periodic scan, movement sampler, or frame capture. It records only when an existing server-side event adapter invokes Record.
- **No extra network or persistence cost:** no client remotes, telemetry uploads, DataStore/MemoryStore writes, MessagingService calls, or cross-server diagnostics aggregation are added by Phase 12.
- **Compatibility preserved:** this is server-side SecurityCore work only. It does not alter PC, mobile, or console UI/input, UtilityBar behavior, AudioPlayer ownership, crossfade, or independent per-server playback queues.
- **Security priority preserved:** authorization, validation, rate limiting, receipt processing, moderation enforcement, and security-event recording are not throttled by the adaptive workload manager. Only optional staff replay queries may be deferred.

The implementation is bounded by source-level contracts; actual CPU, memory, and latency improvements must be measured in Studio and on representative devices/servers. No performance gain is claimed without profiling.

## 12.7 — Verification and Exit Criteria

The following Studio verification remains outstanding; repository source changes do not imply runtime verification.

1. With simulation stopped, install the staged SecurityCore release and verify SecurityReplayService is present under ServerStorage/ClubMusicSecurityCore and the installer pin matches the documented hardened commit.
2. Verify the two replay BindableFunctions are under ServerStorage and no replay RemoteEvent/RemoteFunction is replicated.
3. Trigger controlled CharacterPhysicsGuard, teleport-validation, and avatar/accessory signals and verify sanitized events are retained.
4. Exercise receipt callback retry, failure, success, and duplicate paths in a controlled environment; verify ProductId/outcome only and confirm PurchaseId is absent.
5. Complete an authorized teleport and verify TeleportVerified appears as Info; test mismatch/expiry paths and verify warning events.
6. Trigger malformed action envelopes and controlled handler exceptions at ClubMusic and Tiki Tide Settings; trigger malformed/unsupported Utility Bar requests and unsupported Tool Shop operations. Verify fixed event names only and no raw payloads.
7. Trigger deterministic invalid audio IDs/allowlist rejection, a filtered title, AFK message, bubble, and announcement; verify event type/actor only. Trigger a sanitized ReportSignal, Kohl's regular-command denial/invalid target, and a committed moderation update; verify each is retained.
8. Enter, switch, and exit StaffSpectatorService and verify lifecycle events appear.
9. Run `;cmreplay`, `;cmreplay UserId 20`, and a timestamp/event-type filtered query as authorized staff. Verify output is bounded and includes only sanitized fields.
10. Verify ordinary players and non-Player actors cannot query. Test invalid target IDs, fractional/out-of-range limits, invalid timestamps, reversed time windows, malformed event types, and valid inclusive bounds.
11. Modify a returned event and its metadata in a controlled test harness; verify retained history is unchanged.
12. Fill beyond 2,048 events and verify the ring remains bounded and newest events remain queryable.
13. Burst Record with normal and oversized metadata tables; verify each event inspects no more than 24 input entries, stores no more than 12 scalar fields, and recording remains available in Normal/Reduced/Critical load modes.
14. Burst authorized Query calls in Normal/Reduced/Critical modes; verify the ReplayQueries budget can defer optional review work with an explicit result, while Record, validation, authorization, receipt processing, and moderation remain unaffected.
15. Verify query scanning never exceeds the 2,048 retained-event capacity, returned events never exceed the requested limit (maximum 100), command output never exceeds 1,900 characters, and no unbounded allocation or background polling is introduced.
16. Verify PlayerRemoving/server shutdown behavior and confirm no new persistence writes, client remotes, telemetry uploads, background loops, or capture tasks were introduced.
17. Regression-test CharacterPhysicsGuard, staff spectator, Kohl's Admin, Tiki Tide Settings, Utility Bar, ClubMusic playback/queue, and PC/mobile/console behavior. Profile low-end mobile, desktop, and console separately; confirm Phase 12 introduces no UI/input changes.

**Exit criteria:** bounded memory, server-only record access, permission-checked and validated staff queries, detached query results, correct selected event adapters, privacy safeguards, and successful Studio/published-server tests. Source review alone is not runtime verification.
