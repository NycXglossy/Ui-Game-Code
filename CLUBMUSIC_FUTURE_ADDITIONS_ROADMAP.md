# ClubMusic Future Additions Roadmap

**Status:** Planning document — proposed work only; none of the items below should be treated as implemented merely because they appear here.  
**Target branch:** `audit/hardened-clubmusic-2026-11-08`

This roadmap records potential additions for the existing ClubMusic architecture. It is intentionally designed to preserve the current LocalScripts, remote contract, server authority, profile and receipt systems, moderation, titles, XP, and cross-server service.

## Architecture rules for every future addition

1. `UI_Server_Controller` remains the authority for player permissions, request eligibility, cooldowns, queue mutations, and privileged music actions.
2. Existing LocalScripts remain the client presentation and input layer. They communicate through `UI_Network` and the existing remotes; they never require server-only modules.
3. The five music managers are supporting server-side components, not independent authorities. They must have clearly defined ownership of their state and APIs.
4. `ClubMusic_Global_Service` remains the cross-server coordination boundary. MessagingService delivery is best-effort; do not treat it as a durable global queue or guaranteed command log.
5. Do not introduce duplicate remotes, role systems, profile stores, receipt journals, or competing copies of the current track/queue/pause/vote state.
6. Keep secrets and privileged modules server-only. Validate every client-originated request and every cross-server message at the receiving server.
7. Preserve existing behavior unless a deliberate, documented migration is approved. Add tests for backward compatibility.
8. Do not add an audio-count feature based on `Audio Sound Count 1.rbxm`: that asset is a Sound instance named `ServerMusicSound`, not a counter script or module.

## Phase 0 — Complete the manager integration

**Priority: Critical · Prerequisite for later music features**

- [ ] Obtain and inspect the actual source for all five child manager modules:
  - `MusicQueueManager`
  - `MusicPlaybackManager`
  - `MusicValidationService`
  - `MusicSkipVoteManager`
  - `MusicPlaylistManager`
- [ ] Inspect their dependencies, public APIs, state ownership, event connections, yields, and cleanup behavior.
- [ ] Compare their behavior with the original `Music System`, `Music Module`, `Music Role System`, and `Music Storage Handle` scripts.
- [ ] Adapt useful behavior into the existing controller/network/global-service architecture.
- [ ] Retain original LocalScripts and UI callbacks; update them only where a compatible UI feature or state field is required.
- [ ] Keep the existing controller as permission authority; do not import the source system's independent role authority.
- [ ] Define one authoritative owner for current track, playback state, queue, and skip-vote state.
- [ ] Remove or disable duplicate legacy event connections and duplicate state mutation paths.
- [ ] Document module initialization order, shutdown/cleanup, and failure behavior.

**Exit criteria:** source-level integration review passes; no duplicate remote system or permission authority; existing UI actions and music behavior have regression coverage.

## Phase 1 — Security, reliability, and regression testing

**Priority: Critical · Complete before production release**

- [ ] Build a regression matrix for all existing features: requests, queue operations, DJ controls, skip voting, moderation, VIP tiers, titles, XP, purchases, and profile persistence.
- [ ] Test simultaneous requests and simultaneous staff actions for race conditions.
- [ ] Test request flooding, malformed payloads, replayed actions, unauthorized actions, and invalid audio IDs.
- [ ] Verify server-side enforcement of request slots, cooldowns, tier priority, and staff permissions.
- [ ] Test player departure during a queued request or active vote; clean up stale user references.
- [ ] Test unavailable, moderated, deleted, private, or non-loadable audio and define safe fallback behavior.
- [ ] Add bounded retries and timeouts where appropriate; avoid infinite retry loops.
- [ ] Ensure playback failure cannot leave the system permanently stuck in a loading/playing state.
- [ ] Test server shutdown, restart, and player reconnect behavior.
- [ ] Test MessagingService delivery failure, duplicate messages, stale messages, and out-of-order commands.
- [ ] Add structured server-side diagnostics for queue, playback, validation, and global-command failures without logging sensitive data.
- [ ] Run multi-client Studio tests and controlled live-service tests for DataStore, Marketplace receipts, and MessagingService.
- [ ] Record which tests are automated, manually tested, or not yet run.

**Exit criteria:** no known critical security or state-consistency defect; documented test results; runtime testing completed in a controlled environment. Source review alone is not runtime verification.

## Phase 2 — Music configuration and operational controls

**Priority: High**

- [ ] Add a server-only `MusicConfiguration` ModuleScript for queue limits, tier priorities, cooldowns, vote thresholds, retry limits, default volume, playlist options, and optional audio allowlist policy.
- [ ] Validate configuration values at startup and fail safely on invalid settings.
- [ ] Keep authoritative values server-side; replicate only non-sensitive display settings needed by the UI.
- [ ] Add staff-configurable master music volume with server-side bounds and clear separation from per-client listening volume.
- [ ] Add configurable queue capacity and duplicate-request policy.
- [ ] Add configurable skip-vote thresholds, vote duration, eligibility, and cooldowns.
- [ ] Add an explicit policy for whether each server has independent playback or participates in a synchronized global session.

**Exit criteria:** settings are centralized, validated, documented, and do not bypass server-side enforcement.

## Phase 3 — Advanced DJ and staff tools

**Priority: High**

- [ ] Add individual queued-track removal with permission checks.
- [ ] Add queue reordering and promote/demote controls with permission checks.
- [ ] Add clear-queue confirmation and an audit record.
- [ ] Add DJ session status and clear feedback for successful, rejected, or unavailable actions.
- [ ] Add staff announcements with length limits, cooldowns, and moderation safeguards.
- [ ] Consider temporary DJ permissions with explicit issuer, target, expiration, and revocation rules.
- [ ] Add a bounded recently-played history.
- [ ] Add staff action history for skip, pause, resume, restart, clear, remove, reorder, and volume changes.
- [ ] Ensure staff controls remain hidden or disabled in the UI as appropriate, while server checks remain authoritative.

**Exit criteria:** each staff operation has a server permission check, rate limit, state transition, user feedback, and audit policy.

## Phase 4 — Player-facing music experience

**Priority: Medium**

- [ ] Add a searchable, curated music catalog with title, artist, genre, and category metadata where available.
- [ ] Add genre/category filters and pagination or bounded result sizes.
- [ ] Add player favorites using the existing profile system only after checking current profile schema and save behavior.
- [ ] Add recently played tracks and requester attribution, with privacy-conscious display rules.
- [ ] Improve the Now Playing display with current track, requester, elapsed time, and queue position.
- [ ] Add queue position feedback and clear request status.
- [ ] Improve skip-vote UI with eligible-voter count, vote progress, remaining time, and result.
- [ ] Add accessible loading, empty, error, and unavailable-audio states.
- [ ] Keep UI state derived from server snapshots/events rather than trusting client-side predictions.

**Exit criteria:** new UI features use existing LocalScripts and network contracts safely and do not create client-authoritative state.

## Phase 5 — Playlist and playback intelligence

**Priority: Medium**

- [ ] Add curated playlist definitions and validate every track before it can be selected.
- [ ] Add weighted or round-robin rotation with configurable repeat avoidance.
- [ ] Add genre or event-based playlist selection if supported by the experience.
- [ ] Define behavior when the request queue is empty.
- [ ] Define behavior when all playlist entries fail validation or playback.
- [x] Add bounded playback watchdog checks for stalled or unexpectedly stopped tracks.
- [x] Add track-transition safeguards to prevent double advancement.
- [ ] Keep automatic playlist playback distinct from player-request priority and staff-only Creator Hub audio policy.

**Exit criteria:** playlist rotation is deterministic enough to debug, bounded, and cannot bypass audio validation or staff restrictions.

## Phase 6 — Cross-server coordination and recovery

**Priority: Medium · Depends on an explicit playback topology decision**

- [ ] Decide and document whether music is per-server or globally synchronized. Do not imply synchronized playback if servers only receive best-effort DJ commands.
- [ ] Add message schema versions, strict payload validation, sender identity checks, and bounded payload sizes.
- [ ] Add command IDs or idempotency keys to reject duplicate global actions.
- [ ] Add sequence/version checks to reject stale or out-of-order state changes where applicable.
- [ ] Add reconciliation for missed notifications using an appropriate durable source, with shared DataStore budget controls.
- [ ] Define recovery behavior when MessagingService or DataStore is unavailable.
- [ ] Add server status/health reporting for diagnostics.
- [ ] Ensure local-origin message echoes cannot apply the same command twice.
- [ ] Keep global moderation fail-closed behavior and existing persistence protections intact.

**Exit criteria:** documented delivery guarantees and tested recovery behavior; no false claim of durable or globally synchronized playback.

## Phase 7 — Analytics and observability

**Priority: Medium to Low**

- [ ] Track bounded aggregate counts such as tracks played, requests accepted/rejected, playback failures, and queue activity.
- [ ] Track most-requested tracks only if catalog identity is stable and data collection is appropriate.
- [ ] Add playback failure rates and recovery outcomes.
- [ ] Add DJ action counts and moderation audit summaries with access controls.
- [ ] Add operational metrics for queue length, playback state, retry counts, and global-message failures.
- [ ] Use bounded retention and aggregation; avoid unbounded DataStore keys or per-event writes.
- [ ] Avoid collecting unnecessary player behavior or exposing private player data.

**Exit criteria:** metrics are bounded, access-controlled, and do not create a new persistence bottleneck.

## Optional supporting modules

Create these only if inspection shows the responsibility is not already covered by an existing script or one of the five managers:

| Candidate | Responsibility | Guardrail |
|---|---|---|
| `MusicConfiguration` | Validated server-side settings | No client authority |
| `MusicAuditLogger` | DJ/moderation action records | Bounded writes and access |
| `MusicRecoveryService` | Coordinates playback recovery | Must not own a competing playback state |
| `MusicAnalyticsService` | Aggregated usage and reliability metrics | Bounded storage and privacy |
| `MusicCatalogService` | Catalog search and metadata | Must use approved/validated audio entries |

These are optional candidates, not a requirement to create five more modules.

## Release gates

Before production release, verify:

- [ ] All existing original UI and LocalScripts still initialize and function.
- [ ] Existing remote names and payload contracts remain compatible or have a documented migration.
- [ ] Server-side authorization is enforced for every privileged operation.
- [ ] VIP/VVIP/Tiki Tide Sultan priority, slots, and cooldowns match the configured policy.
- [ ] Current playback is not interrupted by a new request.
- [ ] Playback pause/restart/skip and automatic advancement behave correctly.
- [ ] Moderation, title, XP, and receipt systems pass regression tests.
- [ ] Profile save/lease and receipt recovery paths are tested.
- [ ] Cross-server failure behavior is documented and tested.
- [ ] No duplicate remotes, role authorities, DataStores, or state owners were introduced.
- [ ] Live configuration IDs and audio permissions are reviewed before publishing.

## Current known limitations to carry forward

- The five manager module source files were not present in the repository tree at the time this roadmap was written; their actual implementations and APIs remain unverified.
- The supplied `Music Module` currently has an empty music list.
- The source system's separate role system should not become a second permission authority.
- The global DJ MessagingService path is best-effort, not a durable globally synchronized playback queue.
- The `Audio Sound Count 1.rbxm` asset is a Sound named `ServerMusicSound`, not an audio counter implementation.
- The existing integration documentation reports source-level review only; Roblox Studio multiplayer, live DataStore, Marketplace, MessagingService, and exploit-client tests remain necessary.

## Suggested implementation order

1. Complete and review the five-manager integration.
2. Complete security, compatibility, and runtime regression testing.
3. Add centralized music configuration and playback recovery.
4. Add advanced DJ/staff controls and audit logging.
5. Add player catalog, favorites, and Now Playing improvements.
6. Add playlist intelligence.
7. Decide and implement any stronger cross-server synchronization guarantees.
8. Add bounded analytics and operational dashboards.

Do not implement every item at once. Each phase should be reviewed, tested, and committed independently on the working branch before proceeding.
