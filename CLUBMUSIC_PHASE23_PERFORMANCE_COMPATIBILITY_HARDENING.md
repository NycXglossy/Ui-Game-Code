# Phase 23 — Performance & Compatibility Hardening

**Status:** Source-level bounds and compatibility contracts reviewed; profiling and device testing are acceptance tasks, not claims made by repository edits.

## Existing bounded mechanisms

- SecurityReplay: bounded per-server ring buffer and query limit; event recording remains available in every adaptive-load mode.
- SecurityThreatIntelligence: 256 subjects, 12 distinct signal codes per subject, 256 retained review items and TTL pruning.
- HoneypotManager: fixed decoys, cooldown, subject cap and leave cleanup.
- ClientIntegrityTelemetry: fixed allowlist, eight unique reports/player, one-second minimum interval, 200 tracked subjects and leave cleanup.
- StaffSpectatorService: maximum 64 active observers and lifecycle cleanup.
- IncidentResponse: 256-entry local indexes, 32-entry read cache, bounded incident size and TTL, ResourceGuard/StorageGuard gates.
- Diagnostics: server-local bounded histories and snapshots; no cross-server diagnostics aggregation or diagnostic writes.
- Adaptive Security Load Manager: optional replay and threat-review queries can be budget-gated; essential validation, authorization, rate limiting, receipt processing, moderation enforcement and event recording are never throttled.

## Compatibility requirements

- Preserve current PC, mobile and console interfaces.
- Do not change mobile layout while addressing desktop or server-side security.
- Keep UtilityBar independent from ClubMusic.
- Keep modern AudioPlayer as the controller-owned source, preserve crossfade, and keep each server's playback clock, Auto DJ selection, playlist cursor, skip votes, request accounting, and queue local. Cross-server playback synchronization is retired and must not be reintroduced.
- Keep client presentation, graphics quality, visual effects, input, and diagnostics local to each client. The adaptive visual-quality client combines local device quality with the current server's local adaptive-load mode; it does not send telemetry or create remotes.
- Use cross-server services only for explicitly global features with real consumers (for example moderation, announcements, catalog invalidation, or shared XP boost/receipt coordination). Do not use them for local playback, queues, or diagnostics.
- Preserve durable receipt idempotency, profile session leases, entitlement rules, DJ role separation and Kohl's adapter behavior.
- Do not assume client FPS/memory/ping values are trustworthy or transmit them to the server.
- Do not add permanent high-frequency polling loops to movement, diagnostics or security services.

## Required profiling matrix

- [ ] Baseline and peak Heartbeat delay with normal player count and high player count.
- [ ] Burst remote traffic from one player and many players.
- [ ] Replay/threat/honeypot signal bursts and bounded memory behavior.
- [ ] Diagnostics snapshot calls during active playback and queue churn.
- [ ] MemoryStore/DataStore throttling, temporary outage, and recovery.
- [ ] Adaptive Normal/Reduced/Critical transitions and hysteresis, including ReplayQueries and ThreatReviewQueries budgets.
- [ ] Staff spectator at maximum configured observer count.
- [ ] Character physics observer under respawn, custom rigs, launch pads, vehicles and latency.
- [ ] Profile on low-end mobile, desktop and console; verify UI responsiveness and input controls.
- [ ] Verify server shutdown and repeated installer execution do not leak connections or duplicate services.

## Safe-load policy

- Essential validation and authorization must never be skipped to save performance.
- Optional inspection work may be deferred or denied under a budget; do not silently drop security validation.
- When a dependency is unavailable, fail closed for the protected action and report an unavailable status without crashing unrelated gameplay.
- No automated punishment or physics correction is enabled by performance pressure.

**Exit criteria:** bounded resource use, no essential-path throttling, stable adaptive transitions, acceptable gameplay latency, and a clean device/server regression matrix.
