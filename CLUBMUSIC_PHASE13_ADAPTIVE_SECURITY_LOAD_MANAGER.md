# Phase 13 — Adaptive Security Load Manager

**Source status:** Base server-local adaptive workload governor implemented. Phase 13.1 integration is recorded separately in `CLUBMUSIC_PHASE13_1_ADAPTIVE_LOAD_INTEGRATION.md`.
**Runtime status:** Roblox Studio, published test-server, and controlled-load verification remain open.

## Purpose

Phase 13 adds a server-only workload governor that reduces optional security/observability work when server Heartbeat is persistently delayed. It is not an anti-cheat bypass, moderation engine, memory cleaner, or replacement for the existing watchdog and ResourceGuard.

## Base implementation

- `ClubMusicSecurityCore/AdaptiveSecurityLoadManager.lua` samples server Heartbeat delta in fixed five-second windows.
- Modes are `Normal`, `Reduced`, and `Critical`.
- Three consecutive overloaded windows move Normal to Reduced; two consecutive severe windows move to Critical; six overloaded windows while Reduced also move to Critical.
- Recovery is staged: four consecutive healthy windows move Critical to Reduced; six additional healthy windows move Reduced to Normal.
- Thresholds use server Heartbeat timing, not a single instantaneous FPS reading:
  - overloaded: average delta at least 0.10 seconds or maximum delta at least 0.45 seconds;
  - critical: average delta at least 0.20 seconds or maximum delta at least 0.75 seconds;
  - healthy: average delta at most 0.07 seconds and maximum delta at most 0.25 seconds.
- The governor uses bounded token buckets for five optional task classes:
  - `DiagnosticsSampling`
  - `ReplayQueries`
  - `ThreatReviewQueries`
  - `AnalyticsAggregation`
  - `BackgroundMaintenance`
- Essential task classes always pass and are never throttled: `EssentialSecurityValidation`, `RemoteAuthorization`, `RateLimiting`, `PurchaseReceiptProcessing`, `ModerationEnforcement`, and `SecurityEventRecording`.
- The installer exposes `ServerStorage.TikiTideSecurityLoadManager` with `Status`, `GetBudget`, and `TryConsume`, plus the read-only `GetTikiTideSecurityLoadStatus` BindableFunction. These are server-only.
- Replay event recording remains available in all modes. Staff replay queries consume `ReplayQueries`; threat-review queries consume `ThreatReviewQueries`.
- Mode transitions are recorded in the existing bounded server-local replay timeline. No player text or client-supplied data is included.

## Phase 13.1 integration status

See `CLUBMUSIC_PHASE13_1_ADAPTIVE_LOAD_INTEGRATION.md` for the detailed changes. The follow-up adds bounded per-task attempted/accepted/deferred counters, cumulative time per mode, recovery streak visibility, adaptive passive movement sampling, optional analytics aggregation deferral, tagged client visual scaling, and Staff Controls visibility.

## Explicit boundaries

- The automatic load signal is server Heartbeat delay only. It does not claim to directly measure total server memory, network saturation, DataStore queue depth, or CPU utilization.
- ResourceGuard and StorageGuard retain ownership of storage concurrency and circuit-breaker behavior.
- Essential validation, authorization, rate limiting, receipts, moderation, security-event recording, and replay event recording are never gated by optional budgets.
- No remote cooldown is changed dynamically. Existing per-action rate limits remain authoritative.
- No automatic kick, ban, teleport, rubber-band, restriction, restart, or other player enforcement is performed by this governor.
- No DataStore, MemoryStore, MessagingService, diagnostics remote, or client-to-server diagnostics telemetry is added.
- `BackgroundMaintenance` remains a reserved budget because source review did not identify a safe, genuinely optional background-maintenance callsite. Profile persistence, storage cleanup, purchase processing, and security retention are not safe to defer merely to consume a budget.
- No Roblox runtime or performance test is claimed by source changes.

## Studio test plan

1. Run the installer with simulation stopped and HTTP Requests enabled. Verify the manifest and pinned release include `AdaptiveSecurityLoadManager` and the adaptive visual client.
2. Verify `TikiTideSecurityLoadManager` and `GetTikiTideSecurityLoadStatus` exist only under ServerStorage; confirm no new RemoteEvent/RemoteFunction is created.
3. Verify initial mode, five bounded buckets, task counters, mode durations, and zero storage writes/client remotes.
4. In an isolated test harness, feed synthetic Heartbeat deltas and verify Normal/Reduced/Critical transitions and staged recovery.
5. Verify token refill, burst limits, attempted/accepted/deferred counters, and every essential task class in every mode.
6. Verify ReplayQueries and ThreatReviewQueries are deferred under Critical load while replay event recording remains available.
7. Verify AnalyticsAggregation can be deferred without suppressing the health coordinator, ServerHealth Heartbeat sampling, watchdog, or essential security status.
8. Verify DiagnosticsSampling reduces only passive aggregate movement sampling; movement property checks, velocity signals, MovementAuthority, and TeleportValidationService remain active.
9. Verify VIP speed changes, size changes, mounts, authorized teleports, respawns, and scripted movement are not corrected or misclassified by a new fixed speed threshold.
10. Verify visual mode affects only `ClubEffect` particle rates and `StageClubLight` shadows; existing light Enabled/Color/Brightness and player-selected lighting presets remain intact.
11. Verify newly tagged/untagged effects follow the current mode and original properties restore correctly.
12. Run multi-client playback, queue, Tiki Tide Settings, Utility Bar, Tool Shop, receipt, moderation, and spectator regression tests under controlled load.
13. Profile server frame time, client frame time, memory, and visual rendering before/after integration.
14. Verify installer rollback, bootstrap shutdown, and absence of duplicate services, scripts, or endpoints.

## Exit criteria

The manager remains server-local and bounded; essential security paths remain unrestricted; optional budgets and staged recovery behave as specified; visual changes restore cleanly; and Studio/published-server performance and regression tests pass. Source review alone is not runtime verification.
