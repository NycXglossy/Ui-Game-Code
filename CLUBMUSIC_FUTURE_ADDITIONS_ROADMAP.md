# ClubMusic Future Additions Roadmap

**Status:** Living implementation roadmap — updated 2026-11-09. Checkboxes distinguish implemented source changes from work that still requires runtime verification. A checked item is not a production-release certification.  
**Target branch:** `audit/hardened-clubmusic-2026-11-08`

This roadmap records potential additions for the existing ClubMusic architecture. It is intentionally designed to preserve the current LocalScripts, remote contract, server authority, profile and receipt systems, moderation, titles, XP, and cross-server service.

## Current implementation snapshot (2026-11-09)

This section supersedes older status wording elsewhere in this document where the repository has since changed. Status is based on committed source changes and source review, not an independent Roblox runtime test.

| Area | Current status | Evidence / remaining caveat |
|---|---|---|
| Queue manager | **Integrated** | `MusicQueueManager` is adapted to the controller-owned queue; preserve a single queue authority. |
| Other four managers | **Not integrated** | Playback, validation, skip-vote, and playlist managers still require compatibility work; do not activate legacy state owners blindly. |
| Catalog | **Implemented, evolving** | `MusicCatalogService` exists; schema consistency, playlist refresh, and catalog-removal protections have received refinements. |
| HUD | **Refined** | Festival-style HUD and live playing/paused/standby status are implemented in source; device-layout testing remains. |
| Genre/catalog UI | **Partially implemented** | Genre filtering includes `Other`; verify search, pagination, empty states, and full device behavior. |
| Textface/title customization | **Implemented in source** | The expanded font-style choices and server validation exist; continue permission and UI regression checks. |
| Security | **Improved, not release-verified** | Remote validation order, bounded payload checks, action budgets, and player-leave cleanup are present. Exploit testing remains. |
| Global queue | **Partially hardened** | Shared queue integration and stale-revision protections exist; catalog deletion still has a snapshot-check concurrency gap. |
| Playlist watchdog/transitions | **Implemented in source** | Bounded watchdog and double-advance safeguards are present; runtime recovery tests remain. |
| Persistence and cross-server delivery | **Not fully verified** | Studio memory mode does not prove live DataStore, MessagingService, or receipt behavior. |

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

**Current status: Partial — `MusicQueueManager` is integrated; the other four managers remain compatibility work.**

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

**Current status: In progress — multiple source-level hardening changes are committed; runtime and adversarial test evidence is still outstanding.**

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

**Current status: Not started as a centralized configuration phase.**

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

**Current status: Partial — existing controller actions and permission enforcement provide a foundation; remaining tools and audit coverage need verification.**

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

**Current status: Partial — genre/catalog improvements, title styling, and the festival playback HUD have landed; remaining experience and device regression work is open.**

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

**Current status: Partial — watchdog and transition safeguards are implemented in source; full rotation and failure-path behavior still needs testing.**

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

**Current status: Partial — shared queue and revision protections exist; idempotency, recovery, and atomic catalog concurrency remain open.**

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

**Current status: Not implemented; retain as future work.**

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

- `MusicQueueManager` is integrated, but the other four manager modules remain unintegrated pending dependency, API, and state-ownership review.
- The supplied `Music Module` has an empty music list; do not assume it supplies a production catalog.
- The source system's separate role system must not become a second permission authority.
- The global DJ MessagingService path is best-effort, not a durable globally synchronized playback queue.
- Global catalog removal currently relies on an authoritative snapshot check; it is not an atomic reservation against a concurrent enqueue. Treat this as an open consistency risk.
- `RestrictAudioToAllowlist` is not enabled by default; server-side audio inspection is not equivalent to a strict catalog allowlist.
- The `Audio Sound Count 1.rbxm` asset is a Sound named `ServerMusicSound`, not an audio counter implementation.
- Recent security and UI work has received source-level review/commit verification only. Roblox Studio multiplayer, mobile/console layout, live DataStore, Marketplace, MessagingService failure/replay, and exploit-client tests remain necessary.

## Updated implementation order

1. **Close high-risk consistency gaps:** design atomic global catalog-removal protection that blocks concurrent enqueue safely; do not ship a partial lock/reservation design.
2. **Complete Phase 1 testing:** exercise malformed/replayed requests, simultaneous queue changes, player departure, stale/duplicate/out-of-order cross-server commands, and service outages.
3. **Finish manager compatibility review:** integrate only the useful behavior from the remaining four managers without duplicate state, remotes, or permission authorities.
4. **Run UI regression:** verify HUD and full-screen UI on desktop, mobile, tablet, gamepad/console, and supported VR presentation.
5. **Add centralized configuration and recovery controls** after existing behavior has regression coverage.
6. **Finish staff tools and player experience** with bounded audit history and accessible error/empty/loading states.
7. **Verify playlist and cross-server recovery guarantees** against live-like DataStore and MessagingService conditions.
8. **Add bounded analytics** only after operational reliability is established.

Do not implement every item at once. Each phase should be reviewed, tested, and committed independently on the working branch. Mark a checkbox complete only when its stated exit criteria have evidence; source code existing is not proof of runtime correctness.
