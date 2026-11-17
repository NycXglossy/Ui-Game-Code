# ClubMusic Audio Server-Core Conversion & Module Consolidation

**Branch:** `security/phase1-foundation`  
**Audit baseline:** `f62fd46e4ae17e12ae00dc01418d7bdd6208459f`  
**Status:** Source inventory completed; implementation is staged behind dependency and runtime gates.  
**Runtime status:** Owner reports modern audio playback is functional. This document does not claim independent Roblox Studio or published-server verification.

## Objective

Finish converting the remaining ClubMusic core responsibilities to a clear, server-owned architecture before retiring legacy playback dependencies. Preserve the working modern `AudioPlayer` path. Do not rewrite playback merely to consolidate modules.

The server controller remains the authority for playback state, per-server queue ownership, track selection, request accounting, action validation, DJ permissions, and state replication. Client modules may render state and store local preferences, but must not own authoritative playback, queue, playlist, DJ, or permission state.

## Non-negotiable invariants

1. Modern `AudioPlayer` is the only intended long-term playback source; the controller remains its lifecycle owner.
2. Each server owns its own request queue. Optional global playback-only sync shares the playing track/state only; it must never become a shared request queue.
3. `SecurityCore.Authorization` remains the sole permission authority. DJ/session modules may call injected authorization but must not implement a parallel role system.
4. Normal player song requests and Auto DJ remain available to all players; neither may be wrapped in a DJ/staff authorization gate or disabled by DJ Control Mode. They remain subject to server-side catalog validation, request cooldowns/limits, queue capacity, idempotency, and abuse controls.
5. Privileged playback controls (play/pause/restart/reload/skip), playlist management, catalog mutation, and DJ session/handoff actions require the appropriate SecurityCore-backed DJ/staff permission. Read-only Now Playing/queue access and skip voting retain their existing player-facing behavior.
4. Queue, playlist rotation, skip-vote state, playback clocks, transition generations, and recovery ownership remain server-side.
5. Crossfade remains a separate lifecycle manager until its transition cancellation/commit behavior is proven stable.
6. Catalog and playlist persistence remain separate from in-memory playback/queue state.
7. Client audio preferences and local output routing remain client-side; never move client-only preferences into server modules.
8. Do not remove rollback assets, legacy adapters, or duplicate source files until all consumers, installer paths, embedded bundles, and live-place references are reconciled.

## Current server-side inventory

### Controller-loaded facades

| Module | Current role | Conversion decision |
|---|---|---|
| `ServerMusicAudioHandler.luau` | Backend-neutral snapshot and audio access adapter; still exposes legacy `Sound` methods | Merge with playback inspection into one server-only runtime adapter, or replace with controller-local helpers. Retain no independent playback ownership. |
| `MusicPlaybackManager.luau` | Playback snapshot, elapsed/remaining time, quality inspection, controller action delegation | Consolidate with `ServerMusicAudioHandler`. Preserve `InspectQuality()` semantics because watchdog/track-advance logic consumes quality state. |
| `MusicPlaylistManager.luau` | Thin facade over `MusicPlaylistService` and controller-owned rotation callbacks | Fold into controller/service boundary after every method caller is mapped. Do not move rotation cursor or playback selection into persistent storage. |
| `MusicSkipVoteManager.luau` | Thin facade over controller-owned vote state and callbacks | Fold into controller vote functions after all consumers and player-departure cleanup paths are mapped. |

These four are currently loaded by the controller's `ChildManagerModules` list and instantiated with injected controller callbacks. They do not independently own playback loops, queue state, playlist cursors, or vote timers. Their consolidation should reduce module count without changing behavior.

### Core server audio modules

| Module | Current role | Conversion decision |
|---|---|---|
| `ClubMusicAudioBackend.luau` | Creates and owns the modern AudioPlayer graph | Keep as the backend implementation behind the controller-owned runtime boundary. |
| `ClubMusicAudioCrossfadeManager.luau` | Controller-invoked dual-deck transition coordinator with generation-based cancellation | Keep separate. Its lifecycle and safe commit/cancellation semantics are distinct. |
| `ClubMusicAudioQualityProfiles.luau` | Validated gain/speed/EQ profile application | Fold into backend configuration only if this keeps the backend cohesive and does not obscure profile validation. Otherwise keep as a small backend submodule. |
| `ClubMusicDJSessionManager.luau` | DJ session/handoff state with injected authorization | Keep server-only. It may be folded into controller DJ management only after session lifecycle and handoff callbacks are fully mapped. It must not become an authorization authority. |
| `ClubMusicSpatialAudioGraph.luau` | Optional AudioPlayer-to-emitter/listener/output graph lifecycle | Keep separate while optional spatial routing exists; resource ownership and teardown are distinct. |

The five core sources above are stored as ModuleScripts in `ClubMusic_Audio_Server_Modules.rbxmx` and also exist as standalone `.luau` files. A canonical source policy must be established before either copy is edited.

### Queue, catalog, validation, and persistence

- `MusicQueueManager.lua` is the controller's expected adapter and delegates to `MusicQueueManagerService.lua`.
- `MusicQueueManagerService.lua` mutates the injected controller-owned queue and does not create a second queue or own playback.
- `MusicQueueManager.luau` is a second implementation that retains a legacy config-backed mode. It is a duplicate retirement candidate, but **must not be deleted** until every installer, package, and live-place consumer is confirmed to use the canonical adapter/service pair.
- `MusicCatalogService.lua` owns catalog lookup/storage; keep it separate from queue and playback state.
- `MusicPlaylistService.lua` owns persistent playlist storage; keep it separate from the in-memory rotation cursor and playback owner.
- `MusicValidationService.lua` is the controller's current expected validation module.
- `MusicValidationService.luau` is a second implementation with a separate legacy dependency. Retire it only after all repository, bundle, installer, and live-place consumers are mapped. Do not duplicate SecurityCore rate limiting or authorization in either validator.

### Client-only boundary

`ClubMusicPlayerPreferences.luau`, bundled in `ClubMusic_Audio_Client_Modules.rbxmx`, remains client-side. It may own local output preferences only. No server authority, permissions, queue mutation, playlist persistence, DJ sessions, or recovery logic should move to the client.

## Target architecture

1. **Server Audio Runtime** — one compact server module boundary for backend access, playback snapshots, elapsed/remaining time, quality inspection, and modern backend recovery integration. The controller owns the active source and playback state.
2. **Server Audio Transitions** — separate crossfade coordinator; controller owns transition invocation and commits.
3. **Server Queue & Catalog** — controller-owned per-server queue, canonical queue adapter/service, catalog lookup, metadata validation, request accounting.
4. **Server DJ & Playlist** — SecurityCore-authorized DJ sessions, playlist persistence, controller-owned rotation, and controller-owned skip voting.
5. **Server Audio Support** — existing watchdog, error handler, recovery reporting, and bounded server-local diagnostics. Do not merge unrelated global security services into the audio runtime.

Spatial routing remains a separate optional server resource service. Client preferences remain client-side.

## Permission boundary and acceptance rules

- **All players:** submit normal catalog song requests; use Auto DJ as the fallback/refill system; view Now Playing and the queue subject to existing visibility; cast skip votes subject to existing vote rules.
- **Authorized DJ/staff:** use privileged playback controls, reload/recovery controls, playlist management, catalog mutation, and DJ session/handoff actions according to the existing SecurityCore permission levels.
- `SecurityCore.Authorization` is the only role/permission authority. `getLevel` and DJ checks are projections/delegations to that service, not local role tables.
- Normal requests must never call `GlobalDJ` or require staff rank. Keep server validation, cooldowns, per-player request limits, queue caps, duplicate-track checks, and abuse budgets.
- DJ Control Mode is a booth/control-state indicator only; it must not close ordinary player requests or disable Auto DJ.
- The separate emergency request lock remains an explicit staff incident-response override; it must not stop server-owned Auto DJ playback/refill.

## Implementation sequence

### Step 1 — Source-of-truth and consumer closure (current step)
- Inventory every direct/transitive `require`, controller call site, installer manifest, embedded RBXMX ModuleScript, and known hierarchy dependency.
- Compare standalone module text against embedded ModuleScript sources and record drift.
- Map every consumer of both queue implementations and both validation implementations.
- Record all consumers of the four facades and the watchdog's quality-inspection contract.
- Confirm the actual installed ServerStorage names and whether old source variants remain in the live place.

**Exit gate:** no ambiguous source owner or unclassified consumer remains for a module selected for consolidation.

### Step 2 — Consolidate thin server facades
- Merge `ServerMusicAudioHandler` and `MusicPlaybackManager` into one runtime adapter (or controller-local helpers) while preserving public method behavior and watchdog quality inspection.
- Fold playlist and skip-vote facades into their existing controller/service boundaries only after exact consumer mapping.
- Keep queue, playback, playlist rotation, and vote state owned by the controller.

**Exit gate:** no behavior change in pause/resume/restart/reload, watchdog advancement, playlist rotation, skip voting, or player-departure cleanup.

### Step 3 — Canonical queue and validation services
- Make the `.lua` adapter + `MusicQueueManagerService.lua` the only canonical queue implementation if consumer audit confirms it.
- Remove legacy config-backed queue behavior only after all callers are migrated.
- Keep one canonical metadata validation service and migrate consumers before retiring the duplicate.
- Preserve request-slot release callbacks, queue ordering, queue limits, idempotency, and per-server isolation.

**Exit gate:** one canonical queue path and one canonical validation path across source, installer, package, and live hierarchy.

### Step 4 — Server DJ and backend configuration cleanup
- Consolidate DJ session state only where controller callbacks and lifecycle behavior remain unchanged.
- Fold quality profile definitions into backend configuration only if the backend remains cohesive and profile validation remains explicit.
- Keep SecurityCore as sole authorization authority.

### Step 5 — Modern-only recovery and legacy Sound retirement
- First convert every consumer: runtime adapter, watchdog, pause/restart/reload actions, recovery, crossfade fallback, diagnostics, and error messages.
- Then disable the legacy Sound fallback behind an explicit test gate.
- Remove legacy Sound code only after modern playback, reload, transitions, recovery, and multi-server behavior pass the owner-run test matrix.

**Exit gate:** no active legacy Sound path or legacy-only consumer remains; rollback procedure is recorded.

### Step 6 — Bundle and installer canonicalization
- Select canonical standalone source files and generate the server RBXMX bundle from those exact sources (or establish the reverse if the installer requires embedded sources).
- Pin all source revisions in installer manifests.
- Verify the installed ModuleScript names, source hashes, and server-only placement.
- Do not leave standalone and embedded copies drifting.

## Required runtime acceptance matrix

- Startup and first track; track change; natural end; silent/catalog-only track.
- Pause/resume, restart, seek/reload, volume/gain and playback-speed profiles.
- Crossfade success, cancellation, failed incoming deck, and safe outgoing-deck preservation.
- Modern AudioPlayer rebuild/recovery and watchdog quality classification.
- Request queue insert/pop/remove/clear, slot release, player departure, concurrency and burst requests.
- Independent queues in two servers while playback-only global sync is enabled and disabled.
- Global sync leader failover and recovery after temporary DataStore/MemoryStore outage.
- DJ start/end/handoff, playlist CRUD/rotation, skip voting and voter departure.
- SecurityCore authorization failure and service-unavailable fail-closed behavior.
- Studio/public data separation, shutdown cleanup, and PC/mobile/console controls.

## Rollback and release gates

- Do not change profile schema, receipt ledger, product/pass IDs, remote contract, global playback sync semantics, or per-server queue ownership as part of module consolidation.
- Keep the last known functional modern AudioPlayer implementation and current installer revision available for rollback.
- If a conversion causes playback/watchdog/queue regressions, restore the previous server module set before attempting further consolidation.
- Static source inspection is not a substitute for Roblox Studio or published-server testing.
- No phase is runtime-certified until the owner records the tested commit and results.

## Initial source findings

- The controller loads the four facade modules through `ChildManagerModules`.
- `MusicPlaybackManager:InspectQuality()` is used by controller watchdog/advance logic and must be preserved.
- The controller currently loads `MusicQueueManager` from ServerStorage; the standalone `.lua` adapter delegates to `MusicQueueManagerService`.
- The duplicate `.luau` queue implementation includes a legacy config-backed API.
- The controller expects `MusicValidationService`; a second `.luau` implementation exists and must be consumer-audited before retirement.
- The modern AudioPlayer backend is already the intended primary source, but the controller still contains a guarded legacy Sound fallback. This plan does not remove it prematurely.
- The global playback-only sync and local queue ownership model are preserved.


## Implementation log

### Server audio facade consolidation — source change committed

- **Controller commit:** `c5af3a44c003f386adf333f5ae8c56ebdceffe5e`
- Removed `ServerMusicAudioHandler` from the controller's required child-manager module list.
- Removed the unused `ControllerFunctions.ChildManagers.Audio` instance; the controller had no consumers of that instance.
- Injected `ControllerFunctions.getAudioSnapshot()` directly into `MusicPlaybackManager`, removing the redundant snapshot adapter layer.
- Preserved `MusicPlaybackManager:InspectQuality()`, which is still consumed by watchdog/track-advance logic.
- Preserved the guarded legacy Sound fallback and its adapter compatibility for this incremental step.
- Left `ServerMusicAudioHandler.luau` in the repository as a rollback/reference artifact; it is no longer required by this controller revision. Do not delete it until installer and live-place references are reconciled.
- Post-edit source inspection confirms there are no `ChildManagers.Audio` references, the direct controller snapshot is injected, and the watchdog quality probe remains present.

**Not yet verified:** Luau compilation, Roblox Studio playback controls, watchdog behavior, published-server playback, or multi-server queue/sync behavior. Owner runtime testing remains required.

### Permission boundary source audit — 2026-11-16

- Confirmed the controller loads `SecurityCore.Authorization`; `canUseDJBooth` delegates to `Authorization.Check(..., "GlobalDJ")` and rank projections come from the same service.
- Confirmed normal `RequestTrack` is a separate public action with server validation, request cooldown/limits, queue-capacity and duplicate checks; it does not require DJ authorization.
- Found two mismatches against the required acceptance rules: DJ Control Mode rejected normal requests, and `ReloadSong` had no DJ authorization check. The next controller patch removes the request lock and gates reload through SecurityCore-backed DJ authorization.
- Auto DJ refill is server-owned and remains independent of DJ permissions.

### Permission boundary conversion — source changes committed

- **Controller commit 1:** `78ce2750b27cd0e2a6c2af0a8d936650f8a83480`
- **Controller commit 2:** `67f4af62f0f8c5376ec18b574140be12ba121c60`
- Split `djControlModeEnabled` from the existing emergency `requestsLocked` state.
- DJ Control Mode no longer rejects normal `RequestTrack` submissions. The request path retains server-side catalog/playability checks, staff blocks, queue capacity, cooldowns, per-player request limits, duplicate-track rejection, and server action budgets.
- Replicated `djControlMode` independently from `locked`; status now distinguishes `OPEN (DJ CONTROL)` from the explicit `EMERGENCY LOCK` state.
- Auto DJ remains controller-owned and its refill path does not consult DJ permissions or the emergency player-request lock.
- Added `canUseDJBooth` authorization to `ReloadSong`; the helper delegates to `SecurityCore.Authorization.Check(..., "GlobalDJ")` and fails closed when authorization is unavailable.
- Playlist and catalog mutation remain staff-gated; DJ booth queue/playback controls retain their existing SecurityCore-backed rank checks.
- **Exception:** the existing explicit emergency request lock continues to reject ordinary player requests as a staff incident-response action. It does not stop Auto DJ playback/refill.
- **Not yet verified:** Luau compilation, UI compatibility with the added `djControlMode` state field, normal request submission while DJ Control Mode is on, reload denial/allowance, emergency lock behavior, Auto DJ refill, or Roblox runtime playback. Owner testing remains required.
