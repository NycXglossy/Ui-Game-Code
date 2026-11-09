# ClubMusic Profile and Storage Compatibility Audit

Date: 2026-11-09  
Target branch: `audit/hardened-clubmusic-2026-11-08`

## Scope

Source-reviewed the current `UI_Server_Controller_server (1).lua`, `MusicCatalogService.lua`, and `MusicPlaylistService.lua`. This is a compatibility audit only: no DataStore names, keys, profile fields, or stored records were changed.

## Confirmed storage contracts

| Area | DataStore | Key | Stored shape / notes |
|---|---|---|---|
| Player profiles | `SunsetStageClubProfiles_v1` | `tostring(player.UserId)` | Profile fields plus session lock and receipt compatibility fields |
| Custom music catalog | `ClubMusic_Catalog_v1` | `custom_tracks` | `{schemaVersion, tracks = {...}}`; up to 200 custom tracks |
| Staff playlists | `ClubMusic_Playlists_v1` | `playlists` | `{schemaVersion = 1, playlists = {...}}`; up to 30 playlists and 100 track IDs each |
| Durable receipt journal | Separate receipt-journal implementation in controller | Must retain its existing sharded keys | Not modified by this audit |

## Player profile findings

- The profile DataStore name remains `SunsetStageClubProfiles_v1`; user records are keyed by the decimal UserId string.
- Loading acquires/renews a session lock with `UpdateAsync`. If another unexpired server owns the profile, the load fails closed rather than loading defaults.
- A failed load leaves the profile unavailable and explicitly refuses to save defaults.
- The existing profile fields include XP, tickets, coins, login streak/reward state, tags, play time, title unlock version, title slots, unlocked/active slot, title visibility, glowsticks, skip tokens, neon trail, favorites, and XP.
- The loader supports legacy `customTitle`, `titleColor`, and `titleStyle` migration only when no valid new-format title slot exists. It re-filters legacy title text before replication.
- The one-time `titleTagUnlocksVersion` migration is retained.
- Saves use `UpdateAsync` and require the current session-lock owner. The save snapshot intentionally preserves `receiptIds` and `pendingReceipt`, and the receipt journal remains a separate durability boundary.
- Important compatibility risk: the profile save writes a new snapshot rather than merging arbitrary unknown legacy fields. Any older profile field not explicitly loaded and included in the current snapshot can be dropped on the next successful save. Before adding profile fields or retiring old ones, inspect historical profile versions and explicitly preserve or migrate required fields.

## Studio behavior

- `StudioUseDataStore = false` keeps player profiles in memory and skips profile DataStore reads/writes.
- Catalog and playlist services also use session-only mode in Studio unless explicitly passed `studioUseDataStore = true`.
- Therefore, edits made during ordinary Studio tests are not durable after the server session ends. This is expected behavior, not a persistence failure.
- Do not enable Studio access to live DataStores merely to make test changes persist. Use a dedicated test universe/store or a controlled test account and backup plan.

## Custom catalog findings

- Existing store/key: `ClubMusic_Catalog_v1/custom_tracks`.
- The reader accepts a table with a `tracks` array and sanitizes entries; custom tracks are bounded to 200.
- Add writes `schemaVersion = 2`; remove writes `schemaVersion = 1`. The current reader does not branch on the version field, so this mismatch is presently tolerated, but it should be normalized in a future catalog-only refinement after checking all deployed writers.
- Custom track IDs are derived as `custom-` plus the audio asset ID. Built-in track IDs are protected from custom collisions.
- Catalog refresh replaces the in-memory custom overlay only after a successful read; the write/refresh lock prevents stale refreshes racing mutations.

## Playlist findings

- Existing store/key: `ClubMusic_Playlists_v1/playlists`.
- The persisted envelope uses `schemaVersion = 1` and a `playlists` array.
- Each playlist stores `id`, `name`, `trackIds`, `createdAt`, and `updatedAt`.
- Limits are 30 playlists, 100 track IDs per playlist, and 32 characters per name. Mutations use `UpdateAsync`; refresh is serialized against mutations.
- Playlist storage does not own playback or the live queue. Playlist IDs reference catalog track IDs, so catalog removals can leave stale references unless the playlist read/selection path filters them against the current catalog. Verify this before enabling more playlist automation.

## Safe next changes

1. Preserve all three existing DataStore names and keys.
2. Add a documented profile schema/version only with a backward-compatible reader and an explicit field-preservation policy.
3. Normalize the catalog schema version in a dedicated change, preserving the existing `tracks` array and unknown fields where safe.
4. Validate playlist track references against the authoritative catalog when presenting or selecting tracks; do not silently delete stored references during read.
5. Add regression fixtures for legacy title fields, sparse title slots, favorites with removed catalog IDs, receipt compatibility fields, older profile fields, and stale playlist track IDs.
6. Test persistence only in an isolated test environment before any live DataStore migration.

## Verification status

- Source-level inspection: complete for the three files listed above.
- DataStore contents / historical production records: not inspected.
- Migration execution: not performed.
- Roblox Studio multiplayer, live DataStore, and receipt regression tests: not run.

No data migration or live storage write was performed by this audit.
