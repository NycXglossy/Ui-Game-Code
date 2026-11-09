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
| Server audio | Controller-owned `SoundService.ServerMusicSound` in `SoundGroup.ClubMusic` | `ServerMusicAudioHandler` is not loaded; it creates a competing `MusicGroup` and assumes legacy playback ownership. |
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
- **Do not import** the legacy `Music Group.rbxm` or legacy RemoteEvent models. The controller creates and owns `SoundService.ClubMusic` and the `ReplicatedStorage.ClubMusicRemotes` contract.
- **Do not import** `Audio Sound Count 1.rbxm`. It is excluded; the controller creates `ServerMusicSound` itself when needed.

These legacy source files can remain in the repository for reference. Their presence in the repository does not mean they should be inserted into the live Roblox hierarchy.

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
