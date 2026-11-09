# ClubMusic Music Catalog Foundation

Branch: `audit/hardened-clubmusic-2026-11-08`

## What was added

- `MusicCatalogService.lua`: server-owned, metadata-only catalog ModuleScript.
- Existing 42 built-in sample tracks were moved out of the controller into the catalog service without changing their stable IDs, titles, artists, genres, or durations.
- The controller builds its trusted `TRACK_BY_ID` lookup from the service. `RequestTrack` still validates against that server-owned lookup and continues through the existing VIP priority, queue limits, moderation, cooldown, and playback paths.
- A server-owned `GetMusicCatalog` RemoteFunction provides bounded title/artist/genre search and pagination (maximum 50 entries per page).
- `UI_Network.GetMusicCatalog(query, genreId, offset, limit)` exposes that read-only catalog API to the existing client architecture.

## Installation

1. Create a **ModuleScript** named `MusicCatalogService` under `ServerStorage`.
2. Paste the complete contents of `MusicCatalogService.lua` from this repository into it.
3. Keep the existing `UI_Server_Controller` Script in `ServerScriptService`; it now requires the catalog module.
4. Keep `UI_Network` in `ReplicatedStorage`. The controller creates `GetMusicCatalog` inside the existing `ClubMusicRemotes` folder at runtime.
5. No new LocalScript, legacy remote, role module, DataStore, or queue manager is required for this foundation.

## Adding songs

Edit the `CATALOG` array in `MusicCatalogService.lua`. Each entry requires:

- `id`: stable, unique internal ID (letters, digits, hyphens, underscores; max 24 characters).
- `genreId`: one of the declared genre IDs.
- `title`: non-empty display title (maximum 100 characters).
- `artist`: display artist (maximum 100 characters).
- `duration`: positive duration in seconds, maximum 3,600.
- `genre`: display genre label.

Do not change an existing ID after players have favorited it or it has been queued. The catalog validates duplicate IDs, genre references, and metadata at module load.

**Audio asset IDs are intentionally separate from catalog metadata.** The current `SoundIds` configuration in the controller remains the mapping from stable track IDs to approved `rbxassetid://...` values. The current repository's sample catalog does not include verified playable audio IDs, so those entries can appear in search/catalog results without producing audible playback until configured. Creator Hub audio ID requests remain staff-only and retain their existing inspection/allowlist controls.

## API

`MusicCatalogService:GetTrackById(trackId)` returns a detached track record or nil.

`MusicCatalogService:GetAllTracks()` returns detached records sorted by title.

`MusicCatalogService:GetGenres()` returns detached genre records.

`MusicCatalogService:GetCatalog(query, genreId, offset, limit)` returns:

- `schemaVersion`
- `items`
- `total`
- `offset` (zero-based)
- `limit` (clamped to 1–50)
- `hasMore`

The network API is `UI_Network.GetMusicCatalog(query, genreId, offset, limit)`. Search matches title, artist, and genre. An invalid genre returns nil. Queries are capped at 48 characters and pages at 50 records.

## Security and architecture boundaries

- The catalog is in `ServerStorage`; clients cannot require or mutate the canonical module.
- The catalog RemoteFunction returns metadata only. It cannot request a song, modify the queue, or grant permissions.
- The server applies a per-player 0.75-second catalog query cooldown and the existing local/shared state-query budgets.
- The server still ignores client-supplied title, artist, duration, genre, and audio ID for normal catalog requests. It accepts only a known stable `trackId`.
- VIP/VVIP/Tiki Tide Sultan request priority and request limits remain in `UI_Server_Controller`.
- Playback, current-track state, staff controls, and cross-server commands remain owned by the existing controller/global service.
- The old `Music Module` file remains as an untouched legacy source; it is not a second runtime authority.
- The old `Music Storage Handle` remains an optional Sound-instance cache source, not the song catalog. It is not loaded by this foundation because its ReplicatedStorage Sound cache and loading lifecycle need separate review before production use.

## Current scope / not yet implemented

- The Audio ID tab now includes a staff-only genre selector and **SAVE TO CATALOG** action after asset lookup. The server still performs its own audio inspection; client lookup is only a convenience.
- Catalog add/remove network actions are available. The Audio ID tab currently exposes adding; a dedicated custom-entry removal list is still a follow-up UI task.
- The All Tracks renderer still uses its built-in local display list; dynamic custom entries are returned by the catalog API but are not yet merged into that tab.
- No playlist manager, automatic rotation rules, favorites migration, or five child manager modules have been introduced.
- No live Roblox Studio, multiplayer, audio-permission, or exploit-client test was run as part of this repository change.


## Persistent staff-managed catalog storage (next stage)

The catalog service now supports a bounded persistent overlay stored separately
from player profiles in DataStore `ClubMusic_Catalog_v1`, key `custom_tracks`.

### Staff operations

- `CatalogAddAudio`: staff supplies an audio asset ID and a genre ID. The server checks staff permission, optional audio allowlist, rate limits, audio type, and actual server-side loadability/duration before saving. The server derives the title and creator from Marketplace metadata; client-supplied title/artist/duration are never accepted.
- `CatalogRemoveTrack`: staff can remove only custom catalog entries. A track cannot be removed while it is currently playing or still queued.
- Custom tracks use stable IDs `custom-<assetId>`, carry their approved `rbxassetid://` sound ID, and become eligible for normal catalog requests and automatic selection after successful save.
- Storage is capped at 200 custom entries. DataStore `UpdateAsync` performs atomic add/remove operations. Failed writes do not update the server's in-memory catalog.
- Storage loads at server startup through the existing shared DataStore budget gate. If loading fails, built-in songs remain available, but custom catalog mutation is disabled for that server to avoid overwriting unknown persisted state.
- Studio remains session-only when `StudioUseDataStore=false`; set it true only when Studio API access and intentional live-store testing are configured.

### Network API

`UI_Network.CatalogAddAudio(assetId, genreId)` and
`UI_Network.CatalogRemoveTrack(trackId)` are available. Server-side staff checks
remain authoritative; client wrappers are not security boundaries.

### Important limits

- This stage persists approved catalog metadata and asset IDs. It does not create a new catalog editor screen; a staff-facing add/remove UI can be connected to the existing Audio ID and All Tracks tabs in a separate renderer change.
- DataStore writes use the shared budget gate and atomic `UpdateAsync`. Roblox Studio/live DataStore behavior still requires a controlled runtime test.


## Current persistent catalog stage

- Persistent store: `ClubMusic_Catalog_v1`, key `custom_tracks`, maximum 200 custom entries.
- The catalog loads at controller startup after passing the existing shared DataStore budget gate.
- `CatalogAddAudio` is available in the staff Audio ID tab. It stores only after server-side staff authorization, optional allowlist enforcement, Marketplace audio-type inspection, and server-side Sound loadability/duration inspection.
- `CatalogRemoveTrack` is available through `UI_Network.CatalogRemoveTrack(trackId)`; only custom entries may be removed, and current/queued tracks are protected.
- Built-in tracks remain code-defined. Custom tracks are persisted independently from player profile data and are merged into server-side track lookup, automatic selection, and catalog search.
- A successful write is immediately reflected in the current server. Other already-running servers load the persisted change on their next restart; cross-server live catalog invalidation is not implemented yet.
- If catalog loading fails at startup, built-in playback remains available and persistent catalog mutation fails closed for that server. Failed writes never mutate the in-memory catalog.


## Catalog browsing UI integration

The All Tracks tab now reads the server-owned catalog through
`UI_Network.GetMusicCatalog` rather than relying only on its original local
sample list.

- Displays built-in and persisted custom tracks returned by the server.
- Search is performed against the canonical server catalog (title, artist,
  genre), with a short client debounce.
- Genre chips are sent as server-side filters.
- Results are paginated in pages of 30; the UI does not request the entire
  catalog at once.
- Custom entries are identified with a CUSTOM badge.

- Staff see a two-step REMOVE / CONFIRM? control on custom catalog entries in
  All Tracks. The existing server-side removal action still checks staff
  authorization, persistence availability, and whether the track is currently
  playing or queued; the client confirmation is only a usability safeguard.
- After a removal request, the renderer refreshes the current catalog page.
  A rejected removal remains visible in the catalog and the server notification
  explains the restriction.

- Catalog results are validated before they are rendered and merged into the
  renderer's track index so existing favorite/request presentation can use
  stable catalog IDs.
- Requests still go through the existing `RequestTrack` server action.
  Browsing never queues a song and does not grant permissions.

The server catalog read remains read-only and retains the controller's existing
per-player cooldown and shared state-query budget. This change does not alter
DataStore persistence, the queue, VIP priority, moderation, or playback.

### Verification status

- GitHub writes completed on the working branch and the changed renderer was
  fetched again for verification.
- No Roblox Studio execution, Luau typecheck, live DataStore test, multiplayer
  session, or exploit-client test has been performed. Validate catalog search,
  genre filtering, page navigation, custom-track display, and ordinary song
  requests in a private Studio test before release.


## Cross-server catalog synchronization

The persistent custom catalog now broadcasts invalidation events after successful
staff additions and removals.

- The global service publishes a small, versioned
  `ClubMusic_Global_Catalog_v1` MessagingService message. It contains no
  user-supplied track metadata; the message only signals that the durable
  catalog may have changed.
- Other running servers validate the message envelope, ignore their own
  echoes, deduplicate message IDs, and refresh the custom catalog from
  `ClubMusic_Catalog_v1`.
- Refresh uses the existing shared DataStore budget gate. A failed refresh
  leaves the last known-good in-memory catalog untouched.
- Each server rebuilds its trusted track lookup and catalog index after a
  successful refresh. Existing queue entries and the current track retain
  their already-copied playback data; removed entries are no longer available
  for new requests or automatic selection.
- MessagingService delivery is best-effort, so servers also perform a
  jittered, low-frequency reconciliation (about every 3–3.5 minutes) to repair
  missed invalidations.
- If the global service is disabled or MessagingService is unavailable, the
  originating server still keeps its successfully saved local change. Other
  servers converge through periodic reconciliation or restart; this is not a
  durable event queue or an instantaneous consistency guarantee.

### Verification status for this stage

The service, controller, and global-service files were committed and fetched
again from the working branch. No Roblox Studio multiplayer session,
MessagingService delivery test, live DataStore test, Luau typecheck, or
exploit-client test has been run. Validate add/remove propagation with at
least two live test servers and confirm behavior during MessagingService
outage and DataStore budget exhaustion before release.


## Persistent staff playlist management

The next catalog stage adds `MusicPlaylistService.lua`, a server-only
ModuleScript installed at `ServerStorage/MusicPlaylistService`.

### What it supports

- Staff can create and delete named playlists from the All Tracks screen.
- Staff can select a playlist and add catalog tracks to it.
- Playlist service operations also support removing a track and moving a track
  to a requested position.
- Playlist names are 2–32 characters; names are unique without regard to case.
- Limits: 30 playlists, 100 tracks per playlist, and no duplicate track IDs
  within a playlist.
- Playlists are stored separately from player profiles and catalog entries in
  DataStore `ClubMusic_Playlists_v1`, key `playlists`.
- Mutations use `UpdateAsync` and update the in-memory copy only after the
  persistent update succeeds. Concurrent edits are applied against the latest
  stored list.
- Studio uses session-only playlists while `StudioUseDataStore=false`.
- The client receives a detached, read-only playlist list. All mutations pass
  through the existing action RemoteEvent and server-side staff authorization.
- The All Tracks tab now provides staff playlist creation, selection, deletion,
  and an ADD control on catalog entries when a playlist is selected.
- Selecting a playlist displays its tracks with REMOVE, move-up, and move-down controls.

### API and architecture

- `MusicPlaylistService:Create(name)`
- `MusicPlaylistService:Delete(playlistId)`
- `MusicPlaylistService:AddTrack(playlistId, trackId)`
- `MusicPlaylistService:RemoveTrack(playlistId, trackId)`
- `MusicPlaylistService:MoveTrack(playlistId, trackId, position)`
- `MusicPlaylistService:GetAll()`
- `UI_Network.GetMusicPlaylists()` provides a bounded read-only remote call.
- `UI_Network.PlaylistCreate/Delete/AddTrack/RemoveTrack/MoveTrack` send
  mutation requests through the existing network layer.

The controller verifies that added track IDs exist in its current trusted
catalog. Playlist data is metadata only: this stage does not automatically
start playlists, modify the active queue, bypass VIP request priority, or
grant DJ privileges. Playlist playback/rotation remains a separate future
feature and must be explicitly connected to the controller's existing
playback lifecycle.

### Installation

1. Create a **ModuleScript** named `MusicPlaylistService` under
   `ServerStorage`.
2. Paste the complete contents of `MusicPlaylistService.lua` from this branch.
3. Keep the existing `MusicCatalogService` ModuleScript in ServerStorage.
4. Keep the updated controller, network module, and renderer in their existing
   locations. The controller creates `GetMusicPlaylists` under
   `ClubMusicRemotes` at runtime.
5. Do not install the original source system's separate remotes or role system.

### Current boundaries and verification

- Playlist reads refresh the persistent store on a bounded interval (at most
  once per five seconds per server when clients request the list), so changes
  made on another server converge without trusting client-supplied playlist
  data. This is not instant MessagingService synchronization.
- Playlist mutations fail closed if initialization or DataStore writes fail.
- Deleting a catalog track does not currently cascade-delete its ID from
  playlists; stale IDs are harmless metadata and are not playable/requestable
  through the controller unless the track exists in the trusted catalog.
- This repository change has been committed and fetched again for source
  verification. No Roblox Studio execution, Luau typecheck, live DataStore
  concurrency test, or exploit-client test has been performed. Test creation,
  selection, adding/removing/reordering, deletion, DataStore outage, and
  concurrent edits in a private test experience before release.


## Playlist playback rotation and startup recovery

### Playlist playback

Staff can now press **PLAY** on a saved playlist. The controller:
- Validates staff permission and the playlist ID on the server.
- Resolves each playlist track against the current trusted catalog; stale or
  removed catalog IDs are skipped.
- Leaves the currently playing track untouched and fills the automatic queue
  with the selected playlist in its saved order.
- Repeats the playlist from its first track after the last track.
- Keeps player requests ahead of playlist/automatic entries, preserving the
  existing guest/VIP/VVIP/Tiki Tide Sultan request priority rules.
- Refreshes queued playlist entries after staff edits the active playlist.
- Stops playlist rotation if the active playlist is deleted or has no valid
  tracks. **STOP** returns automatic queue filling to the normal Auto DJ.
- Does not make playlist playback a staff permission grant; only staff can
  start or stop rotation.

Playlist rotation is per server in this stage. It is not synchronized across
all live servers, and the playlist does not interrupt the current track. Global
DJ command synchronization continues to follow the existing best-effort
MessagingService behavior.

### Remote startup race correction

The previous client startup expected `ReplicatedStorage.ClubMusicRemotes`
within a single 30-second wait and aborted the bootstrap after one failed
initialization. This could fail when the server controller had not published
its remotes yet, or if the controller was blocked loading its required storage
modules.

The controller now creates the remote folder and all remote instances before
loading the catalog/playlist modules, sets the folder attribute `Ready=false`,
and changes it to `Ready=true` only after the server handlers are connected.
The client network waits for this readiness marker, uses short bounded waits,
and throttles repeated startup warnings. The bootstrap retries initialization
up to 20 times with three-second spacing before reporting a final actionable
error instead of exiting on the first race.

If the folder never becomes ready, verify all of these exact placements:
- `ServerScriptService/UI_Server_Controller` — enabled Script using the
  updated controller source.
- `ServerStorage/MusicCatalogService` — ModuleScript containing
  `MusicCatalogService.lua`.
- `ServerStorage/MusicPlaylistService` — ModuleScript containing
  `MusicPlaylistService.lua`.
- `ServerStorage/ClubMusic_ReceiptHash` — ModuleScript required by the
  controller.
- `ReplicatedStorage/UI_Network` — updated ModuleScript.
- `ReplicatedStorage/UI_Renderer` — updated ModuleScript.
- `StarterPlayer/StarterPlayerScripts/ClubMusicBootstrap` — updated LocalScript.

Do not manually create a second `ClubMusicRemotes` folder. The controller
creates and owns that folder and its remote instances.

### Verification boundary

Source changes were committed and fetched again. No Roblox Studio runtime,
server/client startup race, playlist DataStore test, live multiplayer playback,
or Luau typecheck was executed here. Test with the exact installation above:
start the client before/after the server controller, temporarily delay a
required ModuleScript, play/stop a playlist, finish the current track, enqueue
player requests at each tier, edit/delete the active playlist, and verify
normal Auto DJ resumes after STOP.


## Startup readiness and playback watchdog hardening

The client now allows up to 45 seconds for the server-owned readiness
marker, rather than treating a three-second cold-start delay as a failed
controller. The network waits up to 20 seconds for the server-created remote folder and
up to 45 seconds for its readiness marker. The bootstrap makes two bounded
initialization attempts instead of repeating a long readiness wait indefinitely. The network module reports the
server's startup stage and any published startup error when the deadline
expires; the bootstrap includes that diagnostic in its final startup message.
The controller publishes bounded stages while loading its storage modules,
loading the receipt-hash dependency, initializing persistent storage, building
the controller, and binding the remotes. Required ModuleScript lookups and
requires now have bounded waits and publish actionable failure details. It
still marks `Ready=true` only after the server action handler is connected.

The playback clock now has a bounded recovery watchdog. It advances at the
configured track duration as before, but also recovers when a loaded Sound has
stopped unexpectedly, or when an asset never finishes loading within the
45-second ceiling. Paused playback is excluded. Track transitions are guarded
by a generation check and a synchronous transition lock, so the duration
clock and watchdog cannot both advance the same track. This does not guarantee
that Roblox audio permissions or asset availability are valid; it provides
server-side recovery when playback cannot proceed.

No Roblox Studio runtime, multi-client, real audio asset, or Luau typecheck was
run for this change. Test a valid audio asset, an unavailable/private asset,
a paused track, normal completion, manual skip, and playlist rotation.
