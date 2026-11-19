# ClubMusic Audio & Server-Core Installation

Branch: `phase0-33-performance-compatibility`

This document describes the current Phase 30 source layout. Use the controller, renderer, server modules, and embedded packages from the same branch snapshot.

## Architecture contract

- The modern server-owned `AudioPlayer` is the only playback source. The controller owns asset selection, playback state, playhead, queue transitions, pause/restart, reload/recovery, watchdog decisions, and crossfade commits.
- Every server owns its own request queue, playlist cursor, Auto DJ refill, request accounting, and skip votes.
- Playback and request queues are server-local in this branch. The retired playback-sync action is rejected for old clients; the current controller and global-service status report local-only playback. Do not install or enable a legacy global playback authority or shared-queue implementation.
- Client audio modules own only per-listener output routing and preferences. They cannot select assets, mutate queues, persist playlists, change server playback, or authorize DJ actions.
- Global moderation, announcements, catalog invalidation, boost controls, receipt protection, and security services remain separate from the audio controller.

## Canonical module layout

**ServerStorage / ClubMusicAudioModules**
- `ClubMusicAudioBackend`
- `ClubMusicAudioCrossfadeManager`
- `ClubMusicAudioQualityProfiles`
- `ClubMusicDJSessionManager`
- `ClubMusicSpatialAudioGraph`

**ServerStorage direct children — controller-required core**
- `MusicCatalogService`
- `MusicPlaylistService`
- `MusicQueueManager` — thin adapter over the queue service
- `MusicQueueManagerService` — bounded queue operations over the controller-owned local queue
- `MusicValidationService` — bounded audio metadata cache; no permission or cooldown authority

The audio installer provisions `MusicCoreService` and `MusicPlaylistService` as direct ServerStorage children. The matching `ClubMusic_ServerStorage_Modules.rbxmx` package contains those two canonical sources. `ClubMusic_ReceiptHash` and receipt transaction authority belong to the separate SecurityCore installation, not this two-module core installer.

**ServerStorage / ClubMusic_Global_Optional_Services**
- `ClubMusic_Global_Event_Log_Service`
- `ClubMusic_Global_RateLimit_Service`
- `ClubMusic_Global_Authorization_Service`
- `ClubMusic_Global_SafeCall_Service`
The Global Service resolves its installed optional modules recursively under ServerStorage or as direct children. This branch does not use a cross-server playback leader or shared queue. Do not install a playback-authority module from an older package snapshot.

**ReplicatedStorage / ClubMusicClientAudioModules**
- `ClubMusicPlayerPreferences`

**Compatibility / rollback sources**
- `MusicPlaybackManager.luau` is no longer required by the controller. Playback quality classification now runs in controller-local code against the modern AudioPlayer snapshot. The old adapter source and any existing live instance are retained only until live-place consumer reconciliation; the current installer does not provision it.
- `ServerMusicAudioHandler.luau`, `MusicQueueManager.luau`, `MusicValidationService.luau`, `MusicPlaylistManager.luau`, and `MusicSkipVoteManager.luau` are unreferenced rollback artifacts in the current controller path. Do not delete them until every installed script, package, and live-place consumer is checked.
- Do not install a standalone legacy Music System, a second playback controller, or a global shared-queue module.

## Runtime audio-instance placement

The server creates the shared modern playback graph under `SoundService` (managed backend folder, `AudioPlayer`, EQ, server gain fader, and server-side wires). Keep this graph server-owned.

Each client discovers the replicated server-owned graph and creates its own local `AudioFader`, `AudioDeviceOutput`, and local wires under that client's `SoundService`. Do not create one server-owned `AudioDeviceOutput` for all listeners; per-client routing preserves independent volume and mute.

The server remains authoritative for asset selection, playback commands, readiness checks, crossfade, queue, permissions, and recovery. `AudioPlayer.IsReady` is not replicated and remains a server-side readiness check.

## Recommended installation: Command Bar installer

`ClubMusic_Studio_CommandBar_Installer.lua` stages and installs:
- Five server audio support ModuleScripts in `ServerStorage/ClubMusicAudioModules`.
- Six controller-required core ModuleScripts directly under `ServerStorage`.
- One client preferences ModuleScript in `ReplicatedStorage/ClubMusicClientAudioModules`.

All eight audio/core downloads are pinned to the immutable source snapshot `6ec3766ef48f38eb2893f3385e4b4370ec0b7112`. The installer downloads five server audio support modules, two direct ServerStorage core modules, and one client preferences module. It no longer downloads or installs `MusicPlaybackManager`; existing copies are left untouched.

1. Back up the place and stop all running test servers.
2. In Studio, open **Game Settings → Security** and enable **Allow HTTP Requests**.
3. Open **View → Command Bar**.
4. Copy the complete current-branch `ClubMusic_Studio_CommandBar_Installer.lua` into the Command Bar and run it once.
5. Confirm the five audio modules, two direct ServerStorage core modules, and one client module appear under the exact names and parents above.
6. If using the RBXMX packages instead, import `ClubMusic_ServerStorage_Modules.rbxmx` under ServerStorage as a folder named `ClubMusic_ServerStorage_Modules`; the controller supports that layout. Keep the standalone files and embedded module sources byte-identical.
7. Install the current Global Service and its required optional service modules only if your place uses those non-playback global features. Do not install a cross-server playback authority or configure shared playback sync in this branch.
8. Keep `EnableInStudio = false` in normal Studio use. For an intentional two-server Studio test copy only, enable it temporarily; restore the isolation setting afterward. Published servers use the configured global service.
9. Install the matching `UI_Server_Controller_server (1).lua` and `UI_Renderer (2).lua` from this branch. Do not mix controller, renderer, global service, and module revisions.
10. Save the place before starting tests.

The installer stages all source downloads and preflights destination types before replacing same-named ModuleScripts. It does not modify the controller, renderer, global service scripts, existing legacy objects, or the optional global-service RBXMX package.

## Security Core and Phase 32 installer

Install the security stack separately with `ClubMusic_Security_Core_Installer.lua`. It installs the existing SecurityCore modules plus the four Phase 32 account-risk, chat-abuse, punishment, and composition modules into `ServerStorage.ClubMusicSecurityCore`. The installer pins the existing SecurityCore snapshot and Phase 32 snapshot independently, stages all downloads before promotion, and retains the previous module folder for rollback.

The security installer does not overwrite `UI_Server_Controller_server (1).lua`, `KohlsAdmin_ClubMusic_Addon.lua`, or `RegularCommandsSecurityServer.lua`. Install those matching branch sources into their existing Studio locations as a separate step; otherwise Phase 32 punishment commands and feature restrictions will not be active. The audio installer above remains dedicated to audio support modules and does not replace this security installation.

## Legacy compatibility and cleanup

The current controller and watchdog no longer use a legacy Sound playback fallback. The controller-local quality inspector preserves the established states: `Idle`, `SilentCatalogTrack`, `Unavailable`, `Playing`, `Paused`, `StoppedAfterLoad`, and `BufferingOrStopped`.

Do not delete existing `ServerMusicSound`, `MusicGroup`, `ServerMusicAudioHandler`, or legacy module instances solely because the current controller no longer requires them. First audit the actual live-place hierarchy, every Script/LocalScript/ModuleScript consumer, client volume compatibility, plugins, and third-party packages. Keep rollback assets until that audit and the relevant Studio tests pass.

## Phase 33 regression checks

1. Confirm modern AudioPlayer startup and readiness; no Sound fallback is selected.
2. Test pause/resume, restart, self-service `ReloadSong`, same-track recovery, watchdog stop detection, normal track advance, and crossfade cancellation/commit.
3. Test all watchdog quality states against real modern AudioPlayer states and confirm server-local diagnostics report the same classifications.
4. Run two servers with different Now Playing tracks and independently changing request queues. Confirm neither server adopts the other's playback state or queue.
5. Verify global moderation, announcements, catalog invalidation, rate limits, and other enabled non-playback global services independently; a global-service outage must not merge queues or start a legacy playback source.
7. With DJ Control Mode off, all players can submit allowed catalog requests. With it on, only the controller can submit normal requests; other players are blocked. Auto DJ refill remains active.
8. While DJ Control Mode is on, verify every player can still see Now Playing and their local queue, cast skip votes, and use self-service `ReloadSong` subject to cooldown. Unauthorized players cannot pause, restart, skip via privileged controls, or perform other restricted playback actions.
9. Verify controller departure clears DJ Control Mode and reopens normal requests.
10. Test playlist CRUD, catalog add/remove, skip voting, artwork image/decal validation, DJ session permissions, and moderation/catalog invalidation.
11. Test PC, mobile, and console with at least two clients per server; verify per-client volume and mute remain independent.
12. Repeat the critical tests in published two-server sessions. Phase 33 source compatibility is not production-certified until both Studio and published-server acceptance matrices pass.

This repository work is static source and bundle reconciliation only. It does not substitute for Roblox Studio Luau compilation, multiplayer runtime tests, live-place consumer inspection, or published two-server verification.

## Phase 33 Studio acceptance checklist

Run this checklist in a separate unpublished test place copied from the target place. Back up the place first. Keep the live place and published servers untouched until every applicable item passes.

### 1. Installation and source integrity
- [ ] Stop Play/Run simulation and enable HTTP Requests only for the installation step.
- [ ] Run the current audio Command Bar installer once. Confirm it reports 5 audio support modules, 5 direct ServerStorage core modules, and 1 ReplicatedStorage client preferences module.
- [ ] Confirm each instance has the expected class, exact name, and parent. Check that no unexpected duplicate module names exist in alternate folders.
- [ ] Install the separately versioned SecurityCore only if this place uses it. Confirm its manifest lists the intended independent SecurityCore and Phase 32 release hashes; do not replace those pins just to match the audio installer commit.
- [ ] If client diagnostics are required, run the diagnostics installer separately and confirm its module and StarterPlayerScripts bootstrap are present. Its pinned sources were checked against the current branch and match exactly.
- [ ] Install the controller, renderer, and any required Global Service scripts from the same reviewed branch snapshot. Do not mix unrelated branch revisions.
- [ ] Open every changed Script, LocalScript, and ModuleScript in Studio and confirm there are no syntax or type-analysis errors. Review Output during a clean server and client startup.

### 2. Startup, teardown, and network contracts
- [ ] Start a server with one client, then two clients. Confirm the UI bootstrap mounts once per player and cleans up after respawn/player departure without duplicate listeners or GUI instances.
- [ ] Confirm RequestAction and the GetState, GetMusicCatalog, and GetMusicPlaylists RemoteFunction contracts are present with the expected classes and return shapes.
- [ ] Exercise catalog and playlist reads while the server is shutting down or a client leaves; no stale client result should be applied after teardown.
- [ ] Confirm rate limits reject excess requests without blocking normal controls; verify unauthorized staff actions remain denied after any yielding moderation or DataStore operation.

### 3. Modern audio and queue regression
- [ ] Confirm the controller creates and owns the modern AudioPlayer graph. No Sound-based fallback becomes the active track source when modern startup or recovery fails.
- [ ] Test initial asset load, decoder readiness, play, pause/resume, restart, seek/reload, track end, normal advance, and unavailable/invalid assets.
- [ ] Test crossfade start, successful commit, cancellation, rapid next/previous requests, source replacement, and cleanup of outgoing/incoming graphs.
- [ ] Force a recoverable playback failure and confirm replacement AudioPlayer recovery preserves the intended track, playhead, pause state, and gain. Confirm unrecoverable failure remains unavailable rather than starting legacy playback.
- [ ] Test watchdog classifications and recovery after stopped, buffering, silent, and unavailable states. Confirm diagnostics remain server-local.
- [ ] Test requests, queue ordering, skip votes, DJ Control Mode, Auto DJ refill, playlists, catalog add/remove, and DJ session ownership. Confirm queues and Now Playing are independent between servers.

### 4. Profile, purchase, and security acceptance
- [ ] Test profile load, save, leave/rejoin, rapid rejoin from another server, concurrent save attempts, and shutdown with pending saves. Confirm active session locks are not released after an unconfirmed save.
- [ ] Simulate DataStore budget exhaustion and transient failures in a controlled test environment. Confirm retries are bounded and stale sessions cannot overwrite a newer owner.
- [ ] Test each applicable developer product and game pass with Roblox test purchase flows. Confirm ProcessReceipt is idempotent, grants once, and recovers from interrupted profile persistence.
- [ ] Test title filtering, moderation restrictions, staff authorization, teleport/spectator features, and account-risk/chat-abuse handling where installed.

### 5. UI, device, and published-server acceptance
- [ ] Test at least two clients on desktop and mobile, plus console if supported. Check independent local volume/mute, GUI scaling, input focus, safe areas, joystick/jump controls, and inventory overlap. Do not change mobile layout while fixing desktop-only issues.
- [ ] Confirm utility-bar and full-menu visibility rules during inventory and tab transitions; verify no duplicate menus or flicker during respawn and repeated open/close cycles.
- [ ] Repeat the critical playback, queue, permission, purchase, and profile tests in published two-server sessions with the intended DataStore, MemoryStore, MessagingService, and HTTP settings.
- [ ] Inspect the actual target-place hierarchy and search all scripts/packages/plugins for legacy Sound, MusicGroup, old controller, and old module consumers before removing any rollback assets.
- [ ] Record device, place version, test account roles, test results, Output errors, and unresolved failures. Only promote after all release-blocking checks pass and a rollback copy is verified.

Passing source review or Studio single-server tests alone is not production certification. Published two-server, purchase, persistence, and device acceptance remain required.
