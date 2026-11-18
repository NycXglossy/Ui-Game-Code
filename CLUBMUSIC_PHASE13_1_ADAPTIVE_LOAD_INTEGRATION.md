# Phase 13.1 — Adaptive Workload, Movement Sampling & Visual Quality Integration

**Source status:** Implemented on `phase13.1-adaptive-load-integration`, based on `phase14.1-local-staff-diagnostics`.
**Runtime status:** Not yet accepted. No Roblox Studio, published test-server, or controlled-load tests were run as part of this source change.
**Deployment:** Source-only. Not merged, installed, or deployed to a live Roblox place.

## Objectives

Extend the existing Phase 13 manager rather than create a second governor. Connect safe optional workloads, expose bounded accounting in the existing Tiki Tide Staff Controls diagnostics overview, make passive movement sampling adaptive, and reduce only explicitly tagged client-side club visuals during sustained server load.

## Implemented source changes

### 1. Adaptive manager accounting

Updated `ClubMusicSecurityCore/AdaptiveSecurityLoadManager.lua`:

- Preserved the existing five-second Heartbeat sampling window, Normal/Reduced/Critical states, overload thresholds, and staged recovery hysteresis.
- Preserved the five existing optional token buckets: `DiagnosticsSampling`, `ReplayQueries`, `ThreatReviewQueries`, `AnalyticsAggregation`, and `BackgroundMaintenance`.
- Added bounded per-task counters for attempted, accepted, and deferred requests.
- Added cumulative time spent in Normal, Reduced, and Critical modes, plus current-mode duration.
- Added an explicit recovery healthy-window streak field for staff visibility.
- Kept essential task bypasses unchanged. Security-event recording remains unrestricted.
- All status is in-memory and scoped to the current server process.

### 2. Existing query budget integrations

- Existing `ReplayQueries` and `ThreatReviewQueries` integrations remain in place.
- `AnalyticsAggregation` now gates optional aggregation in `ClubMusic_Global_Diagnostics_Service:GetMetrics()`. If the optional budget is exhausted, metrics return a bounded Deferred result; the health coordinator and ServerHealth sampling continue.
- `BackgroundMaintenance` remains reserved. Source review found no safe optional background-maintenance worker to defer. Profile persistence, storage cleanup, receipt handling, and security retention must not be throttled just to consume a token bucket.
- No new background worker or polling loop was added.

### 3. Adaptive passive movement measurement

Updated `ClubMusicSecurityCore/CharacterPhysicsGuard.lua` and the embedded bootstrap source in `ClubMusic_Security_Core_Installer.lua`:

- Existing CharacterPhysicsGuard remains detection-only.
- Existing MovementAuthority and TeleportValidationService continue to own authorized movement and teleport exemptions.
- Passive aggregate displacement measurement changes sampling interval by mode: Normal 0.5s, Reduced 1.0s, Critical 1.25s.
- Each sample consumes a fractional `DiagnosticsSampling` budget normalized by the current server player count, keeping the budget server-wide rather than granting every player an independent bucket.
- If a sample is deferred, the local position/time baseline is refreshed so the next accepted sample does not count the skipped interval as movement.
- Deferred sample counts are exposed in the existing CharacterPhysicsGuard status.
- Existing WalkSpeed/JumpPower/JumpHeight authorization checks, scale checks, and high-velocity/high-angular-velocity observation are not throttled.
- No hard-coded MAX_WALK_SPEED detector, CFrame correction, rubber-banding, kick, ban, or automatic enforcement was added.
- Legitimate VIP speed, size controls, mounts, authorized teleports, and scripted movement continue to be governed by existing server-authorized movement pathways.

### 4. Client visual quality

Added `TikiTideAdaptiveVisualQuality.client.lua`, installed by the existing SecurityCore installer into StarterPlayerScripts:

- Reads the server-local `Workspace.TikiTideAdaptiveLoadMode` attribute. The attribute is set by the existing adaptive manager in the current server instance; it is not a cross-server diagnostics channel.
- No RemoteEvent or RemoteFunction is created.
- Only explicitly tagged `ClubEffect` ParticleEmitters are scaled:
  - Normal: 100% of their original Rate.
  - Reduced: 50%.
  - Critical: 10%.
- Only lights under explicitly tagged `StageClubLight` roots have local shadow rendering disabled outside Normal mode.
- Light Enabled, Color, and Brightness are not modified. Existing Stage & Club Lighting presets and server-owned light color/brightness remain intact.
- Original particle rates and shadow settings are cached client-locally. The script tracks updates from other authorized writers and restores values when the mode returns to Normal, an object is untagged, or the script is destroyed.
- Tag additions/removals and new descendants are handled without a separate HUD or client telemetry.

### 5. Installer and release pin

Updated `ClubMusic_Security_Core_Installer.lua`:

- Pins the SecurityCore module release to commit `21a9b11e256a69d949f5fead07e0b3c51e0e1d89`, which contains the updated AdaptiveSecurityLoadManager, CharacterPhysicsGuard, and visual-quality LocalScript.
- Stages the visual LocalScript with the existing camera/integrity clients.
- Preserves an existing visual client backup and restores it on failed promotion.
- Adds the visual client name to the install manifest.
- Sets/clears the Workspace adaptive-mode attribute as the server-local manager starts/stops.
- The installer still requires Studio simulation to be stopped and HTTP Requests enabled. It has not been run as part of this source change.

### 6. Existing Staff Controls visibility

Updated `UI_Server_Controller_server (1).lua`:

- The existing authorized OperationalDiagnostics projection now includes current adaptive mode duration, recovery healthy-window streak, transition count/reason, and accepted/deferred counts for all five workload categories.
- It includes CharacterPhysicsGuard passive movement sample interval, accepted samples, and deferred samples.
- The existing Staff Controls Diagnostics overview renders the existing server command result. No separate HUD, new client command, or diagnostics remote was added.
- Client FPS/ping/memory readings remain local and untrusted; they are not sent to the server.

## Workload safety matrix

| Workload | Adaptive behavior | Essential path protected |
|---|---|---|
| ReplayQueries | Existing optional query budget | Replay event recording |
| ThreatReviewQueries | Existing optional review budget | Threat/security event recording |
| AnalyticsAggregation | Optional metrics aggregation can defer | Health checks, watchdog, ServerHealth |
| DiagnosticsSampling | Passive aggregate movement samples can defer | Movement authorization and event-driven checks |
| BackgroundMaintenance | Reserved; no safe optional callsite identified | Persistence, cleanup, security retention |

## Non-negotiable boundaries

- Diagnostics and adaptive counters remain server-local, in-memory, and bounded.
- The visual mode attribute is replicated only to clients in the same server instance so their local rendering can adapt. It is not stored or aggregated across servers.
- No diagnostics DataStore, MemoryStore, MessagingService, client-to-server diagnostic telemetry, or new RemoteEvent/RemoteFunction was added.
- No automatic repair, restart, queue mutation, moderation, kick, ban, teleport, rubber-band, or gameplay restriction was introduced.
- Existing rate limits are not changed dynamically.
- Existing SecurityCore authorization, purchase receipts, moderation, security-event recording, and essential validation remain active in all modes.
- Existing Stage & Club Lighting server-side preset ownership is preserved; only local particle rates and stage/club light shadows are adjusted.
- Mobile UI layout and controls were not modified.

## Required Studio acceptance matrix

1. Verify installer staging/promotion/rollback with existing camera, integrity, and visual scripts present and absent.
2. Confirm the SecurityCore manifest pin matches the exact module/client release commit.
3. Verify no new RemoteEvent/RemoteFunction or replicated diagnostics endpoint exists.
4. Feed synthetic Heartbeat deltas and verify transition thresholds, counters, cumulative mode durations, and staged recovery.
5. Verify all five task buckets are bounded and token refill/burst accounting is correct.
6. Verify essential task names always pass in Normal, Reduced, and Critical.
7. Verify AnalyticsAggregation defers under Critical without making GetSnapshot, Check, ServerHealth, or watchdog unavailable.
8. Verify DiagnosticsSampling defers only passive movement measurements; existing movement property/velocity observations still run.
9. Verify the fractional per-player cost behaves correctly with 1, 10, and full-server player counts.
10. Test authorized VIP speed changes, size scaling, mount spawn/despawn, Tiki Tide Settings teleports, Kohl's authorized teleports, respawn, and scripted movement. Confirm no rubber-banding or false movement correction.
11. Test ClubEffect particle rates in all three modes, including effects tagged after startup and effects untagged while degraded.
12. Test StageClubLight shadows in all modes and confirm existing Enabled/Color/Brightness presets remain unchanged.
13. Change a tagged emitter's base Rate or light's Shadows from another authorized writer while adaptive mode is active; verify the client script preserves the newer baseline.
14. Test server mode recovery and LocalScript shutdown/restore behavior.
15. Profile server and client frame time, memory, rendering, and long-session cleanup.
16. Run playback controls, modern AudioPlayer, crossfade, local request queues, optional playback-only global sync, purchase receipts, moderation, Staff Controls, Utility Bar, Tool Shop, and all existing mobile/laptop layouts.

## Release gates

- [ ] Static syntax/type review completed in the Roblox Luau environment.
- [ ] Installer staged and rollback paths verified in a disposable Studio place.
- [ ] Adaptive state/token/hysteresis tests pass.
- [ ] VIP/mount/teleport/movement regression tests pass.
- [ ] Visual quality restoration and Stage & Club Lighting regression tests pass.
- [ ] Staff authorization and diagnostics lifecycle tests pass.
- [ ] Performance profiling and full gameplay regression suite pass.
- [ ] Published test-server acceptance passes.
- [ ] Project owner explicitly approves any later merge or live-place installation.

**Current result:** Source integration is committed to the development branch. All Roblox runtime and release gates above remain open.
