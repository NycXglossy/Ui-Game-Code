# ClubMusic Phase 0 — Manager Integration Audit

**Branch:** `audit/hardened-clubmusic-2026-11-08`  
**Audit date:** 2026-11-09  
**Scope:** Repository source inspection only. No Roblox Studio runtime or live-service tests were performed.

## Result

**Phase 0 is not complete.** The controller currently owns several music responsibilities directly, while the five manager modules named in the future-additions roadmap are not present in the repository source search. Their APIs and implementations cannot be safely integrated or reviewed without the actual module files.

## Repository evidence

### Existing server-side service modules

`UI_Server_Controller_server (1).lua` waits for and requires:

- `ServerStorage.MusicCatalogService`
- `ServerStorage.MusicPlaylistService`

The controller calls their initialization and catalog/playlist APIs. These are distinct from the five proposed child managers.

### Responsibilities currently owned by the controller

The controller directly declares and mutates:

- Queue entries and queue state (`QueueEntry`, `queue`, `requestCounts`, queue insertion/removal and priority handling).
- Current playback state (`nowPlaying`, `playbackPaused`, `musicSound`, track advancement and playback recovery).
- Skip voting (`skipVotes`, `checkSkipVotes`, `skipStatus`, `VoteSkip` handling).
- Playlist rotation state (`activePlaylistId`, `activePlaylistTracks`, `activePlaylistCursor`) while delegating persistent playlist definitions to `MusicPlaylistService`.
- Request authorization, cooldowns, VIP tier priority, staff permissions, moderation and remote action dispatch.

The controller also owns the existing remote contract and bridges global operations through its existing global API integration. These responsibilities must not be duplicated by new modules.

## Five-manager source availability

The repository code search returned no matching source files for:

| Expected module | Source found | Audit status |
|---|---:|---|
| `MusicQueueManager` | No | Cannot inspect API or behavior |
| `MusicPlaybackManager` | No | Cannot inspect API or behavior |
| `MusicValidationService` | No | Cannot inspect API or behavior |
| `MusicSkipVoteManager` | No | Cannot inspect API or behavior |
| `MusicPlaylistManager` | No | Cannot inspect API or behavior |

This is a source-availability finding, not proof that the modules do not exist in an unpublished Roblox place or another asset.

## Integration decisions

Until the original five module sources are available:

1. Keep `UI_Server_Controller` as the sole permission and action authority.
2. Keep the existing queue, playback, and skip-vote state owned by the controller; do not create parallel managers that also mutate those states.
3. Keep `MusicCatalogService` and `MusicPlaylistService` as the only currently verified service-module dependencies from this audit.
4. Do not add remotes, DataStores, role authorities, receipt journals, or competing global playback/queue state.
5. Do not replace the existing LocalScripts or change the current remote payload contract.
6. Do not claim that the five-manager integration is complete.

## Required inputs to finish Phase 0

Provide the actual source for all five modules, preferably as their original `.lua` files, plus any ModuleScripts they require. If they exist only inside a Roblox model or place file, provide that source/export. The audit can then compare public APIs, dependencies, state ownership, event connections, yields, cleanup, and behavior against the current controller before making a minimal compatibility-preserving integration.

## Phase 0 exit criteria

- [ ] All five original module sources inspected.
- [ ] Dependencies and public APIs documented.
- [ ] State ownership mapped with no duplicate authoritative state.
- [ ] Existing controller permission checks remain authoritative.
- [ ] Duplicate event connections and mutation paths removed or disabled, if present.
- [ ] Initialization, shutdown, cleanup, and failure behavior documented.
- [ ] Existing UI actions and remote contracts have regression coverage.

## Verification boundary

This audit is based on the repository files and code-search results available on the audit date. It does not verify Roblox Studio behavior, live DataStore access, Marketplace receipts, MessagingService delivery, or exploit-client resistance.
