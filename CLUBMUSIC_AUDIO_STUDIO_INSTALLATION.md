# ClubMusic Audio Module Installation

Branch: `feature/sultan-settings-2026-11-10`

Audited source snapshot: `8edd537a30f002e39bd437a6d77f74e5ce66c2c6`

## Architecture contract

- Playback, queue order, Auto DJ selection, skip/pause/restart, and crossfade timing are owned by each individual game server.
- A server's queue and playback state are not copied to, reconciled with, or controlled by another server.
- The modern server AudioPlayer is the controller-owned main playback source.
- Client volume is per-listener output routing; it must not change another player's volume or server queue state.
- Global services are reserved for shared features that genuinely need cross-server delivery, such as moderation updates, announcements, catalog invalidation, and global boost controls. They are not playback or queue authorities.
- Do not install or recreate `MusicGlobalQueueService`, `MusicGlobalPlaybackAuthority`, `ClubMusic_Global_Recovery_Service`, or `ClubMusic_Global_State_Reconciliation_Service`. Those retired modules are not dependencies of the local playback design.

## Module package

The current audio package contains six ModuleScripts:

**ServerStorage / ClubMusicAudioModules**
- `ClubMusicAudioBackend`
- `ClubMusicAudioCrossfadeManager`
- `ClubMusicAudioQualityProfiles`
- `ClubMusicDJSessionManager`
- `ClubMusicSpatialAudioGraph`

**ReplicatedStorage / ClubMusicClientAudioModules**
- `ClubMusicPlayerPreferences`

Keep server-only modules in ServerStorage. Only the client preferences/routing module belongs in ReplicatedStorage.

## Recommended installation: Command Bar installer

The repository's `ClubMusic_Studio_CommandBar_Installer.lua` is pinned to the same audited source snapshot for all six modules. Prefer it over older locally saved copies of the RBXMX packages, which may contain an earlier module revision.

1. Make a backup copy of the place and stop all running test servers.
2. In Studio, open **Game Settings → Security** and enable **Allow HTTP Requests**.
3. Open **View → Command Bar**.
4. Open the installer file from this branch, copy its entire contents, paste it into the Command Bar, and run it once.
5. Confirm that the two folders and all six ModuleScripts appear under the exact parents and names listed above.
6. Install the matching `UI_Server_Controller_server (1).lua` and `UI_Renderer (2).lua` from this same branch snapshot. Do not mix controller, renderer, and module revisions from different snapshots.
7. Save the place before starting the test session.

The installer stages all six downloads before creating or replacing ModuleScripts. It only replaces same-named ModuleScripts inside its two dedicated folders and stops if a conflicting non-ModuleScript object is present. It does not modify the controller, renderer, legacy compatibility objects, or global services.

## Legacy compatibility

Keep any existing `ServerMusicSound` or `MusicGroup` objects until the current controller/client volume path has been validated in Studio. Do not remove compatibility objects merely because the modern AudioPlayer is the main source. Their removal is a separate cleanup after playback, recovery, and per-player volume regression tests pass.

## Studio regression checks

Run these in a stopped-place copy with at least two clients:

1. Confirm the server starts with the modern AudioPlayer as its main source.
2. Confirm each server maintains an independent queue and Auto DJ progression.
3. Change volume and mute on client A; verify client B's volume is unchanged.
4. Trigger a crossfade and verify both clients hear a clean transition.
5. Exercise local pause, resume, skip, restart, and queue edits.
6. Exercise modern audio reload/recovery and verify playback resumes without duplicating or advancing the queue.
7. Confirm global moderation, announcements, catalog invalidation, and boost controls still work independently of local playback.

This repository audit and installer update are static checks only. They do not substitute for Roblox Studio multiplayer testing or a published-server test.
