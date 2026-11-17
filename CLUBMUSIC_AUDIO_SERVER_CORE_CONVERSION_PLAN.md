# ClubMusic Audio Server-Core Conversion & Module Consolidation

**Branch:** `security/phase1-foundation`  
**Audit baseline:** `f62fd46e4ae17e12ae00dc01418d7bdd6208459f`  
**Status:** Source inventory completed; implementation is staged behind dependency and runtime gates.  
**Runtime status:** Owner reports modern audio playback is functional. This document does not claim independent Roblox Studio or published-server verification.

## Objective

Finish converting the remaining ClubMusic core responsibilities to a clear, server-owned architecture before retiring legacy playback dependencies. Preserve the working modern `AudioPlayer` path. Do not rewrite playback merely to consolidate modules.

The server controller remains the authority for playback state, per-server queue ownership, track selection, request accounting, action validation, DJ permissions, and state replication. Client modules may render state and store local preferences, but must not own authoritative playback, queue, playlist, DJ, or permission state.

## Audio instance and replication boundary audit (2026-11-16)

**Decision: do not move the modern AudioPlayer graph into ReplicatedStorage.** The existing runtime already uses the appropriate separation: server-created shared playback graph under `SoundService`, server-only modules in `ServerStorage`, and the per-listener output route created locally by the client preferences module.

- `UI_Server_Controller_server (1).lua` explicitly passes `SoundService` as the parent when creating the main modern backend, crossfade deck, and recovery replacement.
- `ClubMusicAudioBackend.luau` creates a managed folder containing the server-owned `AudioPlayer`, `AudioEqualizer`, `AudioFader`, and the two server-side `Wire` connections. The graph remains under `SoundService`.
- `ClubMusicPlayerPreferences.luau` observes replicated managed backend folders under the client's `SoundService`, then creates that client's private `AudioFader`, `AudioDeviceOutput`, and local `Wire` connections under its own local `SoundService`. This preserves per-listener volume without changing server gain or another player's output.
- The server ModuleScripts remain under `ServerStorage/ClubMusicAudioModules`; the client-only preferences ModuleScript remains under `ReplicatedStorage/ClubMusicClientAudioModules`.
- Do not replicate `AudioDeviceOutput` or the private output wires from the server. Each client creates its own output route.
- Keep queue state, catalog validation, playlist persistence, DJ sessions, authorization, transition ownership, recovery, and watchdog logic server-side. None belongs in `ReplicatedStorage`.
- `MemoryStoreService` is a separate cross-server ephemeral data service. Moving Instances into `ReplicatedStorage` does not preserve, replace, or reduce MemoryStore usage. The optional playback-only sync may continue using its existing server-side MemoryStore coordination independently of the audio graph.
- Roblox's audio documentation describes the 2D output graph using `SoundService` and identifies `AudioPlayer:Play()` / `Stop()` as server-to-client replicated actions. `AudioPlayer.IsReady` is explicitly not replicated, so decoder readiness must remain a server-side check; clients must not be made authoritative by reading it.

**Implementation result:** no runtime parent change is required for this boundary. The controller and backend already construct the server-owned graph in `SoundService`, and the client module already constructs local output routing. Moving the graph to `ReplicatedStorage` would be an unnecessary architectural change and could break the established audio routing. This is a verified source-layout decision, not a claim of Roblox Studio runtime certification.

## Non-negotiable invariants

1. Modern `AudioPlayer` is the only intended long-term playback source; the controller remains its lifecycle owner.
2. Each server owns its own request queue. Optional global playback-only sync shares the playing track/state only; it must never become a shared request queue.
3. `SecurityCore.Authorization` remains the sole permission authority. DJ/session modules may call injected authorization but must not implement a parallel role system.
4. Normal player song requests and Auto DJ remain available to all players; DJ Control Mode allows the current controller to request tracks while blocking other players. Requests remain subject to server-side catalog validation, request cooldowns/limits, queue capacity, idempotency, and abuse controls.
5. Pause, restart, DJ skip, playlist/catalog management, and DJ session/handoff actions require the appropriate SecurityCore-backed DJ/staff permission. `ReloadSong` is explicitly excluded: it is a self-service recovery action available to every live player under its existing cooldown and ingress limits. Read-only Now Playing/queue access and skip voting retain their existing player-facing behavior.
6. Queue, playlist rotation, skip-vote state, playback clocks, transition generations, and recovery ownership remain server-side.
7. Crossfade remains a separate lifecycle manager until its transition cancellation/commit behavior is proven stable.
8. Catalog and playlist persistence remain separate from in-memory playback/queue state.
9. Client audio preferences and local output routing remain client-side; never move client-only preferences into server modules.
10. Do not remove rollback assets, legacy adapters, or duplicate source files until all consumers, installer paths, embedded bundles, and live-place references are reconciled.

## Current server-side inventory

### Controller-loaded facades

| Module | Current role | Conversion decision |
|---|---|---|
| `ServerMusicAudioHandler.luau` | Backend-neutral snapshot and audio access adapter; still exposes legacy `Sound` methods | Merge with playback inspection into one server-only runtime adapter, or replace with controller-local helpers. Retain no independent playback ownership. |
| `MusicPlaybackManager.luau` | Playback snapshot, elapsed/remaining time, quality inspection, controller action delegation | Consolidate with `ServerMusicAudioHandler`. Preserve `InspectQuality()` semantics because watchdog/track-advance logic consumes quality state. |
| `MusicPlaylistManager.luau` | Thin facade over `MusicPlaylistService` and controller-owned rotation callbacks | **Consolidated in controller commit `ff748b8`.** Controller now calls its rotation functions directly; CRUD and refresh continue through `MusicPlaylistService`. Source file retained pending installed-place reconciliation. |
| `MusicSkipVoteManager.luau` | Thin facade over controller-owned vote state and callbacks | **Consolidated in controller commit `06e85c7`.** Controller now owns vote casting and player-departure cleanup directly; source file retained pending installer/live-place reconciliation. |

`MusicPlaybackManager` remains in the controller's `ChildManagerModules` list. `MusicPlaylistManager` and `MusicSkipVoteManager` have been removed from that list; rotation and vote call sites now call controller-owned functions directly. The facades do not independently own playback loops, queue state, playlist cursors, or vote timers.

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

#### Consumer audit — queue and validation (2026-11-16)

- The runtime controller requires only the direct child `ServerStorage.MusicQueueManager`; it does not require `MusicQueueManagerService` directly. The `.lua` adapter requires the direct child `ServerStorage.MusicQueueManagerService` and injects the controller-owned queue and request-slot release callback.
- Controller queue call sites use `Insert`, `PopNext`, `RemoveAt(index, true)`, `Clear(true)`, and `ClearAutomatic`. The service implements those operations over the injected table. `PopNext` releases the removed request slot; explicit `true` removals and clears release slots; `ClearAutomatic` preserves player requests and does not release player request slots.
- `MusicQueueManager.luau` retains a second config-backed queue and per-player counters. It is not loaded by the controller. The inspected ServerStorage and Audio Server RBXMX bundles do not contain either queue-manager name, and the inspected audio and SecurityCore installers do not install either queue module. Keep the legacy `.luau` source as a rollback artifact until the actual live-place ServerStorage hierarchy is confirmed.
- The controller requires only `ServerStorage.MusicValidationService`. Its live API contract is `GetAudioAssetInfo(assetId)` followed by `NormalizeAudioMetadata(assetId, info, duration)` after the controller independently preloads an `AudioPlayer` and confirms playability. The `.lua` service previously lacked `NormalizeAudioMetadata`; this audit added the bounded metadata-shaping method expected by the controller, without moving preload/playability checks into the cache service.
- `MusicValidationService.luau` is not loaded by the controller and contains extra legacy music-ID, spam, cooldown, player-validation, and `RoleSystem` logic. Those responsibilities remain outside the canonical metadata cache; request limits and authorization stay with the controller and SecurityCore.
- The inspected ServerStorage and Audio Server RBXMX bundles and the audio/SecurityCore installers contain no `MusicValidationService` source reference. Keep the `.luau` duplicate as a rollback artifact until live-place hierarchy reconciliation is complete.
- No repository deletion was made: the controller-facing adapter and service pair are the canonical queue path; `MusicValidationService.lua` is the canonical metadata path. Both legacy `.luau` variants remain unreferenced rollback candidates, not approved live runtime dependencies.

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

- **All players:** submit normal catalog requests while DJ Control Mode is off; view Now Playing/queue subject to existing visibility; vote to skip; and use `ReloadSong` for self-service audio recovery.
- **Current DJ controller:** the player who enables DJ Control Mode remains allowed to submit normal requests. Other players are blocked until the controller disables the mode or leaves. Only the current controller may disable it.
- **Auto DJ:** server-owned playback/refill continues regardless of DJ Control Mode.
- **ReloadSong:** available to every live player, with existing per-player cooldown and action ingress limits; no DJ permission is required.
- **Other privileged actions:** pause, restart, DJ skip, playlist/catalog management, and DJ session/handoff operations retain their appropriate SecurityCore-backed DJ/staff authorization.
- `SecurityCore.Authorization` remains the sole role/permission authority for privileged operations.
- Normal requests retain server validation, cooldowns, per-player limits, queue caps, duplicate checks, and abuse budgets.
- The separate emergency request lock remains a staff incident-response override and does not stop Auto DJ playback/refill.


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
- Playlist and skip-vote facade consolidation is complete in source (see implementation log).
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

## DJ session and backend configuration boundary audit (2026-11-16)

### DJ session manager — retain as a separate server-only lifecycle module

- The controller loads `ClubMusicDJSessionManager` through `findAudioModule`, supporting the direct ServerStorage location or `ServerStorage/ClubMusicAudioModules`. It is optional: if absent or initialization fails, session commands report that the module is unavailable rather than inventing a fallback authority.
- The controller injects both callbacks. `Authorize` checks that the player is still connected and calls `ControllerFunctions.isStaff`; `isStaff` derives its level from `authorizationService:GetLevel(player)`.
- `authorizationService` is obtained from `ServerStorage/ClubMusicSecurityCore/Authorization` via `GetShared`. If unavailable, rank level resolves to zero and staff checks fail closed. The DJ session module contains no role table, group-rank lookup, or independent permission cache.
- `OnHandoff` verifies both players remain connected and staff-authorized before updating their `ClubMusicActiveDJSession` attributes. The manager changes its current-session record only after that callback accepts the handoff.
- Session state and bounded history (50 entries) remain local to the manager. The controller handles Start, Handoff, End, status display, and player-departure cleanup. The manager does not own the audio backend, queue, playlist rotation, playback, or transition state.
- **Decision:** keep `ClubMusicDJSessionManager` separate in ServerStorage. Folding it into the controller would add coupling without removing a duplicate authority or meaningful backend configuration. Preserve its injected SecurityCore-backed authorization and controller-owned handoff callback.

### Audio quality profiles — keep separate, currently dormant

- `ClubMusicAudioQualityProfiles` is a small validated profile catalog (Standard, Soft, Bass, Night) that applies a coordinated playback-speed, server-gain, and equalizer tuple to an injected backend context.
- The current controller source does not require or reference `ClubMusicAudioQualityProfiles`; the module is provisioned by the package installer but is not an active controller runtime dependency in this branch.
- The profile module has no independent audio-instance ownership and does not contain per-player output preferences. Its server gain/EQ/speed settings are shared backend settings; client-local volume/mute remains in `ClubMusicPlayerPreferences`.
- **Decision:** do not fold profile definitions into `ClubMusicAudioBackend`. Backend methods remain low-level validated controls; profile selection/application is a distinct policy layer. Do not describe the profile feature as active until a controller or UI consumer is deliberately connected and tested. Keep the standalone and bundled source as a dormant compatibility module pending a separate product decision.

### Source and installer consistency

- Compared all five standalone server audio modules against the exact installer-pinned source revision `8edd537a30f002e39bd437a6d77f74e5ce66c2c6`: backend, crossfade manager, quality profiles, DJ session manager, and spatial graph all match byte-for-byte.
- Compared the embedded `ClubMusicAudioQualityProfiles` and `ClubMusicDJSessionManager` ModuleScript sources in `ClubMusic_Audio_Server_Modules.rbxmx` against their standalone files: both match byte-for-byte.
- The installer creates five server ModuleScripts in `ServerStorage/ClubMusicAudioModules` and one client ModuleScript in `ReplicatedStorage/ClubMusicClientAudioModules`. The controller's module lookup supports the installed folder layout.
- **Decision:** no installer, bundle, or module-source rewrite is required for this audit. Keep the existing pinned installer snapshot because its five server module sources match the current branch. Do not regenerate or re-pin bundles without a source change that requires it.

**Audit outcome:** the DJ session boundary is appropriately separate and SecurityCore-backed; the quality-profile module is provisioned but not currently consumed by the controller; backend low-level controls remain in the backend; and standalone, embedded, and installer-pinned sources are aligned for the five server audio modules. No runtime code was changed. Roblox Studio and published-server verification remain outstanding.

## Legacy Sound consumer closure audit (2026-11-16)

**Current state:** `CONFIG.UseModernAudioBackend = true`; modern AudioPlayer is the intended primary source. The controller still creates and retains `SoundService.ServerMusicSound` and `SoundService.MusicGroup` as guarded bootstrap/fallback compatibility objects. The Sound fallback is still reachable, so legacy retirement is not approved.

### Remaining active controller consumers

1. **Bootstrap and compatibility objects:** creates/reuses `ServerMusicSound` and `MusicGroup`, configures SoundGroup routing, migrates descendants from the obsolete `ClubMusic` SoundGroup, and initializes `activeAudioSource` as a Sound until modern startup succeeds.
2. **Backend-neutral source adapter:** `getAudioSnapshot`, `getAudioGain`, `setAudioGain`, playback-speed changes, asset assignment, seek, play, stop, pause, and resume all retain a `kind == "Sound"` branch.
3. **Startup and migration:** modern startup temporarily parks the controller on the Sound source while a candidate AudioPlayer loads. If modern startup fails, `startLegacyFallback` plays the Sound and schedules a bounded modern migration retry. The explicit `UseModernAudioBackend == false` branch also starts Sound.
4. **Crossfade commit/rollback:** crossfade completion still hard-mutes/stops/rewinds an outgoing Sound and can restore its playhead if commit/binding/queue-pop fails. This rollback path must be replaced with a modern-only recovery/rollback contract before removing Sound.
5. **Restart and reload:** `restartServerMusic` can restart a Sound source; `performReloadServerMusic` retains a full legacy Sound decoder-reset/reload branch. The modern branch already has same-backend reload and replacement-AudioPlayer rebuild.
6. **Watchdog and diagnostics:** source-kind/snapshot and active-playing signal binding support Sound. The watchdog reports the legacy `musicSound` instance to the error handler. Diagnostics expose modern-backend configuration/migration status.
7. **Client volume compatibility:** `UI_Renderer (2).lua` adjusts the local `MusicGroup.Volume` only when `SoundService.ClubMusicAudioSourceKind == "Sound"`. For modern playback, `ClubMusicPlayerPreferences.luau` builds a per-client `AudioFader -> AudioDeviceOutput` route. The MusicGroup path must remain until the Sound fallback is retired and the renderer compatibility branch is removed together.
8. **Inspection adapter:** `MusicPlaybackManager.luau` retains Sound-aware quality inspection. It is still controller-loaded for `InspectQuality()`; its remaining Sound branch must be removed or replaced with backend-only quality inspection before legacy retirement.
9. **Rollback/reference-only source:** `ServerMusicAudioHandler.luau` still contains Sound/SoundGroup compatibility code but was removed from this controller's runtime module list. Retain it as a rollback artifact until installer/live-place reconciliation, then retire separately.

### Non-Sound references that must remain

- `soundId` / `SoundIds` are historical data/API names for asset-ID strings and catalog fields; they are not by themselves a dependency on Roblox `Sound` instances.
- The temporary `AudioPlayer` used for asset validation and the modern backend's AudioPlayer graph are not legacy Sound dependencies.
- Per-client output routing and client-local volume preferences must remain; only the conditional SoundGroup fallback should be removed after its server fallback is gone.

### Retirement blockers and safe order

- Do not delete `ServerMusicSound` or `MusicGroup`, disable the fallback, or remove client SoundGroup volume support in this pass.
- First prove the startup path cannot select Sound and the controller never parks on a Sound source; replace the current candidate-load gap with a safe modern source lifecycle that preserves the last known-good AudioPlayer until the incoming backend is ready.
- Then convert crossfade rollback/commit to modern-only AudioPlayer recovery, including failure after incoming deck starts but before queue commit.
- Convert restart, reload, watchdog quality inspection, error reporting, and source-kind replication to AudioPlayer-only contracts. Keep the public `ReloadSong` permission and cooldown behavior unchanged.
- Only after those changes pass the full owner-run Studio matrix may the SoundGroup client compatibility path and bootstrap objects be removed. Reconcile RBXMX/installers/live-place references before deleting the old adapter source.

**Audit outcome:** all remaining legacy Sound runtime paths are classified above. No Sound path was removed because startup fallback and crossfade rollback still depend on it. Static inspection only; Luau compilation and Roblox runtime testing remain outstanding.

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


### Permission correction — 2026-11-16

- **Controller commit:** `0717dcbd7ccd31c5f4f356bcbdd388e7dac1e58d`
- Restored `ReloadSong` as a player-facing self-service recovery action; no `GlobalDJ` permission is required. Existing per-player cooldown, action ingress budget, and server-owned recovery remain.
- DJ Control Mode stores the enabling controller's UserId. That player may continue normal catalog requests; other players are blocked. Only the controller can disable the mode, and it clears automatically if the controller leaves.
- The same restriction is applied in the shared request-block helper for validated audio request paths. EmergencyLock remains separate.
- Auto DJ playback/refill remains independent of DJ Control Mode.
- Roblox Studio/published-server tests remain required.


### Skip-vote facade consolidation — source change committed

- **Controller commit:** `06e85c79872435095f197d707a4b1a6fbdd67459`
- Removed `MusicSkipVoteManager` from the controller's required child-manager module list and removed its initialization.
- Replaced the `VoteSkip` action's adapter call with `ControllerFunctions.castSkipVote`, keeping vote storage, duplicate-vote rejection, threshold calculation, track advancement, notifications, and state publishing in the server controller.
- Moved player-departure vote cleanup directly into the controller; the deferred threshold re-check remains so the departing player is no longer counted.
- Left `MusicSkipVoteManager.luau` in the repository as a rollback/reference artifact. Do not delete it until installer manifests, embedded bundles, and live-place references are reconciled.
- Static source checks passed for removal of runtime manager references and preservation of vote/cleanup paths.
- **Not yet verified:** Luau compilation, Studio/published-server skip voting, voter departure behavior, or concurrent vote/track-transition behavior. Owner runtime testing remains required.


### Playlist facade consolidation — source change committed

- **Controller commit:** `ff748b863dd357e9d8c5d3c381a1145219f70cf2`
- Removed `MusicPlaylistManager` from the controller's required child-manager module list and removed its initialization.
- `DJPlayPlaylist` and `DJStopPlaylist` now call the controller-owned `startPlaylistRotation` and `stopPlaylistRotation` functions directly.
- Persistent playlist CRUD, refresh, and readiness remain owned by `MusicPlaylistService`; playlist rotation tracks, cursor, selection, and queue refill remain controller-owned.
- Preserved the existing DJ booth authorization checks and playlist storage availability checks.
- Repository inventory shows `MusicPlaylistManager.luau` as a standalone source file; it is not embedded in `ClubMusic_ServerStorage_Modules.rbxmx` or the audio server bundle, and it is not listed in the audio module installer. The standalone file is retained for rollback until the live place's ServerStorage hierarchy is confirmed.
- Static source checks passed for removal of runtime manager references and preservation of persistent service, rotation state, and DJ authorization.
- **Not yet verified:** Luau compilation, Studio/published-server playlist start/stop, playlist CRUD/refresh, rotation cursor behavior, and queue refill. Owner runtime testing remains required.


## Rebuilt module audit — DJ sessions and backend configuration (2026-11-16)

The rebuilt five-module audio bundle was compared against its five standalone `.luau` sources on `security/phase1-foundation`. All five embedded ModuleScript sources are byte-for-byte identical to their standalone counterparts:

- `ClubMusicAudioBackend`
- `ClubMusicAudioCrossfadeManager`
- `ClubMusicAudioQualityProfiles`
- `ClubMusicDJSessionManager`
- `ClubMusicSpatialAudioGraph`

No source drift was found between the inspected bundle and standalone files. This does not establish which copy is installed in the live place; the controller intentionally prefers `ServerStorage/ClubMusicAudioModules` over direct ServerStorage children.

### DJ session manager

- The controller loads `ClubMusicDJSessionManager` as an optional server-only child from either supported ServerStorage layout.
- The manager owns only its bounded in-memory DJ session/current-history records. It does not own playback, queue, playlist rotation, or DJ Control Mode.
- Its injected `Authorize` callback delegates to `ControllerFunctions.isStaff`, which delegates to `authorizationService:GetLevel(player)`. The authorization service is the shared `ClubMusicSecurityCore.Authorization` instance. The manager does not implement its own role/group lookup.
- The `Authorize` callback currently treats Start, Handoff, and End identically (staff level required). Handoff additionally checks that the target is a connected staff member before the manager commits the new session owner.
- The controller clears the departing DJ's session through `EndForDeparture`; explicit End and Handoff update the player attributes at the controller boundary.
- Decision: keep this module separate for now. It is a small, coherent session-state boundary and is already injected with centralized authorization. Do not fold it into the controller merely to reduce the module count. If action-specific DJ-session permissions are introduced later, update the injected authorization policy and tests together.

### Backend configuration and optional modules

- `ClubMusicAudioBackend` exposes the configuration setters consumed by quality profiles: `SetGain`, `SetEqualizer`, and `SetPlaybackSpeed`. Its graph construction remains the modern server-owned AudioPlayer/EQ/fader graph under the injected parent.
- `ClubMusicAudioQualityProfiles` is present in the server bundle and matches its standalone source, but the current controller has no reference to or initialization path for it. It is dormant, not part of the active runtime configuration path. Do not fold it into the backend or claim that profile controls are active until a real controller/UI consumer is wired and tested.
- `ClubMusicSpatialAudioGraph` is likewise bundled and source-matched but has no controller reference in the inspected controller. It remains an optional spatial-routing utility, not an active default route. Keep it separate until a spatial-audio feature explicitly consumes it.
- `ClubMusicAudioCrossfadeManager` is actively loaded by the controller through `createAudioCrossfadeManager`; it creates incoming decks through the backend and remains a separate transition lifecycle boundary.
- `MusicPlaybackManager` is the only child playback facade loaded by the controller. `ServerMusicAudioHandler` is not referenced by the current controller and remains a duplicate/rollback candidate pending installer and live-place consumer reconciliation.

### Audit decision and next safe work

No runtime code was changed by this audit because the DJ-session authority boundary is already centralized and the two optional modules (quality profiles and spatial routing) have no active controller consumers. The five bundled module sources match their standalone counterparts exactly.

Next source-conversion target: consolidate the remaining playback inspection facade only after comparing every `MusicPlaybackManager` consumer and its `InspectQuality()` contract with the unused `ServerMusicAudioHandler` snapshot API. Preserve watchdog quality classifications, legacy fallback inspection until the modern-only retirement gate, and controller-owned playback state. Do not remove either source or regenerate the bundle until installer manifests and live-place module placement are reconciled.

**Runtime status:** static source inspection only; no Luau compilation, Roblox Studio, or published-server validation was performed for this audit.


## Playback inspection facade consolidation — source change committed (2026-11-16)

- **Playback adapter commit:** `17f54753e4d18cfbb1f56caba93fb4ded3b5bc9b`
- Extended the active `MusicPlaybackManager.luau` with the backend-neutral, read-only snapshot surface previously duplicated by the unreferenced `ServerMusicAudioHandler.luau`: `GetPlaybackSnapshot()`, `GetTimePosition()`, `GetTimeLength()`, and `GetCurrentSoundId()`.
- `GetPlaybackSnapshot()` consumes the controller-injected `GetAudioSnapshot` contract first, normalizes the snapshot fields, and uses the guarded legacy Sound accessor only as a compatibility fallback.
- Refactored `InspectQuality()` to consume that single normalized snapshot path. Preserved all watchdog-facing quality labels: `Idle`, `SilentCatalogTrack`, `Unavailable`, `Playing`, `Paused`, `StoppedAfterLoad`, and `BufferingOrStopped`.
- No playback state, queue, clock, remote, event connection, recovery policy, or playback loop was moved into the adapter. It remains a passive facade; controller callbacks remain the only mutation boundary.
- The controller still constructs the adapter with its canonical `GetAudioSnapshot` callback and remains the only current caller of `InspectQuality()` (the playback watchdog). No controller code change was needed.
- `ServerMusicAudioHandler.luau` remains in the repository as an unreferenced rollback/reference artifact; it was not deleted. The inspected `ClubMusic_Audio_Server_Modules.rbxmx` bundle does not contain either playback facade, so the live-place direct-child `ServerStorage.MusicPlaybackManager` installation dependency still needs explicit installer/live-hierarchy reconciliation before deleting or renaming either source.
- Static source checks confirmed the new snapshot methods, normalized snapshot path, preserved watchdog labels, and absence of active task/Heartbeat/event-loop ownership. No Luau compilation or Roblox Studio/published-server tests were performed.
- **Remaining gate:** verify the installed `MusicPlaybackManager` ModuleScript source matches this updated standalone file, exercise watchdog quality classifications with modern AudioPlayer and legacy fallback, and confirm pause/restart/reload plus recovery before considering legacy Sound retirement.


## Playback adapter installer reconciliation — 2026-11-16

The repository installation path is now explicit for the active playback inspection adapter:

- The controller's loader uses `ServerStorageForQueue = serverStorage` and performs a direct-child lookup for `MusicPlaybackManager`. It does not search `ServerStorage/ClubMusicAudioModules` for this facade.
- The controller requires the module at `ServerStorage.MusicPlaybackManager`; a nested copy in `ClubMusicAudioModules` does not satisfy that loader.
- `ClubMusic_Studio_CommandBar_Installer.lua` previously installed only the five server support modules inside `ServerStorage/ClubMusicAudioModules` and the client preferences module inside `ReplicatedStorage/ClubMusicClientAudioModules`. It did not provision the controller's playback adapter.
- Updated the installer to stage and install the canonical `MusicPlaybackManager.luau` source as a direct `ServerStorage` child. The adapter source is pinned to commit `44ad160be15ac14eca7907d7158fc81bae865c67`; the five server support modules and client preferences retain their existing audited package pin.
- The installer preflights the direct-child name and refuses to overwrite a non-ModuleScript. All six package sources and the playback adapter are downloaded and staged before installation begins.
- Updated `CLUBMUSIC_AUDIO_STUDIO_INSTALLATION.md` to show the required direct-child placement and verification step.
- The inspected `ClubMusic_Audio_Server_Modules.rbxmx` still does not contain `MusicPlaybackManager` or `ServerMusicAudioHandler`; no bundle regeneration was needed because the controller facade is now provisioned by the Command Bar installer separately.
- `ServerMusicAudioHandler.luau` remains unreferenced by the controller and is not installed by the current installer. It remains a rollback/reference file; do not delete it as part of this change.

**Live-place gate remains open:** the repository installer now defines the expected placement, but it cannot establish which source is currently present in an already-published place. In Studio, run the updated installer in a backed-up stopped-place copy, verify `ServerStorage.MusicPlaybackManager` is a ModuleScript with source matching the pinned standalone file, and confirm the controller starts without a module-loader error. Then exercise modern AudioPlayer quality snapshots, watchdog classifications, pause/restart/reload, recovery, and the legacy fallback path. Do not retire legacy Sound objects or delete `ServerMusicAudioHandler.luau` until those checks pass.


## Playback quality diagnostics — 2026-11-17

- The controller's server-only `GetClubMusicLocalDiagnostics` bridge now includes the active `MusicPlaybackManager:InspectQuality()` result in its playback summary.
- Added bounded, non-sensitive fields: `qualityState`, `qualityReason`, `qualityBackend`, `qualityLoaded`, and `qualityLength`. No asset IDs, player names, raw errors, or client telemetry are exposed.
- This makes the watchdog's existing quality classifications independently observable during Studio validation without adding a second polling loop or changing watchdog/recovery behavior.
- Static source review confirmed the modern backend snapshot is sourced through the controller's injected `GetAudioSnapshot`; legacy Sound inspection remains only a guarded fallback. The adapter continues to preserve the watchdog states `Idle`, `SilentCatalogTrack`, `Unavailable`, `Playing`, `Paused`, `StoppedAfterLoad`, and `BufferingOrStopped`.
- No legacy fallback removal is included. The next acceptance gate is owner-run Studio testing: confirm `migrationSucceeded=true`, `backend=AudioPlayer`, and `qualityState=Playing` during playback; verify `Paused` during pause and correct recovery/quality state after reload and a forced recoverable stop. Then verify a normal track transition and watchdog behavior before any legacy Sound retirement.
- This is a static code change only; no Luau compilation or Roblox runtime test was performed by the repository workflow.

### Legacy playback boundary audit and safe recovery handoff — 2026-11-17

- **Controller hardening commit:** `5e6eedf5d2efa556f57e9a9b36f9616a0f8adb12`
- Audited the current controller's remaining Sound-specific paths before attempting retirement. The legacy source is still deliberately constructed as `SoundService.ServerMusicSound`, with `SoundService.MusicGroup`, and is the initial source until the modern backend is adopted.
- Remaining Sound-dependent behavior is not isolated to a single fallback function. It is referenced by the normalized snapshot and gain/speed/play/stop/pause/resume adapters; modern-backend adoption rollback; initial-track startup fallback; same-track restart; the manual reload recovery branch; crossfade outgoing-deck gain/rollback/cleanup; the playback inspection adapter's optional `GetSound` callback; source-kind replication for client volume routing; and watchdog error context.
- The watchdog's stop/recovery decision itself is already source-neutral: it consumes `getAudioSnapshot()`, `seekAudio()`, `playAudio()`, and `MusicPlaybackManager:InspectQuality()`. Its error report still passes the legacy `musicSound` instance as context, which should be changed to the active source instance during a later diagnostics cleanup.
- Modern replacement recovery already follows the required last-known-good pattern: it creates a muted replacement graph, selects and verifies the asset, restores playback speed and playhead, verifies playing/paused state, restores gain, fences against concurrent track/source changes, then commits the new source and cleans up the old backend. A failed preparation cleans up only the candidate and leaves the current backend selected.
- **Hardening applied:** if the current backend's output gain cannot be read, replacement recovery now fails closed and leaves the current backend untouched. It no longer assumes gain `1`, which could cause an unexpected volume jump after a successful replacement.
- The startup migration path and crossfade rollback still intentionally support a legacy Sound source. Removing those branches now would remove the only guarded fallback for a startup migration failure and would invalidate rollback paths that have not yet been certified by owner-run Studio tests.
- **Next conversion boundary:** after the owner confirms the diagnostics matrix on the installed revision, make restart/reload/watchdog diagnostics modern-backend-only while retaining the isolated startup fallback; then convert crossfade cancellation/rollback to preserve a last-known-good modern deck without referencing Sound. Only after multiplayer/public regression passes should the controller stop creating `ServerMusicSound`/`MusicGroup` and retire the fallback.
- **Runtime status:** this audit and hardening are static source changes. No Luau compilation, Studio, or published-server tests were run. The diagnostics acceptance gate remains open.

### Modern-only restart/reload and source-aware watchdog diagnostics — 2026-11-17

- **Controller commits:** `d48e2627e9225e5ed5b3fd0e8fa454d2704a6517`, `cd6b9d9bf60f1ae4dfcb8b46342ff7c6fab6122b`
- Restart now reads the current asset and playing state through the normalized `getAudioSnapshot()` contract rather than reading Sound-specific properties. The actual seek/play action continues through the controller's source-neutral adapters, so the guarded startup fallback remains operable without duplicating Sound-specific restart logic.
- Manual reload is now a modern AudioPlayer recovery path. If startup is still using the guarded Sound fallback, reload first attempts the normal verified backend adoption. If adoption cannot complete, it returns safely without stopping, clearing, or reselecting the fallback Sound's asset.
- Once the modern backend is active, reload uses `AudioBackend:Reload()` and, if needed, the verified replacement-backend recovery path. The legacy Sound decoder-reset/reload branch has been removed.
- Paused-state handling is preserved: the verified fallback-to-modern adoption may transfer a paused track, backend reload restores its paused playhead, and final verification now accepts the expected paused state instead of incorrectly requiring `IsPlaying=true`.
- Watchdog error reporting now attaches the active source instance (AudioPlayer when modern, Sound only while the guarded fallback is active) rather than always reporting the bootstrap Sound.
- The guarded Sound remains only for initial bootstrap and modern-startup/migration failure. The next retirement work is crossfade rollback and transition cancellation; do not remove the fallback source object or client volume-routing compatibility until those consumers and public-server behavior are validated.
- **Runtime checks required on this revision:** normal modern restart; modern reload during playback; reload while paused (must remain paused at the restored playhead); fallback startup followed by successful modern adoption; fallback startup with forced migration failure (reload must leave fallback playback untouched); watchdog report context for both source kinds; normal crossfade and interrupted crossfade.
- **Runtime status:** static source edits and source checks only. No Luau compiler, Studio, or published-server test was run in this pass.

### Modern-only crossfade commit and rollback boundary — 2026-11-17

- **Controller commit:** `b1222a25010bd896b9b0844f21f0942525b397c9`
- The dual-deck crossfade coordinator now captures and attenuates an outgoing source only when the controller-owned active source is a modern `Backend` (`AudioPlayer`). The guarded bootstrap `Sound` fallback is explicitly transition-free.
- The controller entry point rejects crossfade requests while the guarded fallback is active and returns a clear reason; ordinary track advancement remains available and unchanged.
- The commit callback independently revalidates the outgoing source kind and backend reference before it can stop the outgoing deck or transfer ownership. The stop/rollback transaction now uses only the backend contract: if signal binding or queue consumption fails after stopping, it restores the previous backend at its captured playhead.
- Removed legacy Sound-specific crossfade stop, hard-mute, delayed decoder-tail cleanup, and rollback branches from the coordinator path. This does not remove the bootstrap Sound, its startup migration path, client volume compatibility, or any non-crossfade fallback behavior.
- Existing manager generation fencing, cancellation cleanup, outgoing-gain restoration, queue-head identity check, per-server queue pop, transition token check, and global playback-only sync behavior are unchanged.
- Static source checks confirmed fallback rejection at the entry point and gain-capture boundary, backend-only commit validation, no Sound-specific branch in the crossfade factory, and both rollback paths restoring the previous AudioPlayer backend.
- **Not yet verified:** Luau compilation, cancellation during decoder preparation/fade, queue-head changes during fade, bind failure/queue-pop failure rollback, gain restoration after interruption, fallback normal track advance, modern crossfade, and global playback-only sync in Studio/published servers. No Roblox runtime test was performed in this pass.
- **Next gate:** owner-run Studio tests for the listed transition cases. Keep the guarded startup Sound and remaining client compatibility until the full public-server regression gate passes.


### Transition cancellation metadata invalidation — 2026-11-17

- **Controller commit:** `e0b73fb04157595b804485a565293d7c4a4deeb8`
- Central cancellation now clears `pendingCrossfadeEntry` and resets `pendingCrossfadeToken` regardless of whether the optional crossfade manager exists or whether its cancellation/cleanup reports an error. This prevents stale prepared-queue metadata from surviving an absent manager or failed cleanup report.
- Manager destruction also invalidates pending transition metadata before teardown, including the no-manager case.
- The manager's own generation invalidation, incoming-deck stop/cleanup, and outgoing-gain restoration remain responsible for resource rollback. A reported cleanup failure is still surfaced and is not treated as a successful cancellation.
- Static checks confirmed both cancellation and destruction clear pending metadata before returning, and the obsolete “future transition” comment was removed.
- **Not yet verified:** Studio interruption/cancellation behavior, including cancellation before asset readiness, during the fade, and during server shutdown; no Roblox runtime test or Luau compilation was performed.


### Asynchronous crossfade failure reporting — 2026-11-17

- **Manager commit:** `535cd0c6fa204ca8202f62ba4421e0f9202ddffc`
- **Controller commit:** `f66518cd7ff03a3a83c15eead551c2a0691db7f6`
- Crossfade preparation and fade work runs asynchronously after `Begin` returns. Previously, decoder readiness timeout, incoming playback/gain failures, outgoing gain failures, or controller commit rejection cancelled the transition silently.
- Added a single failure path that invalidates the manager generation, stops and cleans the incoming deck, attempts to restore the outgoing gain, and reports the reason through the controller's warning logger. If cancellation cleanup itself reports a failure, that detail is included in the warning.
- The same reporting path now covers synchronous incoming-deck initialization failures after the coordinator has registered the deck. The normal track-advance fallback remains controller-owned and unchanged.
- This is diagnostic hardening only: it does not change queue ownership, transition timing, source selection, commit semantics, or guarded legacy startup fallback.
- **Static verification required:** confirm every asynchronous abort funnels through the reporting helper, manager generation invalidation precedes cleanup, and the controller warning callback is present. No Luau compilation, Studio, or published-server test has been run for this change.


### Transition settlement and outgoing-deck cleanup — 2026-11-17

- **Manager commit:** `c8e265061ac2fe5af76a02e5c763c54038303d12`
- **Controller commit:** `6f096d80dcdf02170e60a4260cd1973a22005ad2`
- Added a settlement callback for both successful commit and cancellation. The controller now clears the transition closure's references to the outgoing source, its source revision, and the captured outgoing gain once the transition no longer needs them. This avoids retaining a cleaned-up backend through the long-lived manager context between transitions.
- After ownership transfer, outgoing-backend cleanup failures are now logged instead of being silently discarded. The incoming backend remains the active source; cleanup failure is diagnostic and does not roll back an already committed track.
- Cancellation still restores outgoing gain before the settlement callback clears its reference. Failure reporting remains available after cancellation because the manager retains its controller context until explicit teardown.
- **Static checks required:** settlement is notified on both commit and cancellation; the controller clears all transition-scoped references; outgoing cleanup failures are surfaced; queue and source ownership remain controller-owned. No Luau compilation, Studio, or published-server test has been run.


### Crossfade commit ownership boundary audit (2026-11-17)

- The controller commit callback now treats queue consumption plus active-source assignment as the ownership-transfer boundary. Before that boundary, failures restore the outgoing source and allow coordinator cancellation; after it, bookkeeping failures must not be returned as commit failures because coordinator cancellation would destroy the incoming deck that is already active.
- After queue consumption and source assignment, the controller increments the source revision and wraps Now Playing mutation/publication in `pcall`. Failure is warned and the incoming deck remains committed.
- Deferred automatic queue top-up and state publication are independently protected and report failures without reversing the audio ownership transfer. Outgoing deck cleanup remains protected and warning-only after commit.
- The queue manager's `PopNext` releases the consumed entry's reserved slot. Its `Insert` method does not re-reserve that slot, so rollback after PopNext is not a safe generic compensation. The commit path therefore keeps all ordinary rejection paths before queue consumption and treats post-consumption bookkeeping as non-fatal.
- Static source review only. Studio acceptance must still exercise commit-time publication failure, deferred scheduling failure where reproducible, cancellation before commit, queue-slot accounting, repeated crossfades, and outgoing cleanup failure. No Roblox runtime verification is claimed.


### Crossfade manager startup, cancellation, and teardown race audit (2026-11-17)

- **Manager commits:** `2f3eb593d45a749844db8c64c8db544517a8d657`, `f801a29aef295d105fd89aad21884e0d10c1351f`, `2495ed6e3d21edcfdf3cb43ba35e18d807b0acf8`
- `Begin` now reserves a generation and marks startup in progress before invoking injected deck creation or gain-reading callbacks. A second Begin is rejected while setup is pending.
- If Cancel/Cleanup invalidates startup while an injected callback yields, the late continuation cleans up its unregistered deck and cannot install it into the manager. Rejected setup clears the reservation and notifies settlement so controller transition references are released.
- Cleanup closes admission by marking the manager destroyed before cancellation touches deck resources. A yielding cleanup operation therefore cannot leave a window for a new Begin.
- Sync initialization and async worker continuations are generation-fenced after potentially yielding calls. An obsolete worker cannot cancel or report failure against a newer transition after a Cancel/restart race.
- Worker scheduling failure is handled through the same generation-scoped cancellation path. Existing queue ownership and controller commit boundary remain unchanged.
- Static source review only. Studio acceptance still needs repeated Begin attempts during setup, Cancel during deck creation/gain read/initialization/fade, Cleanup during setup/fade, and immediate Begin attempts after cancellation/teardown. No Luau compilation or Roblox runtime verification is claimed.

- **Follow-up manager commit:** `3ff42a4dfba07cee9beda715795ca2e4216f0517` adds generation/ownership checks immediately after fade-step deck and gain operations. This prevents a worker that resumes after cancellation from continuing to attenuate the outgoing deck or attempting commit work.


### AudioPlayer graph resource ownership audit (2026-11-17)

- **Backend commits:** `b8c04961dcba7df190c74f4cd43ebb8225983373`, `018049ef31e890fc715499f6538d1237c6c5271c`
- **Transition/controller commits:** `9f6fd8d11bbb8c9d2cf9b8e12ddaa32c0ed24681`, `f0df6647a1becc76df681b38b3fcf5af3445775e`
- Backend graph construction now tracks each allocated Instance and rolls back in reverse allocation order if any property assignment, parenting, or Wire setup fails. A partially created Folder/AudioPlayer/AudioEqualizer/AudioFader/Wire graph is not intentionally left in SoundService.
- Backend Cleanup reports root or child destruction failures and falls back to individually destroying owned graph children when root destruction fails. It clears Lua references and wire lists after teardown attempts.
- Controller CreateDeck now wraps post-construction trim/player setup and invokes Backend Cleanup if setup fails before returning the deck to the transition manager.
- Manager cancellation and rejected-start cleanup now recognize a deck Cleanup method that returns false (not only a thrown error), and report cleanup failure through the controller failure callback.
- Static source checks only. Studio tests must verify no ClubMusicCrossfadeDeck roots or child instances accumulate after repeated transitions, injected setup failures, cancellation, and manager teardown. No Luau compilation or Roblox runtime verification is claimed.

- **Teardown follow-ups:** `c91e6e437c6d349cc61b3c3f15da346cd70b1461` and `68bc1f78e87edcd57797c513bf228b6f77e0271a` make child fallback teardown work even when the root reference is unavailable and preserve sparse child references safely.

- **Cleanup retry follow-up:** `93d5e8e8eeb314f993f368a3b669cf778dff9f1a` retains references to instances whose Destroy call fails and retries those instances on a subsequent Cleanup call, rather than dropping the only references after a failed teardown attempt.
