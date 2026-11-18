# ClubMusic Audio & Server-Core Installation

Branch: `fix/security-core-release-and-queue-loop`

This document describes the current Phase 30 source layout. Use the controller, renderer, server modules, and embedded packages from the same branch snapshot.

## Architecture contract

- The modern server-owned `AudioPlayer` is the only playback source. The controller owns asset selection, playback state, playhead, queue transitions, pause/restart, reload/recovery, watchdog decisions, and crossfade commits.
- Every server owns its own request queue, playlist cursor, Auto DJ refill, request accounting, and skip votes.
- Optional global playback sync is disabled by default. When explicitly enabled by an Owner/Co-Owner through the SecurityCore-backed global setting, a fenced server leader shares only Now Playing metadata, pause state, and a time-anchored playhead. No queue, playlist, request count, or Auto DJ state is shared.
- If global sync is disabled, each server plays independently. Do not install a global shared-queue service or the standalone legacy Music System.
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
- `ClubMusic_ReceiptHash`
- `MusicQueueManager` — thin adapter over the shared queue service
- `MusicQueueManagerService` — canonical bounded queue operations over the controller-owned queue
- `MusicValidationService` — canonical bounded audio metadata cache; no permission or cooldown authority

The controller resolves these six modules either as direct ServerStorage children or inside the `ServerStorage.ClubMusic_ServerStorage_Modules` folder. The matching `ClubMusic_ServerStorage_Modules.rbxmx` package contains the same six canonical standalone sources.

**ServerStorage / ClubMusic_Global_Optional_Services**
- `ClubMusic_Global_Event_Log_Service`
- `ClubMusic_Global_RateLimit_Service`
- `ClubMusic_Global_Authorization_Service`
- `ClubMusic_Global_SafeCall_Service`
- `MusicGlobalPlaybackAuthority` — optional playback-only leader lease and snapshot authority; no queue implementation

The Global Service resolves optional modules recursively under ServerStorage or as direct children. The matching `ClubMusic_Global_Optional_Services.rbxmx` bundle contains the canonical `MusicGlobalPlaybackAuthority.lua` source.

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

The audio modules are pinned to package snapshot `f47410ac9a9674d3df0b24eb1714b31d1a4ef816`; the six core modules are pinned to `4857fd9c5b763a2a685b37bccf812a6f85425524`. The installer no longer downloads or installs `MusicPlaybackManager`; existing copies are left untouched.

1. Back up the place and stop all running test servers.
2. In Studio, open **Game Settings → Security** and enable **Allow HTTP Requests**.
3. Open **View → Command Bar**.
4. Copy the complete current-branch `ClubMusic_Studio_CommandBar_Installer.lua` into the Command Bar and run it once.
5. Confirm the five audio modules, six direct ServerStorage core modules, and one client module appear under the exact names and parents above.
6. If using the RBXMX packages instead, import `ClubMusic_ServerStorage_Modules.rbxmx` under ServerStorage as a folder named `ClubMusic_ServerStorage_Modules`; the controller supports that layout. Keep the standalone files and embedded module sources byte-identical.
7. For optional cross-server playback sync, import `ClubMusic_Global_Optional_Services.rbxmx` under ServerStorage as `ClubMusic_Global_Optional_Services`, and install the matching `ClubMusic_Global_Service_server_1.lua` and `ClubMusic_Global_Config_Service.lua`. The global setting `playbackSyncEnabled` defaults to false.
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

## Phase 30 regression checks

1. Confirm modern AudioPlayer startup and readiness; no Sound fallback is selected.
2. Test pause/resume, restart, self-service `ReloadSong`, same-track recovery, watchdog stop detection, normal track advance, and crossfade cancellation/commit.
3. Test all watchdog quality states against real modern AudioPlayer states and confirm server-local diagnostics report the same classifications.
4. With global sync disabled, run two servers with different Now Playing tracks and independently changing request queues.
5. Enable optional playback-only sync as Owner/Co-Owner. Confirm both servers show the same Now Playing/playhead while each queue remains independent and Auto DJ refill continues locally.
6. Test leader departure, lease expiry, failover, temporary DataStore/MemoryStore/MessagingService outages, recovery, and disabling sync. No server may upload or adopt another server's queue.
7. With DJ Control Mode off, all players can submit allowed catalog requests. With it on, only the controller can submit normal requests; other players are blocked. Auto DJ refill remains active.
8. While DJ Control Mode is on, verify every player can still see Now Playing and their local queue, cast skip votes, and use self-service `ReloadSong` subject to cooldown. Unauthorized players cannot pause, restart, skip via privileged controls, or perform other restricted playback actions.
9. Verify controller departure clears DJ Control Mode and reopens normal requests.
10. Test playlist CRUD, catalog add/remove, skip voting, artwork image/decal validation, DJ session permissions, and moderation/catalog invalidation.
11. Test PC, mobile, and console with at least two clients per server; verify per-client volume and mute remain independent.
12. Repeat the critical tests in published two-server sessions. Phase 30 is not certified until both Studio and published-server acceptance matrices pass.

This repository work is static source and bundle reconciliation only. It does not substitute for Roblox Studio Luau compilation, multiplayer runtime tests, live-place consumer inspection, or published two-server verification.
