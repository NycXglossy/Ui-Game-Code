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

Pause, resume, and restart are recorded in the existing global-control DataStore under a revisioned `playbackControl` record before MessagingService notification. Pause state and the latest restart are retained as separate revisions, so a later pause does not erase a restart that another server missed. Each receiving controller applies only revisions newer than its last applied revision, in revision order. A low-frequency reconciliation loop reads the durable record immediately and then approximately every 30–40 seconds. The originating controller records the returned revision to avoid replaying its own restart during reconciliation.

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

## Global queue migration — backend foundation (2026-11-09)

The global queue backend has been added as a separate atomic state service:

- `MusicGlobalQueueService.lua` — place as a **ModuleScript** at
  `ServerStorage/MusicGlobalQueueService`.
- `ClubMusic_Global_Service_server_1.lua` requires that module and exposes
  server-only BindableFunction operations through `ServerStorage.ClubMusicGlobalAPI`:
  `GetGlobalQueueState`, `EnqueueGlobalQueueEntry`, `RemoveGlobalQueueEntry`,
  `ClearGlobalQueue`, `AdvanceGlobalQueue`, `SetGlobalPlayback`, and
  `GetGlobalPlaybackPosition`.
- Shared state is stored under `ClubMusic_GlobalQueue_v1/globalState`.
  Queue mutations and compare-and-swap track transitions use DataStore
  `UpdateAsync`; MessagingService is only a notification path, never the
  source of truth.
- Entries are normalized and bounded server-side. The service caps the global
  queue at 80 entries, validates audio IDs, metadata, duration, source, role
  tier, and requester identity, and rejects duplicate track IDs.
- Playback state stores a shared server-time anchor, pause state, position,
  and track revision. A stale server cannot advance a newer track revision.

**Important rollout status:** this is the backend/API foundation, not the
completed live global-queue migration. The controller still has local queue
mutation and playback paths that must be routed through these APIs before
servers share one queue/current track. Do not publish this as a completed
global-sync feature yet. The next integration stage must migrate request
insertion, auto/playlist top-up, queue reorder/removal/clear, moderation
purges, DJ skip, automatic end/watchdog transitions, pause/resume/restart,
and late-join reconciliation together. Until that stage is complete, the
existing local queue remains active and the new global queue store is not
authoritative for live playback.

**Required installation:** copy the new ModuleScript into ServerStorage under
the exact name above. The global service will fail startup if it is missing.
Enable DataStore and MessagingService access for the published experience.
Studio cross-server tests require intentionally enabling
`EnableInStudio` in the global service configuration; keep it disabled for
ordinary isolated Studio sessions.


## Studio log diagnosis and safe testing

The following startup messages are expected with the checked-in defaults:

- `Studio in-memory profile mode is active`: the controller has `StudioUseDataStore = false`. Player profiles are held in memory for that Studio server and are discarded when the session ends. This is intentionally separate from global music configuration.
- `Cross-server service initialized. Enabled=false`: the global service has `Enabled = true` but `EnableInStudio = false`; its effective enabled state is false whenever `RunService:IsStudio()` is true. This prevents Studio from accidentally sharing production moderation, budget, playback-control, and queue DataStores.
- The `Playback changed on this server, but cross-server sync is unavailable` and `Track restarted here, but cross-server sync is unavailable` notices are the expected consequence of the global service being disabled. They do not indicate that the local controller failed.

For an intentional Studio persistence test, enable Studio API access in the experience settings and review the two independent settings before changing either one. `StudioUseDataStore = true` makes profile data use the configured profile DataStore; `EnableInStudio = true` enables the global service and its shared stores. Do not enable either against production data just to silence a log. Prefer a separate test universe / isolated test DataStore names, and keep both defaults for ordinary Studio playtests.

The Kohl's Admin Explorer `Unable to cast string to Array` and Building Tools nil `WaitForChild` stack traces in the reported output originate in Kohl's Admin model scripts, not ClubMusic. The JellyBuild loaded messages are informational. Diagnose/update those packages independently; changing ClubMusic does not repair them.

**Global queue completion status remains partial:** the queue service and bridge APIs exist, but `UI_Server_Controller` still uses its local queue/playback flow. The bridge's queue API guard/topic cleanup does not itself migrate request insertion, playlist/Auto DJ scheduling, queue moderation, transitions, or late-join playback. Cross-server queue and exact timeline synchronization must not be advertised as active until those controller paths are migrated and tested in a multi-server live test.
