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
