# ClubMusic Legacy Music Model Integration

Updated: 2026-11-09

## Integration decision

The original music-system models are integrated **at the behavior and responsibility level**, not installed as a second running music system. The secured ClubMusic controller already implements the compatible features and remains the single server authority.

The original standalone `Music System` is **not** a runtime dependency. It creates a separate `MusicRemotes` folder and expects a different controller, role system, module hierarchy, and event contract. Running it beside ClubMusic would create competing queues, playback state, permissions, and client transports.

## Runtime ownership

| Responsibility | Active implementation | Legacy model disposition |
|---|---|---|
| Catalog and custom audio metadata | `ServerStorage/MusicCatalogService` | `Music Module` is reference-only; its current `MusicList` is empty/commented out. |
| Persistent playlists | `ServerStorage/MusicPlaylistService` | Legacy `MusicPlaylistManager` is not loaded; its static playlist source is incompatible with the persistent playlist service. |
| Queue, per-player limits, VIP/VVIP/Sultan priority | `UI_Server_Controller` | `MusicQueueManager` is reference-only; do not create a second queue. |
| Playback clock, pause, restart, track transitions | `UI_Server_Controller` | `MusicPlaybackManager` is reference-only; it broadcasts through legacy remotes that do not exist in the secured transport. |
| Server audio | Controller-owned `SoundService.ServerMusicSound` routed through the supplied `SoundService.MusicGroup` | `ServerMusicAudioHandler` is not loaded; the controller directly owns playback and does not create a competing handler. |
| Audio ID inspection and request validation | Controller validation, rate limits, and protected MarketplaceService inspection | `MusicValidationService` is reference-only; it dynamically requires a separate `RoleSystem` and uses a different configuration contract. |
| Skip voting | Controller-owned skip vote state and handlers | `MusicSkipVoteManager` is reference-only; its current implementation has an ineffective stale-timer comparison and does not enforce voter eligibility in `CastVote`. |
| Role and permission checks | Existing controller VIP/VVIP/Sultan/staff/group/pass logic | `Music Role System` must not be installed as a second authority. |
| Cross-server moderation and DJ actions | Existing `ClubMusic_Global_Service` bridge | No legacy global dispatcher or remote set is added. |

## Original models: install or do not install

- **Do not install** the standalone `Music System` Script.
- **Do not install** the legacy `MusicQueueManager`, `MusicPlaybackManager`, `MusicValidationService`, `MusicSkipVoteManager`, or `MusicPlaylistManager` as active children of a running music system. Their responsibilities are already owned by the secured controller and persistent services.
- **Do not install** the legacy `Music Role System`; it would create a second role hierarchy and permission source.
- **Do not install** the legacy `Music Storage Handle`. It caches Sound instances under `ReplicatedStorage.MusicStorage`, which is not the private server-side metadata store used by this architecture.
- **Do not install** the legacy `Music Module` as a second catalog source. Its current list is empty, and the authoritative catalog is `MusicCatalogService`.
- **Use the supplied** `Music Group.rbxm` instance as `SoundService.MusicGroup`. The controller now reuses it as the canonical SoundGroup; the UI renderer's volume slider targets this exact group.
- **Use the supplied** `Audio Sound Count 1.rbxm` instance as `SoundService.ServerMusicSound`. It is a Sound instance, not a counter script. The controller reuses it for playback and marks it with `ManagedByClubMusicController = true`.
- The controller publishes `SoundService.ActiveMusicSoundCount` (0 or 1) to represent whether its single managed playback Sound is currently playing. This is not a count of client-local audio previews.
- If an older `SoundService.ClubMusic` SoundGroup exists, the controller migrates SoundService sounds routed through it to `MusicGroup` and removes the obsolete group. The remote contract remains `ReplicatedStorage.ClubMusicRemotes`.

These legacy source files can remain in the repository for reference. Their presence in the repository does not mean they should be inserted into the live Roblox hierarchy.

## Cross-server playback controls

Pause, resume, and restart are now recorded in the existing global-control DataStore under a revisioned `playbackControl` record before the MessagingService notification is sent. Each receiving controller applies only revisions newer than its last applied revision. A low-frequency reconciliation loop re-reads the durable record so servers recover missed notifications; a restart revision is treated as a one-shot action per server. The originating controller records the returned revision to avoid replaying its own restart during reconciliation.

MessagingService remains the fast path; durable reconciliation is the recovery path. Restart means restart each server's locally current track at position zero. It does **not** synchronize queue contents, track identity, or exact playback position across servers. Pause/resume applies to each server's own current track. New local tracks preserve the current global paused state.

The earlier request-lock persistence bug is also corrected: its DataStore write remains exclusively in the `SetRequestLock` branch.

## SoundService model integration

Place both supplied instances directly under `SoundService`:

- `MusicGroup` — a `SoundGroup` used by `ServerMusicSound` and by the UI's local volume slider.
- `ServerMusicSound` — the one server-owned `Sound` used for all authoritative music playback.

The controller reuses these instances by exact name and class. It assigns `ServerMusicSound.SoundGroup = MusicGroup`, configures the playback properties, and never creates a parallel playback Sound when the supplied instance is present. The renderer updates `MusicGroup.Volume` locally for the player's own volume preference; it does not send a volume command to the server or change other players' volume.

The controller exposes `SoundService.ActiveMusicSoundCount` as a replicated attribute: `1` while the managed server music Sound is playing, otherwise `0`. The original Audio Sound Count model does not implement counting by itself. Local audio previews are client-owned and intentionally excluded from this server playback count.

## Roblox Studio placement

Keep the existing secured layout:

1. `ServerScriptService/UI_Server_Controller` — use `UI_Server_Controller_server (1).lua`.
2. `ServerStorage/MusicCatalogService` — ModuleScript from `MusicCatalogService.lua`.
3. `ServerStorage/MusicPlaylistService` — ModuleScript from `MusicPlaylistService.lua`.
4. `ServerStorage/ClubMusic_ReceiptHash` — existing receipt module.
5. `ServerScriptService/ClubMusic_Global_Service` — existing separate cross-server service and its configured bridge.
6. `ReplicatedStorage/UI_Network` and `ReplicatedStorage/UI_Renderer` — retain the existing secured UI modules.
7. `StarterPlayer/StarterPlayerScripts/ClubMusicBootstrap` — retain the existing LocalScript.

Do not create `ReplicatedStorage.MusicRemotes`, `DispatchAction`, `DispatchEvent`, `MusicBroadcast`, `MusicUpdate`, or `RequestSync`.

## Storage recovery and concurrency hardening

The integration now includes these storage safeguards:

- Catalog initialization remains retryable after a transient DataStore-budget or `GetAsync` failure. The controller retries catalog and playlist initialization with bounded delays before marking persistent management unavailable.
- Catalog refresh and writes share one operation lock. A refresh cannot overwrite a newer successful local catalog mutation with a stale read.
- Playlist refresh and mutations share one operation lock. A stale playlist read cannot replace the in-memory list after a successful mutation.
- Failed refreshes preserve the last known-good in-memory data.
- Built-in catalog tracks remain readable when custom persistent storage is unavailable; playlist management and custom catalog writes remain fail-closed when their storage is not ready.

## Required configuration

Populate `CONFIG.SoundIds` in the controller with approved audio asset IDs keyed by catalog track ID, for example:

```lua
SoundIds = {
    ["edm-0"] = "rbxassetid://YOUR_APPROVED_AUDIO_ID",
    ["pop-0"] = "rbxassetid://YOUR_APPROVED_AUDIO_ID",
},
```

The checked-in map is empty by default. Configure existing group/pass/staff IDs and ensure every audio asset is permitted for the experience before publishing.

## Verification status

The changes were source-reviewed against the repository. They have **not** been executed in Roblox Studio or tested against live DataStore, MarketplaceService, MessagingService, or multi-server sessions. Run a private multiplayer Studio test before publishing: verify catalog and playlist startup/retry, add/remove catalog tracks, create/edit/delete playlists, request priority, queue removal, skip voting, pause/resume/restart, automatic advancement, moderation, and player join/leave cleanup.
