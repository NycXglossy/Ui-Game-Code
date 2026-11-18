# ClubMusic Audio Server-Core Conversion & Module Consolidation

**Branch:** `fix/security-core-release-and-queue-loop`  
**Phase 30 status:** Server-first audio, media ingress, optional playback-only sync, and bundle/installer reconciliation are in source integration.  
**Runtime status:** Static repository audit only. Studio and published two-server certification remain outstanding.

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
- Optional playback-only global sync is part of the current Phase 30 design but is disabled by default. When enabled, MemoryStore provides only a fenced leader lease, DataStore stores only the current Now Playing snapshot/playhead, and MessagingService publishes revision invalidations. No queue, playlist cursor, request accounting, or Auto DJ state is shared. If disabled, each server owns its playback and request queue independently.
- Roblox's audio documentation describes the 2D output graph using `SoundService` and identifies `AudioPlayer:Play()` / `Stop()` as server-to-client replicated actions. `AudioPlayer.IsReady` is explicitly not replicated, so decoder readiness must remain a server-side check; clients must not be made authoritative by reading it.

**Implementation result:** no runtime parent change is required for this boundary. The controller and backend already construct the server-owned graph in `SoundService`, and the client module already constructs local output routing. Moving the graph to `ReplicatedStorage` would be an unnecessary architectural change and could break the established audio routing. This is a verified source-layout decision, not a claim of Roblox Studio runtime certification.

## Non-negotiable invariants

1. Modern `AudioPlayer` is the only intended long-term playback source; the controller remains its lifecycle owner.
2. Each server independently owns its request queue, playlist cursor, Auto DJ refill, request accounting, and skip votes. Optional global playback sync shares only Now Playing/playhead under a fenced leader; it never shares or consumes another server's queue.
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
| `ServerMusicAudioHandler.luau` | Historical backend/Sound adapter | Not present in the current tracked branch tree and not loaded by the current controller. Treat any live-place copy as rollback-only pending hierarchy inspection. |
| `MusicPlaybackManager.luau` | Historical playback facade and quality inspector | **Consolidated into controller-local `inspectPlaybackQuality()`.** The controller no longer loads it; the current installer no longer provisions it. The standalone source remains as a rollback artifact until live-place consumers are checked. |
| `MusicPlaylistManager.luau` | Historical facade over `MusicPlaylistService` and controller-owned rotation | Consolidated in the existing controller path; not loaded by the current controller. Keep source as rollback until live-place reconciliation. |
| `MusicSkipVoteManager.luau` | Historical facade over controller-owned vote state | Consolidated in the controller path; not loaded by the current controller. Keep source as rollback until live-place reconciliation. |

The current controller owns playlist rotation, skip-vote state, playback quality classification, watchdog decisions, and playback state. No separate facade owns a playback loop, queue, playlist cursor, or vote timer. The `MusicPlaybackManager` quality classifications are preserved in controller-local code and use only the modern AudioPlayer snapshot.

### Core server audio modules

| Module | Current role | Conversion decision |
|---|---|---|
| `ClubMusicAudioBackend.luau` | Creates and owns the modern AudioPlayer graph | Keep as the backend implementation behind the controller-owned runtime boundary. |
| `ClubMusicAudioCrossfadeManager.luau` | Controller-invoked dual-deck transition coordinator with generation-based cancellation | Keep separate. Its lifecycle and safe commit/cancellation semantics are distinct. |
| `ClubMusicAudioQualityProfiles.luau` | Validated gain/speed/EQ profile application | Fold into backend configuration only if this keeps the backend cohesive and does not obscure profile validation. Otherwise keep as a small backend submodule. |
| `ClubMusicDJSessionManager.luau` | DJ session/handoff state with injected authorization | Keep server-only. It may be folded into controller DJ management only after session lifecycle and handoff callbacks are fully mapped. It must not become an authorization authority. |
| `ClubMusicSpatialAudioGraph.luau` | Optional AudioPlayer-to-emitter/listener/output graph lifecycle | Keep separate while optional spatial routing exists; resource ownership and teardown are distinct. |

The five core sources above exist as standalone `.luau` files and are embedded byte-identically in `ClubMusic_Audio_Server_Modules.rbxmx`. Standalone sources are canonical; the RBXMX bundle is regenerated from them and checked for exact source equality.

### Queue, catalog, validation, and persistence

- `MusicQueueManager.lua` is the canonical controller adapter and delegates to `MusicQueueManagerService.lua`; it supports both direct ServerStorage installation and the `ClubMusic_ServerStorage_Modules` bundle folder.
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
- `ClubMusic_ServerStorage_Modules.rbxmx` now contains the canonical `MusicQueueManager`, `MusicQueueManagerService`, and `MusicValidationService.lua` sources alongside catalog, playlist, and receipt-hash modules. The Command Bar installer stages and installs the six controller-required ServerStorage core modules directly. The legacy `.luau` validation duplicate remains outside the bundle and installer.
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

## Modern-only Sound retirement audit — Phase 30

**Current tracked-source state:** the controller has no Roblox `Sound` playback path. Static search of the current controller found no `Instance.new("Sound")`, `IsA("Sound")`, `FindFirstChildWhichIsA("Sound")`, `ServerMusicSound`, `MusicGroup`, `musicSound`, `startLegacyFallback`, or `kind == "Sound"` branch. The controller creates, owns, reloads, recovers, pauses, restarts, crossfades, and diagnoses modern `AudioPlayer` instances only.

### Consumer conversion status

1. **Backend and source lifecycle:** modern AudioPlayer is the only controller source. Startup fails closed if it cannot create/readiness-check the modern backend; restart and reload never start a legacy Sound fallback.
2. **Crossfade:** the crossfade coordinator is modern AudioPlayer-only. Its commit, cancellation, and rollback paths do not adopt or restore a Sound source. If crossfade is unavailable, normal modern track advance remains the only fallback.
3. **Watchdog and recovery:** watchdog quality inspection is now controller-local and reads `ControllerFunctions.getAudioSnapshot()`. It preserves the prior quality states (`Idle`, `SilentCatalogTrack`, `Unavailable`, `Playing`, `Paused`, `StoppedAfterLoad`, and `BufferingOrStopped`) without a Sound adapter.
4. **Pause/restart/reload:** server controller methods operate on the modern backend. `ReloadSong` remains available to every live player under its cooldown/rate limits; it does not require DJ permission.
5. **Client volume and output routing:** `UI_Renderer (2).lua` and `ClubMusicPlayerPreferences.luau` use per-client AudioFader/AudioDeviceOutput routing. Static search found no `MusicGroup` or `ServerMusicSound` references in the current renderer/preferences module.
6. **Inspection facade:** the controller no longer requires `MusicPlaybackManager.luau`; the quality inspector was moved into controller-local code. The module source remains a rollback artifact, and the current installer no longer provisions it.
7. **Historical modules and place objects:** `ServerMusicAudioHandler.luau` is absent from the current tracked tree. Existing live-place copies of that module, `MusicPlaybackManager`, `ServerMusicSound`, or `MusicGroup` must not be deleted until the actual place hierarchy and all external consumers are inspected.

### Non-Sound media references that remain valid

- `soundId` / `SoundIds` are historical field names for Roblox audio asset-ID strings, not `Sound` instances.
- The temporary AudioPlayer used by the server validation service confirms an asset is playable; it is not a legacy Sound fallback.
- The client UI's AudioPlayer preview is local to that player, uses a private AudioDeviceOutput, and cannot mutate server playback or another player's output.
- Artwork is rendered from server-returned catalog metadata. The server accepts optional artwork only after `MarketplaceService:GetProductInfo` confirms `Enum.AssetType.Decal`; audio assets are separately validated as `Enum.AssetType.Audio`.
- No active boombox remote, animation asset mutation endpoint, or server animation playback endpoint was found in the tracked Lua/Luau source scan. The only animation-related server observation found is `Humanoid:GetPlayingAnimationTracks()` for Dance Floor activity eligibility; it does not play or mutate animations.
- The Studio Kohl's hardening patch contains `InsertService` text only in the patch/replacement validation logic; it asserts the installed loader no longer references external asset insertion. It is not an active audio/media loader.

### Retirement decision and remaining gate

- **The guarded Sound fallback is retired from the tracked controller and controller-loaded playback adapter path.** The current controller no longer creates or adopts Sound instances, and the quality facade no longer provides a Sound fallback.
- Do not delete existing live-place Sound objects or rollback modules solely from this source audit. First inspect the actual live-place hierarchy, all Script/LocalScript/ModuleScript consumers, plugins, third-party packages, and any client-side volume compatibility.
- Run Studio tests for modern playback, reload, restart, pause/resume, crossfade, watchdog recovery, per-client volume, and PC/mobile/console before removing legacy place objects.
- Reconcile embedded bundles and installers before deleting any duplicate source. The current installer does not provision `MusicPlaybackManager`; the standalone file is retained as rollback until live-place reconciliation.

**Audit outcome:** no active legacy Sound fallback remains in the current tracked controller path. This is static source evidence only; Luau compilation, Studio runtime, live-place consumer inspection, and published-server tests remain outstanding.

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

- Do not change profile schema, receipt ledger, product/pass IDs, remote contract, or per-server queue ownership as part of module consolidation. Global playback sync is retired and must not be reintroduced.
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
- Global playback sync is retired; independent per-server queue ownership is preserved.


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
- Existing manager generation fencing, cancellation cleanup, outgoing-gain restoration, queue-head identity check, per-server queue pop, and transition token checks are unchanged. Each server advances only its own queue.
- Static source checks confirmed fallback rejection at the entry point and gain-capture boundary, backend-only commit validation, no Sound-specific branch in the crossfade factory, and both rollback paths restoring the previous AudioPlayer backend.
- **Not yet verified:** Luau compilation, cancellation during decoder preparation/fade, queue-head changes during fade, bind failure/queue-pop failure rollback, gain restoration after interruption, fallback normal track advance, and modern crossfade in Studio/published servers. No Roblox runtime test was performed in this pass. Global playback sync is retired and is not a test target.
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


### Controller active-source retirement audit (2026-11-17)

- **Controller commits:** `f3f79b3b77c272d4298859d8c9486658cc0a0ab7`, `1d31496fba304c65464a4da84185c147c0c3ae21`
- Added a controller-owned backend retirement helper for non-crossfade source replacement. It checks both thrown errors and explicit `false` cleanup results, logs the reason, retries cleanup up to three times with backoff, and retains failed backend references in a registry for diagnosis and later retry.
- Routed adoption rejection, backend adoption, new-track startup retirement, modern startup candidate discard, startup source replacement, recovery candidate abandonment, and watchdog recovery replacement through the helper.
- Crossfade deck ownership remains with the crossfade manager; its incoming cancellation and outgoing post-commit cleanup are intentionally not routed through the general active-source helper.
- Static source checks only. Studio acceptance must exercise failed adoption, stale startup cancellation, fallback-to-modern migration, watchdog recovery, and repeated track changes while checking SoundService for orphaned backend roots and verifying failed cleanup retries. No Luau compilation or Roblox runtime verification is claimed.

### Crossfade failed-deck retention audit (2026-11-17)

- **Manager commit:** `a7bbbaca3c8faf7dda32e16f62d4eb9239c4b483`
- **Controller commit:** `89a859778702978baf4da586e885b61f95d8d8ab`
- The crossfade manager now keeps references to incoming decks whose `Cleanup()` throws or returns `false`. It retries teardown up to three times with bounded backoff and leaves a final failure in a manager-owned pending registry for a later explicit `Cleanup()` attempt.
- Both cancellation and rejected-start cleanup use the same retention path. Manager teardown can be called again after destruction to retry pending decks; it does not admit new transitions, and a pending cleanup is reported rather than silently treated as complete.
- After a successful crossfade ownership transfer, the controller now retires the outgoing backend through its controller-owned retirement registry. Failed outgoing cleanup therefore remains reachable for bounded retries and later diagnosis; the newly committed incoming backend is not passed to cleanup.
- Ownership boundary remains explicit: the manager retires cancelled/rejected incoming decks; the controller retires the outgoing backend only after the incoming backend has become authoritative.
- Static source checks only. Studio acceptance should force `Cleanup()` to throw and return `false` during cancellation and rejected startup, verify retry/pending retention across repeated manager teardown calls, then complete a successful commit and confirm the incoming AudioPlayer remains active while the outgoing deck is retired. Also test rapid repeated transitions and inspect SoundService for orphaned deck graphs. No Luau compilation or Roblox runtime test was performed in this pass.

### Crossfade shutdown and server-removal cleanup audit (2026-11-17)

- **Manager commit:** `2ffe9e48c38fa5a15ca9a194139b70d0ae32cc43`
- **Controller commit:** `26a84d6eae73b51e199a214f2213f5c9fb464e02`
- Crossfade manager teardown now waits for already-running bounded deck-cleanup retries to settle, then performs a final bounded retry pass for decks retained as pending. Repeated `Cleanup()` calls remain safe after destruction and do not reopen transition admission.
- Controller shutdown now destroys/cancels the crossfade manager first (preserving its outgoing-gain restoration path), stops the currently authoritative backend or guarded bootstrap Sound, retires the active backend through the controller registry, then drains controller-retired backends before continuing profile shutdown work.
- Controller-retired backends already undergoing asynchronous retries are allowed to finish before the final pending-only retry pass. A resource that still fails remains explicitly pending and is warned about rather than being silently discarded.
- Player departure intentionally does not destroy the server-wide crossfade manager or active music backend: those resources belong to the server playback session, not to an individual player. Existing per-player profile cleanup remains separate.
- **Static review only:** verify teardown ordering, pending-registry retention, and that the active source is stopped/retired only after crossfade cancellation. No Luau compilation, Studio test, or published-server test was performed.
- **Studio acceptance:** shut down during deck creation, decoder readiness wait, mid-fade, and immediately after commit; force deck/backend `Cleanup()` to throw and return `false`; verify retries and warnings, no new transition after manager destruction, restored outgoing gain on cancellation, no orphaned `ClubMusicCrossfadeDeck` graph, and no impact on playback in another live server. Also verify ordinary PlayerRemoving leaves that server's independent playback session intact.

### Modern-only transition and recovery dependency audit — 2026-11-17

**Scope:** Re-audited the current controller, modern backend, playback inspection adapter, client audio preferences, and installer after the crossfade-retention and shutdown-cleanup commits.

**Current dependency classification:**

- **Modern source of truth:** `activeAudioSource` remains controller-owned. The `Backend` source delegates asset, playhead, gain, playback speed, play/stop/pause/resume, readiness, and recovery to `ClubMusicAudioBackend`. Queue mutation, track clocks, and transition generations remain controller-owned and server-local.
- **Modern recovery:** replacement recovery builds a muted candidate, verifies asset/readiness/playhead/speed/playing state and gain, fences against concurrent source changes, and commits only after verification. Failed candidates are retired without replacing the selected source.
- **Restart/reload:** restart uses the normalized source snapshot and source-neutral controls. Reload is modern-backend recovery; when the guarded Sound bootstrap is active, it attempts verified modern adoption and leaves the fallback untouched if adoption fails.
- **Watchdog/diagnostics:** watchdog decisions consume normalized snapshots and playback-quality classifications. Error context follows the currently active source rather than always reporting the bootstrap Sound.
- **Crossfade:** transitions are modern-backend-only. The guarded Sound fallback is transition-free; commit/rollback, outgoing retirement, cancellation, and teardown are backend-owned.
- **Client output:** `ClubMusicPlayerPreferences.luau` creates per-listener `AudioFader -> AudioDeviceOutput` routes for modern managed backend folders. `UI_Renderer (2).lua` changes `MusicGroup.Volume` only when the replicated source-kind attribute is explicitly `Sound`.
- **Remaining legacy boundary:** the controller still creates `SoundService.ServerMusicSound` and `SoundService.MusicGroup`, initially selects the Sound source during bootstrap, supports the explicit legacy fallback/configuration path, and retains Sound branches in the normalized source adapters and playback-quality inspection for fallback operation. These are still reachable rollback/startup dependencies, not dead code.
- **Installation boundary:** the active `MusicPlaybackManager` is installed as a direct `ServerStorage` child by `ClubMusic_Studio_CommandBar_Installer.lua`; the client preferences module is installed separately. The inspected audio RBXMX bundle does not provision the playback facade. The unreferenced `ServerMusicAudioHandler.luau` remains a rollback artifact and is not installed by the current installer.

**Decision:** no legacy Sound objects, source branches, client MusicGroup compatibility, or rollback adapter were removed in this audit. Static repository inspection cannot establish that the published place has the audited installer revision or that the owner-run migration/recovery matrix passes. Removing the fallback now would risk losing the only startup recovery route if modern backend construction, readiness, or adoption fails.

**Next safe gate:** run the installed-place regression matrix and capture diagnostics showing `migrationSucceeded=true`, `backend=AudioPlayer`, and `qualityState=Playing`; verify pause/resume, restart, reload while playing and paused, forced candidate failure, watchdog recovery, repeated crossfades/cancellation, normal track advance during fallback, and two independent servers with different tracks and queues. Confirm playback continues when MemoryStoreService and MessagingService are unavailable. No playback leader, shared snapshot, or global playback sync test is applicable. Only after these pass should a separate change make startup AudioPlayer-only while retaining an explicit emergency rollback switch. Remove `ServerMusicSound`, `MusicGroup`, Sound adapter branches, and client SoundGroup compatibility in a later isolated retirement after the startup-only cutover is validated.

**Static verification:** source paths and callsites were re-inspected on branch `security/phase1-foundation`. No Luau compilation, Roblox Studio test, or published-server test was performed in this audit.

## Optional playback-only global sync — Phase 30 current architecture

**Current decision:** retain optional playback-only global sync, disabled by default. This supersedes the earlier local-only retirement note in this plan. The older full shared-queue architecture remains retired and must not be reinstalled.

- `ClubMusic_Global_Config_Service.lua` defines the shared `playbackSyncEnabled=false` default.
- `ClubMusic_Global_Service_server_1.lua` exposes the server-only status/snapshot/commit/toggle APIs and subscribes to the dedicated `Playback` MessagingService topic. The toggle requires SecurityCore `GlobalConfig` authorization (Co-Owner/Owner).
- `MusicGlobalPlaybackAuthority.lua` is the sole playback-only authority. It uses a MemoryStore fenced leader lease and a DataStore snapshot containing only the current track metadata, pause state, position, anchor time, and revision. It has no queue, playlist, request counter, DJ Control Mode, or Auto DJ refill fields.
- The same canonical module is embedded in `ClubMusic_Global_Optional_Services.rbxmx`; the embedded ModuleScript source is regenerated from and checked against the standalone source.
- `ClubMusicSecurityCore/MessageValidation.lua` already permits the `Playback` topic and its `PlaybackChanged` / `PlaybackSyncModeChanged` message kinds. Messages contain bounded envelope metadata and revision invalidations; followers fetch the durable snapshot rather than trusting client or message-supplied asset IDs.
- The controller validates every synchronized track against its own server catalog and canonical SoundId before applying it. A blocked track is stopped locally. No remote message can inject an arbitrary asset into the AudioPlayer.
- The controller owns the leader/follower behavior. Only the elected leader advances its own queue and commits privileged playback controls while sync is enabled. Followers never pop, upload, or adopt another server's queue. Each server continues to refill its own Auto DJ queue.
- The Owner/Co-Owner DJ Booth toggle is exposed through `UI_Renderer (2).lua` and `UI_Network.lua`. The server rechecks SecurityCore rank and the Global Service independently rechecks `GlobalConfig`.
- When sync is disabled, all servers resume independent local playback and queue transitions. If the authority becomes unavailable while sync is enabled, the controller fails closed against local follower advancement rather than allowing split-brain playback; the status loop retries and reconciles after recovery.
- The playback authority receives the existing bounded per-server DataStore operation-budget callback. MemoryStore is used only for the fenced playback lease, not shared rate limiting.

**Required two-server acceptance:** enable/disable from Owner/Co-Owner; same Now Playing and playhead on both servers; independent request queues and Auto DJ refill; no queue content in the global snapshot; leader departure and lease expiry; failover to a new leader; follower catalog mismatch and blocked-track behavior; DataStore/MemoryStore/MessagingService outage and recovery; sync disable returning each server to its own queue; no split-brain advances; pause/restart/skip restrictions on followers; PC/mobile/console output routing.

**Studio boundary:** global services remain isolated by default (`EnableInStudio=false`). Only enable them in a disposable, intentional multi-server Studio test copy. The published two-server acceptance matrix remains mandatory. This source restoration is not runtime certification.

## MemoryStore security/operations consumer audit (2026-11-17)

This is a source-level dependency map, not approval to remove every remaining map. The audit inspected `ClubMusic_Global_Service_server_1.lua`, `ClubMusic_Global_Security_Service.lua`, and the installed `UI_Server_Controller_server (1).lua` on `security/phase1-foundation`.

| Service / storage | Confirmed consumer or behavior | Current decision |
|---|---|---|
| SecurityMonitor — MemoryStore SortedMap | The controller's avatar/accessory validation callback invokes `RecordGlobalSecuritySignal`; the global service records that signal, tracks thresholds, and forwards threshold alerts to threat intelligence and the audit service. The controller also exposes security status and reports security signals through its global API. | **Retain for now.** It has a live telemetry caller. Separately verify whether its cross-server persisted batches are read by any staff workflow; if not, replace the storage sink with bounded local telemetry while preserving the caller and threat-intelligence handoff. |
| Audit — MemoryStore SortedMap | Global service internals record DJ/catalog events, moderation, maintenance, policy changes, authorization denials, security-monitor alerts, and incident lifecycle events. The controller's staff operations include `OperationalSecurityLog`, which reads `GetGlobalAudit`; the broader staff console also consumes the audit API. | **Retain for now.** This is an actively consumed staff-visible workflow, not dead storage. Before changing persistence, decide whether staff require cross-server/restart history or only current-server records, and add an acceptance test for the chosen retention scope. |
| IncidentResponse — MemoryStore SortedMap | The controller's staff operations read, open, resolve, and convert threat-review items into incidents through `GetGlobalSecurityIncidents`, `OpenGlobalSecurityIncident`, and `ResolveGlobalSecurityIncident`. These paths enforce the SecurityCore-backed `IncidentResponse` permission. | **Retain for now.** The staff incident workflow is live and explicitly cross-server/persisted by its current implementation. Any local-only conversion requires an explicit product decision because it changes incident visibility and durability. |
| Idempotency — MemoryStore HashMap | The global service constructs the service and exposes `ReserveGlobalOperation`; the service uses local bounded nonce tracking for local actions and only calls MemoryStore when `crossServer == true`. No direct invocation of `ReserveGlobalOperation` was found in the inspected controller or global-service source. | **Unproven consumer; do not delete yet.** Trace all installed scripts, receipt handlers, and installers for callers. If no live caller exists, remove the endpoint and module together. If a caller exists, classify whether it truly needs cross-server atomic reservation; otherwise use the bounded local path. |
| RateLimit facade — no MemoryStore map | The current constructor receives `consumeLocalBudget`, while the bundled facade currently asserts that a `consumeShared` dependency exists. The global service still exposes budget bindables and a rate-limit status surface, but no corresponding calls were found in the inspected controller. This facade is not itself a MemoryStore dependency. | **Separate cleanup candidate.** Verify external callers and fix or retire the mismatched facade/bindables as a distinct change; do not count it as a reason to retain MemoryStore. |
| SecurityPolicy / MessageValidation / Authorization | SecurityPolicy reads/writes the revisioned global configuration DataStore; MessageValidation validates MessagingService envelopes; Authorization delegates to the installed SecurityCore permission resolver and starts without any storage service. | **Not MemoryStore retirement targets.** Preserve their demonstrated global-config, message-validation, and sole-authority permission responsibilities. |

### Audit boundaries and next actions

- The three confirmed MemoryStore consumers are not interchangeable: monitoring is telemetry, audit is staff history, and incident response is an actionable staff workflow. Keep their API contracts intact until the required visibility and retention scope is decided and tested.
- The idempotency service's shared map is opt-in, not required for local reservations. Search every deployed server script, purchase receipt path, installer, and packaged bundle for `ReserveGlobalOperation` / `crossServer=true` before deciding whether to remove the shared map. Do not weaken purchase receipt idempotency.
- Trace `ConsumeActionBudget`, `ConsumeStateBudget`, `ConsumeDataStoreBudget`, `ConsumeAudioBudget`, and `ConsumeGlobalRateLimit` across installed scripts and bundles. The controller source inspected here has no direct calls to these bindables; that is not proof that no external script calls them.
- Verify the RateLimit facade dependency mismatch (`consumeShared` versus the supplied `consumeLocalBudget`) before relying on its reported health or deleting its endpoints.
- Continue to keep playback, queueing, Auto DJ, transitions, recovery, and watchdog independent of MemoryStore, DataStore, and MessagingService. The SecurityCore movement-authority ledger remains server-local, bounded, and expiring.
- No service was removed in this audit commit. The next implementation change should be limited to a consumer-proven retirement or a local-storage conversion with explicit staff/receipt acceptance tests. The remaining security architecture phases are intentionally still open and will be handled as a later, separate sequence.
