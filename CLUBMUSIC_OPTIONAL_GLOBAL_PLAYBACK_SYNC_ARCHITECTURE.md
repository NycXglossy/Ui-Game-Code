> **RETIRED — superseded on 2026-11-15.** Cross-server playback synchronization and global queue authority were removed by design. Do not use this document as an installation or implementation guide. Each game server now owns its own playback state and queue. See [CLUBMUSIC_AUDIO_STUDIO_INSTALLATION.md](CLUBMUSIC_AUDIO_STUDIO_INSTALLATION.md) for the current architecture and Studio installation instructions.

# ClubMusic Optional Cross-Server Playback Sync

## Agreed behavior

Cross-server playback synchronization is an optional mode, separate from the local request queues.

When enabled, every participating public server follows one authoritative playback stream:
- current track and track metadata;
- shared playback position and transition timing;
- pause and resume;
- restart and skip;
- DJ playback controls and track changes.

Each server retains an independent local queue:
- player requests and request limits;
- queue order, removals, and queue display;
- per-server queue permissions and moderation decisions;
- local playlist/Auto DJ selection state.

A single elected playback leader supplies the next track from its own local queue while global playback sync is enabled. Other servers follow the leader's committed track and never import or mutate the leader's queue. If the leader disappears, a replacement leader is elected and continues from its own server-local queue. When sync is disabled, each server continues its own local playback and queue.

## Existing implementation constraint

The current `MusicGlobalQueueService` stores `queue`, `current`, `playback`, playlist rotation, and recent-track history in one atomic DataStore record. The controller's `globalQueueMode` also replaces its local queue mirror with that shared queue. Therefore, enabling or disabling the existing global queue is not sufficient to meet the behavior above.

The current global queue mode must remain unchanged until the new playback-only authority is integrated and regression-tested. Do not repurpose `MusicGlobalQueueService` or simply stop syncing its queue field: its enqueue, advance, crossfade compare-and-swap, catalog reservation, and queue snapshot flows currently depend on that shared record.

## Implementation progress

### Phase 1: playback-only authority foundation

Implemented on the feature branch:
- Added `MusicGlobalPlaybackAuthority.lua` with a dedicated playback-only DataStore snapshot and a MemoryStore expiring leader lease.
- Snapshot schema contains current track metadata, pause state, position, anchor time, playback revision, and leader identity only; it has no queue, request, rotation, or playlist fields.
- Added revision compare-and-swap commits and leader lease acquisition/renewal/release.
- Added shared config key `playbackSyncEnabled`, defaulting to `false`.
- Added service bridge APIs for status, snapshot reads, leadership, playback commits, and an authorized opt-in toggle.
- Added a separate MessagingService topic and strict envelope validation for playback invalidations.
- Packaged the new ModuleScript in `ClubMusic_Global_Optional_Services.rbxmx`.
- Preserved the existing global queue APIs and their current behavior.

This is the authority/service foundation only. The main UI controller has not yet been switched to consume this snapshot, and no server currently uses it to drive audio. Do not enable the setting yet. Controller integration, leader-owned local-queue advancement, UI controls, and multi-server runtime validation remain outstanding.
 
## Required implementation phases

1. **Playback authority service**
   - Add a distinct durable playback snapshot that contains no queue or playlist data.
   - Add a short-lived MemoryStore leader lease with expiry, renewal, fencing token, and safe takeover.
   - Accept playback mutations only from the current lease holder and reject stale fencing tokens/revisions.
   - Publish playback-only invalidation messages; DataStore remains the authoritative recovery path.

2. **Controller separation**
   - Keep the existing local `queue` and `queueManager` authoritative on every server.
   - Replace global queue snapshot application in the new mode with playback-only snapshot application.
   - Only the elected leader may consume its local queue to select and commit the next shared track.
   - Route skip/end-of-track transitions to the leader without sharing queue mutations.
   - Keep the existing global-queue mode available as a compatibility mode during migration.

3. **Optional setting and UI**
   - Expose a separately authorized global-playback-sync setting.
   - Turning sync off must stop the leader lease and restore each server's local playback without deleting local queues.
   - Turning sync on must elect a leader, publish its current track, and align peers before shared controls become active.
   - Display mode and leader status in operational diagnostics.

4. **Installation and validation**
   - Update the Studio installer/package with the new module(s).
   - Validate leader startup, lease expiry/takeover, stale-leader fencing, missed-message reconciliation, pause/resume/restart/skip, track-end transitions, crossfade, local queue isolation, mode toggling, and fallback when DataStore or MessagingService is unavailable.
   - Do not enable the new mode by default until multi-server Studio/live test results are confirmed.

## Safety invariants

- No local queue entry is written to the shared playback store.
- A non-leader server never advances the shared track.
- A stale leader cannot commit after lease takeover.
- Queue requests and edits remain server-local in both modes.
- If the shared playback authority is unavailable, do not silently split a currently synchronized session into competing tracks; surface degraded status and use an explicitly defined recovery/fallback path.
- Existing global queue behavior remains intact until the playback-only path passes validation.


## Phase 2 implementation progress — controller integration

The controller now has a separate `globalPlaybackSyncState`; it does not set or reuse `globalQueueMode`.

Implemented:
- The controller observes the optional sync setting and the service-owned elected-leader status.
- The leader commits only current-track metadata, pause state, position, and server-time anchor to the playback-only snapshot.
- Followers apply playback snapshots and seek/play/pause their local audio source to match.
- Only the elected leader may advance the track, and it advances from its own server-local queue.
- Skip, pause/resume, and restart requests from non-leader servers are authorized by the existing global DJ permission check and forwarded as playback-only command events.
- Playback-only command events are validated on the Playback topic and are handled only by the elected leader.
- These commands use a validated Playback-topic command envelope and bypass the legacy durable `playbackControl` record, preventing old periodic reconciliation from replaying stale restart/pause commands.
- Queue clear, DJ request-lock mode, and player request moderation remain server-local while playback-only sync is active; no local queue data or queue-control decisions are broadcast.
- Legacy global-queue mode and its queue APIs remain unchanged; legacy playback-control reconciliation is ignored while playback-only sync is active.
- The controller observes the service's lease status instead of creating duplicate MemoryStore lease writes. The controller reconciliation loop runs every eight seconds; MessagingService events provide faster invalidation.

Phase 3 implementation progress — staff setting and status UI

Implemented on the feature branch:
- Added an Owner/Co-Owner-only Cross-Server Playback section in the existing ClubMusic DJ Booth staff controls.
- The control calls the dedicated `SetGlobalPlaybackSyncEnabled` service API; the service independently re-checks `GlobalConfig` authorization.
- The UI shows enabled/disabled state, whether this server is the elected leader or a follower, authority readiness/error, and the local-queue isolation behavior.
- Controller state snapshots include playback-sync status; the controller broadcasts state when the observed role/readiness changes.
- The toggle does not alter `globalQueueMode` or any queue/request data. The setting remains default-off.

Phase 4 implementation progress — durable leader fencing

Implemented on the feature branch:
- Each new leadership term claims a monotonically increasing `leaderGeneration` in the same DataStore record used for playback snapshots.
- The claim updates the durable leader token/job and increments the snapshot revision atomically.
- Playback commits require the snapshot's generation, leader token, and leader job to match the committing server; a prior leader cannot overwrite a newer fenced term after the new claim is committed.
- Normal lease renewal verifies the existing durable fence instead of incrementing the generation on every renewal.
- A new leader does not report ready until its durable fence is claimed and the MemoryStore lease is rechecked.

Phase 5 implementation progress — service recovery

Implemented:
- Playback reconciliation is protected by a pcall boundary so one failed config/authority call does not terminate the background loop.
- Failures are surfaced through playback status and warnings.
- The loop backs off to 30 seconds during repeated failures and returns to the normal eight-second cadence after recovery.
- Shutdown attempts a guarded lease release; if that fails, the lease expires naturally.
- Authority readiness and leader role remain false when the durable fence cannot be verified.

Phase 6 implementation progress — multi-server validation preparation

Added a dedicated published-server test plan covering:
- two/three server leader election and follower status;
- follower-originated skip, pause/resume, restart, and track transition;
- independent local request queues and local moderation/request-lock behavior;
- forced leader shutdown and takeover;
- stale leader commit rejection after a new generation is claimed;
- temporary MemoryStore/DataStore failure and recovery;
- sync disable/re-enable and Studio isolation.

Still required before production:
- Run the published multi-server test plan in a dedicated test universe with API services enabled.
- Record actual results and resolve any runtime-specific failures.
- Keep `playbackSyncEnabled=false` until those tests pass.

This work is code integration and test preparation only. No Roblox Studio or published multi-server runtime tests have been executed by this update.
