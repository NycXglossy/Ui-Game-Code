# Phase 13 — Adaptive Security Load Manager

**Status:** Server-local adaptive workload budgeting, installer staging, and bounded replay-query integration are implemented in source. Roblox Studio, published-server, and load-profile verification remain outstanding.

## Purpose

Phase 13 adds a small server-only workload manager that reduces optional security/observability work when the server heartbeat is persistently delayed. It is a workload governor, not an anti-cheat bypass, moderation engine, memory cleaner, or replacement for the existing watchdog and ResourceGuard.

## Scope delivered

- `ClubMusicSecurityCore/AdaptiveSecurityLoadManager.lua` samples server Heartbeat delta in fixed five-second windows.
- The manager tracks only bounded counters, four optional task buckets, the current mode, transition history, and the latest sample. It creates no storage records, remotes, polling task, or client state.
- Three modes are available:
  - **Normal:** normal optional diagnostics, replay-query, analytics, and maintenance budgets.
  - **Reduced:** lower optional workload budgets after three consecutive overloaded windows.
  - **Critical:** optional work is paused after two consecutive severe windows, or six consecutive overloaded windows while Reduced.
- Recovery is staged: four consecutive healthy windows move Critical to Reduced; the healthy streak resets at that transition, then six additional consecutive healthy windows are required to move Reduced to Normal.
- Thresholds are intentionally conservative and hysteretic:
  - overloaded: average Heartbeat delta at least 0.10 seconds or maximum delta at least 0.45 seconds in the window;
  - critical: average at least 0.20 seconds or maximum at least 0.75 seconds;
  - healthy: average at most 0.07 seconds and maximum at most 0.25 seconds.
- Optional task classes have bounded token-bucket budgets: `DiagnosticsSampling`, `ReplayQueries`, `AnalyticsAggregation`, and `BackgroundMaintenance`.
- Essential task classes always pass and are never throttled: `EssentialSecurityValidation`, `RemoteAuthorization`, `RateLimiting`, `PurchaseReceiptProcessing`, `ModerationEnforcement`, and `SecurityEventRecording`.
- The installer stages the module with the existing SecurityCore release and exposes a server-only `ServerStorage.TikiTideSecurityLoadManager` BindableFunction supporting `Status`, `GetBudget`, and `TryConsume`. A read-only `GetTikiTideSecurityLoadStatus` BindableFunction is also installed.
- Replay event recording remains available in all modes. Staff replay queries consume the optional `ReplayQueries` budget and can be temporarily refused during Critical load or when the query token bucket is empty.
- Mode transitions are recorded in the existing bounded replay timeline with mode, heartbeat sample values, and a fixed reason string. No player text or client-provided values are included.
- The installer release pin is updated to the commit containing the new module. Existing modules, camera adapter, and rollback strategy remain in place.

## Server-only API

Trusted server scripts may use the internal BindableFunction:

```lua
local ServerStorage = game:GetService("ServerStorage")
local loadManager = ServerStorage:WaitForChild("TikiTideSecurityLoadManager")

local status = loadManager:Invoke("Status")
local budget = loadManager:Invoke("GetBudget", "AnalyticsAggregation")
local allowed = loadManager:Invoke("TryConsume", "AnalyticsAggregation", 1)
```

Do not create a client RemoteFunction for this API. Do not call `TryConsume` around essential validation, authorization, rate limiting, receipts, moderation, or replay event recording.

## Explicit limitations

- The current automatic signal is server Heartbeat delay only. It does **not** claim to measure total server memory, network saturation, DataStore queue depth, or CPU utilization directly.
- Existing ResourceGuard and StorageGuard continue to own storage concurrency and circuit-breaker behavior; this phase does not override their limits.
- Only replay-query work is wired to a budget in this phase. Other optional subsystems can adopt the server-only `TryConsume` contract after their actual call sites are reviewed.
- No validation, authorization, receipt, moderation, or security-event recording path is disabled or weakened.
- The manager does not automatically kick, ban, teleport, restrict, or otherwise enforce against players.
- No Roblox runtime or performance test is claimed by this source change.

## Studio test plan

1. Run the installer with simulation stopped and HTTP Requests enabled. Verify the manifest includes `AdaptiveSecurityLoadManager`.
2. Verify `TikiTideSecurityLoadManager` and `GetTikiTideSecurityLoadStatus` exist only under ServerStorage; confirm no new replicated RemoteEvent/RemoteFunction exists.
3. Query status and confirm the initial mode is Normal, budgets are bounded, and storage writes/client remotes are zero.
4. In an isolated test harness, feed synthetic Heartbeat deltas to a manager instance or use a controlled server-load test; verify the three-window Reduced and two-window Critical transitions.
5. Verify recovery requires the documented healthy streaks and cannot jump directly from Critical to Normal.
6. Verify token buckets refill at their configured rates and cannot exceed burst capacity.
7. Verify all essential task classes always return true in Normal, Reduced, and Critical modes.
8. Verify replay event recording still works in Critical mode, while staff replay queries are rate-limited/paused as configured.
9. Verify mode transitions appear in ` ;cmreplay ` without player text or arbitrary payloads.
10. Run multi-client playback, queue, Tiki Tide Settings, Utility Bar, Tool Shop, receipt, moderation, and spectator regression tests while the server is under controlled load.
11. Profile frame time and memory before/after installation; confirm the manager's Heartbeat callback and bounded tables do not create measurable gameplay regressions.
12. Verify server shutdown/installer rollback disconnects the Heartbeat connection and does not leave duplicate managers or BindableFunctions.

## Exit criteria

The module must remain server-only and bounded; essential security paths must remain unrestricted in every mode; optional budgets and staged recovery must behave as specified; staff replay review must fail safely under pressure; and Studio/published-server performance tests must pass. Source review alone is not runtime verification.
