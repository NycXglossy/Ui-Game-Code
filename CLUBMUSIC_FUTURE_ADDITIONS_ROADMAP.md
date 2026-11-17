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


## Phase 10 — Social Action Protection

**Current status: Implemented in source for the audited Tiki Tide player-teleport pathway; broader place audit and runtime tests remain open.**

- [x] Validate player teleport targets as server-resolved live players; reject invalid IDs and self-targeting.
- [x] Require live actor/recipient characters and living Humanoids.
- [x] Preserve recipient opt-in and the existing authorized GlobalModeration exception.
- [x] Revalidate both sessions, character identities, entitlement, and recipient consent after potentially yielding permission checks.
- [x] Revalidate character/root identity immediately before the server-authorized movement.
- [x] Add non-yielding per-actor and per-recipient cooldown reservations to reduce spam and concurrent duplicate actions.
- [x] Clean per-session budgets when players leave; keep existing ingress rate limiting.
- [ ] Audit the complete place for additional social actions/remotes not present in the inspected repository snapshot.
- [ ] Test multi-client consent, staff override, respawn/departure races, simultaneous recipient targeting, and rate-limit boundaries in Studio and published servers.
- [ ] Add equivalent controls only for additional social actions that are confirmed to exist; reuse shared validation and rate-limit infrastructure.

**Exit criteria:** every actual social action has server-side actor/target validation, consent/permission checks, per-player/per-target budgets, duplicate/race protection, bounded state, and regression evidence. Source review is not runtime verification.

**Implementation note:** see `CLUBMUSIC_PHASE10_SOCIAL_ACTION_PROTECTION.md`. The inspected Utility Bar actions are self-only or environment-wide; no separate friend/follow/invite/trade/emote remote was found in the files audited for this phase.


## Phase 11 — StaffSpectatorService

**Current status: Server-authoritative observation service, client camera adapter, and installer integration committed; runtime tests and command/UI adapter remain open.**

- [x] Add staff-only server authorization using the existing SecurityCore `GlobalModeration` permission.
- [x] Validate live staff actor, target user ID, live target, non-self target, and living target Humanoid.
- [x] Keep observation state server-owned; client attributes only select the camera subject.
- [x] Add target switching, state query, exit, bounded active-observer capacity, and lifecycle cleanup.
- [x] Suspend staff Humanoid movement while observing and restore captured movement/jump/rotation settings on exit.
- [x] Add camera follow, target respawn/leave handling, local movement-control disable/restore, and observer camera restoration.
- [x] Audit entry, target switching, exit, and departure through the existing global audit endpoint when available.
- [x] Add module and StarterPlayerScripts camera adapter to the staged installer with rollback copies.
- [ ] Add a trusted Kohl's Admin command or staff UI adapter; no client-facing control remote is introduced by this phase.
- [ ] Ensure every relevant gameplay action service rejects actions while `TikiTideSpectatorNoWorldActions` is true before claiming complete interaction lockdown.
- [ ] Test permission denial, entry/switch/exit, movement restoration, target/observer respawn and departure, audit, and installer rollback in Studio.
- [ ] Test mobile, desktop, and console camera/control behavior and run published-server regression tests.

**Important limitations:** The staff avatar remains visible in the world; this is not invisibility or an untraceable mode. No explicit spectator notification is sent to the observed player. No automatic moderation enforcement is performed. The client adapter is presentation only, while server authorization and movement suspension remain authoritative.

**Exit criteria:** trusted server commands/UI can call the server-only BindableFunction; all required gameplay actions honor spectator restriction state; movement and camera state restore safely under all lifecycle paths; runtime tests pass.

**Implementation note:** see `CLUBMUSIC_PHASE11_STAFF_SPECTATOR_SERVICE.md`.


## Phase 12 — Replay & Behavioral Analytics

**Current status: Bounded server-local event timeline, staff authorization, installer wiring, and repository-snapshot remote/audio/text/social source audit with privacy-safe adapters implemented; runtime verification remains open.**

- [x] Add a fixed-capacity server-local event ring (2,048 events) with actor/target IDs, timestamps, event type, severity, source, and bounded metadata.
- [x] Sanitize metadata and reject invalid IDs/non-finite values; do not retain Instances, arbitrary nested payloads, raw user text, credentials, or secrets.
- [x] Add staff-authorized query API using existing `GlobalModeration` permission.
- [x] Keep record/query endpoints server-only under ServerStorage; add no client remote.
- [x] Wire CharacterPhysicsGuard signals and StaffSpectatorService lifecycle events into the timeline.
- [x] Add TeleportValidationService failure-signal and AvatarAccessoryValidationService detection adapters.
- [x] Add authoritative ProcessReceipt lifecycle adapters for received, retry, failure, granted, and duplicate outcomes; never copy PurchaseId into replay metadata.
- [x] Add status counters and installer staging/rollback integration.
- [x] Avoid frame capture, persistence writes, new MemoryStore maps, and background polling workers.
- [x] Record sanitized server-submitted security signals through the existing ReportSignal gateway and committed global ban/request-block changes.
- [x] Record successful TeleportValidationService destination verification as an informational replay event.
- [x] Add malformed-envelope and handler-exception replay adapters at the confirmed ClubMusic RequestAction and Tiki Tide Settings remote boundaries; ordinary rejections/cooldowns are not scored as exploit evidence.
- [x] Audit the repository snapshot's remaining remote ingress and audio/chat/social validation paths; wire fixed-name signals for confirmed malformed/unsupported requests, deterministic audio validation rejections, and privacy-safe filtered text/audio outcomes. Document intentionally excluded read-only queries and untrusted client telemetry.
- [x] Add the staff-only ;cmreplay Kohl's Admin command with optional UserId/limit filtering; query remains server-only and requires GlobalModeration.
- [ ] Test authorization, filters, overflow, cleanup, bounded memory, and event fidelity in Studio and published servers.
- [ ] Measure overhead under load and verify it does not degrade essential validation or existing gameplay.

**Important limitations:** this is a per-server in-memory event timeline, not durable or cross-server history. It does not capture every frame or full-session video, does not alter threat scores, and does not enforce moderation. Repository-snapshot adapters cover CharacterPhysicsGuard, TeleportValidationService failure/success outcomes, AvatarAccessoryValidationService, authoritative ProcessReceipt outcomes, StaffSpectatorService lifecycle, `ReportSignal` submissions and committed moderation changes, malformed/exceptional ClubMusic and Tiki Tide Settings requests, Utility Bar malformed/unsupported requests, Tool Shop unsupported operations, deterministic Creator Hub audio validation rejections, and successful filtered text/audio outcomes. Read-only query endpoints and untrusted purchase-prompt telemetry are intentionally excluded. External Kohl's Admin internals and scripts/assets absent from the repository are not covered. Roblox Studio/published-server tests and performance profiling remain outstanding.

**Exit criteria:** bounded memory, server-only record access, permission-checked review, complete adapters for confirmed security event sources, and successful runtime/performance tests.

**Implementation note:** see `CLUBMUSIC_PHASE12_REPLAY_BEHAVIORAL_ANALYTICS.md`.

## Phase 13 — Adaptive Security Load Manager

**Current status: Implemented in source for server-heartbeat-driven optional-work budgeting; runtime/load verification remains open.**

- [x] Add a server-only adaptive workload manager with bounded five-second Heartbeat sampling and Normal/Reduced/Critical modes.
- [x] Add hysteresis for overload entry and staged recovery to avoid rapid mode flapping.
- [x] Define bounded budgets for optional diagnostics sampling, replay queries, analytics aggregation, and background maintenance.
- [x] Guarantee essential validation, authorization, rate limiting, purchase receipt processing, moderation enforcement, and security-event recording are never throttled.
- [x] Expose status, budget lookup, and token consumption only through ServerStorage BindableFunctions; add no client remotes.
- [x] Gate staff replay queries under the optional ReplayQueries budget while leaving replay event recording available in every mode.
- [x] Record load-mode transitions in the existing bounded replay timeline without user text or client-provided metadata.
- [x] Add installer staging and pin the release source to the module commit.
- [ ] Test threshold transitions, hysteresis, token refill/burst limits, and essential-task bypass in Studio.
- [ ] Test replay review behavior under Normal, Reduced, and Critical load.
- [ ] Profile Heartbeat callback overhead, memory footprint, and gameplay behavior in Studio and published servers.
- [ ] Verify installer rollback and shutdown disconnect the manager without duplicate services.

**Important limitations:** the automatic signal currently measures server Heartbeat delay only; it does not directly measure total memory, network saturation, CPU utilization, or DataStore queue depth. Existing ResourceGuard and StorageGuard remain authoritative for storage limits. Only replay queries are budget-gated in this phase; other optional subsystems require reviewed call-site integrations. No essential security path is throttled and no automatic moderation enforcement is added.

**Exit criteria:** bounded server-only operation, stable mode transitions, optional-work throttling under pressure, essential-path availability in every mode, successful replay-query behavior, and passing Studio/published-server load tests.

**Implementation note:** see `CLUBMUSIC_PHASE13_ADAPTIVE_SECURITY_LOAD_MANAGER.md`.

## Phase 14 — Unified Diagnostics & Health

**Current status: Existing diagnostics foundation confirmed; Phase 14 source integration adds Phase 12 replay, Phase 13 adaptive-load, SafeCall, and a bounded observability summary to the existing server-local snapshot and authorized staff output. Runtime verification and legacy retirement audit remain open.**

- [x] Preserve the existing Diagnostics coordinator, ServiceRegistry, ServerHealth, observational Watchdog, ErrorHistory, SafeCall, and SecurityCore status providers; do not replace them.
- [x] Expose the dedicated AdaptiveSecurityLoadManager status through the existing server-only diagnostics provider.
- [x] Expose SecurityReplay status counters through its dedicated read-only ServerStorage BindableFunction; do not return replay event contents in the health snapshot.
- [x] Include SafeCall call/failure/recovery counters without exposing detailed errors or tracebacks to clients.
- [x] Add a bounded observability-health summary with component counts and explicit partial/unavailable/degraded states.
- [x] Add adaptive-load mode, replay retention/capacity, and SafeCall counters to the existing authorized staff OperationalDiagnostics output.
- [x] Preserve existing Global API names, metric counters, server-local scope, and observational-only boundaries.
- [ ] Audit dynamic consumers, packaged models, and embedded third-party packages before retiring obsolete diagnostics code.
- [x] Confirm SafeCall and ErrorHistory remain separate after consumer/semantics review; their distinct consumers and failure lifecycles do not justify merging them.
- [ ] Verify watchdog pulse expectations during long tracks, paused playback, AutoDJ idle periods, and disabled recovery.
- [ ] Reconcile previously reported degraded watchdog, detail-registry, and memory warnings against fresh runtime output.
- [ ] Test missing optional diagnostics dependencies and confirm they are reported accurately without breaking ClubMusic startup.
- [ ] Test all snapshot/status APIs, staff permissions, client isolation, bounded storage, and output privacy in Studio and published servers.
- [ ] Profile diagnostics sampling and snapshot-call overhead under controlled load.
- [ ] Complete playback, queue, global playback-only sync, purchases, moderation, Utility Bar, Settings, and spectator regression tests.

**Important limitations:** this phase does not fix a watchdog warning merely by displaying it. It does not infer memory pressure from an arbitrary threshold, change health policy, repair services, restart systems, or perform moderation. No obsolete diagnostic implementation is retired in this phase. Runtime verification remains mandatory.

**Exit criteria:** one accurate, bounded, server-local health view; clear component state distinctions; authorized staff visibility without private traces; preserved compatibility; successful Studio/published-server tests; and a completed consumer audit before any legacy cleanup.

**Implementation note:** see `CLUBMUSIC_PHASE14_UNIFIED_DIAGNOSTICS_HEALTH.md`.


## Phase 15 — Unified Incident Correlation & Threat Intelligence

**Current status: Source implementation committed; Studio/published-server verification remains open.** This phase adds bounded local evidence correlation without replacing SecurityMonitor, SecurityReplayService, or the existing IncidentResponse case workflow.

- [x] Add `SecurityThreatIntelligence` as a server-only SecurityCore module with a 10-minute per-subject window, 256-subject cap, 12 signal-code cap per subject, 256 review-item cap, and 30-minute review-item expiry.
- [x] Use fixed machine signal codes and categories; retain no raw user text, chat, client payloads, asset IDs, or tracebacks.
- [x] Require at least two distinct signal categories and two distinct signal codes plus a minimum score before creating a Medium review item; repeated single-category signals alone cannot create one.
- [x] Add High confidence triage only when at least three categories and three signal codes meet the higher score threshold.
- [x] Integrate existing ReportSignal, RecordGlobalSecuritySignal, SecurityMonitor threshold, unhealthy watchdog pulse, and SafeCall failure adapters.
- [x] Add the server-only endpoint and read-only status endpoint through the SecurityCore installer.
- [x] Add an authorized `;cmthreat [UserId] [Limit]` staff review command; the server controller and service independently check GlobalModeration permission.
- [x] Include threat-intelligence health counters in the existing diagnostics and operational status snapshots.
- [x] Preserve IncidentResponse as a separate explicit staff case workflow; threat correlation does not create persistent cases or take enforcement action.
- [ ] Verify installer staging/promotion/rollback and endpoint isolation in Studio.
- [ ] Test one-signal, repeated-signal, multi-category confidence thresholds, caps, expiry, and subject eviction.
- [ ] Verify every adapter emits the intended fixed signal codes and no raw details.
- [ ] Test unauthorized queries, command parsing, and bounded staff output.
- [ ] Profile signal-recording overhead under burst traffic and test missing optional endpoints.
- [ ] Re-run ClubMusic playback, queue, sync, purchases, moderation, Utility Bar, Settings, and spectator regressions.

**Important limitations:** the correlation service is per-server memory only, advisory, and not durable or cross-server. Its confidence labels are evidence-diversity triage levels, not probabilities. No kick, ban, shadow restriction, gameplay nerf, movement correction, or other automatic enforcement is performed. The existing MemoryStore-backed IncidentResponse service remains independent and is still opened/resolved only through its existing authorized workflow.

**Implementation note:** see `CLUBMUSIC_PHASE15_THREAT_INTELLIGENCE.md`.


## Phase 16 — Diagnostics Completion

**Status: Source implementation committed; runtime acceptance remains open.**

- [x] Add server process-memory trend/freshness with a bounded 20-sample window.
- [x] Add controller-local aggregate diagnostics for purchase receipts, join moderation lookup outcomes, and playback backend/queue state.
- [x] Include controller and CharacterPhysicsGuard health in the unified snapshot.
- [x] Expand staff `;cmdiagnostics` with purchase, moderation, playback, memory, security-monitor and physics summaries.
- [x] Add validated Success/Failure/Observed metric outcomes and explicit SafeCall latest-outcome reporting.
- [x] Add optional client-local diagnostics bootstrap, disabled by default, with FPS/frame-time, memory and ping status available only through a local BindableFunction.
- [x] Keep client telemetry untrusted and untransmitted.
- [ ] Run Studio and published-server acceptance tests, reconcile watchdog/registry/memory warnings, and profile overhead.
- [ ] Verify client bootstrap installation and local-only access.
- [ ] Complete playback, queue, sync, purchase, moderation, Utility Bar, Settings and spectator regression tests.

**Explicit exclusions at Phase 16 completion:** HoneypotManager and client-integrity sensors were not yet present; Phase 17 and Phase 18 subsequently add those as separate security telemetry systems. Client error-log aggregation remains unimplemented. The Phase 16 client FPS/memory/ping diagnostics remain local-only; Phase 18's fixed-code security reports use a separate bounded server endpoint and are explicitly untrusted. No automatic enforcement or cross-server diagnostics aggregation is added.


## Phase 17 — Honeypot Manager

**Status: Source implementation committed; runtime acceptance remains open.**

- [x] Add a server-only HoneypotManager with a dedicated, isolated ReplicatedStorage decoy folder.
- [x] Add decoy admin-privilege, purchase-receipt, VIP-entitlement, and moderation-action remotes; none aliases or replaces a real gameplay remote.
- [x] Make decoy handlers inert; RemoteFunction decoys return a neutral unavailable response.
- [x] Record fixed, sanitized hit signals into existing server-local ThreatIntelligence and SecurityReplay services.
- [x] Add per-player cooldown, bounded subject tracking/counters, PlayerRemoving cleanup, and server-only status.
- [x] Add installer staging/pinning and include honeypot status in existing unified diagnostics and staff output.
- [x] Preserve detection-only behavior: no automatic kick, ban, restriction, movement correction, or IncidentResponse case creation.
- [ ] Test all decoys, signal fidelity, cooldowns, caps, cleanup, and no-gameplay-effect behavior in Studio.
- [ ] Test installer collision handling, promotion/rollback, shutdown cleanup, and optional-module failure behavior.
- [ ] Profile burst overhead and run published-server regression tests for playback, queues, sync, purchases, moderation, Utility Bar, Settings, spectator, and diagnostics.

**Important limitations:** decoys are visible under ReplicatedStorage and are not secrets. They detect probing/interaction; they cannot prevent exploiters from discovering real remotes or replace server-side authorization. A hit is not proof and is never a standalone punishment trigger. Honeypot signals are server-local and are not shared cross-server.

**Implementation note:** see `CLUBMUSIC_PHASE17_HONEYPOT_MANAGER.md`.


## Phase 18 — Client Integrity Telemetry

**Status: Source implementation committed; runtime acceptance remains open.**

- [x] Add an optional-by-installation client dependency observer for expected ClubMusic modules and remotes, with a 60-second startup grace period.
- [x] Transmit only fixed, allowlisted missing-dependency codes and a probe-completed code; no free-form client data or device/performance telemetry.
- [x] Validate server-derived Player identity, cap reports at eight unique codes/player, apply a one-second interval, cap tracked subjects at 200, and clean up on PlayerRemoving.
- [x] Record accepted observations only as Info-level events in the existing server-local SecurityReplay timeline.
- [x] Keep client reports out of ThreatIntelligence scoring, authorization, moderation, and enforcement.
- [x] Add a ServerStorage-only status endpoint and staff diagnostics counters.
- [x] Extend installer module pinning, LocalScript staging, backup, promotion, and rollback.
- [ ] Test normal/missing dependencies, forged/malformed/burst reports, quotas, cleanup, and replay-only routing in Studio.
- [ ] Verify the client-local FPS/memory/ping sampler remains untransmitted.
- [ ] Profile overhead and complete published-server gameplay regression tests.

**Trust boundary:** this checks dependency presence only. A client can suppress or forge reports; a completed probe is not proof of untampered code, and absence of a report is not evidence of cheating. The server remains authoritative. See CLUBMUSIC_PHASE18_CLIENT_INTEGRITY_TELEMETRY.md.


## Phase 19 — Server-Authoritative Movement & Action Validation Audit

**Status:** Source audit and narrow ledger hardening committed; Studio and published-server acceptance remains open.

- [x] Audit CharacterPhysicsGuard, MovementAuthority, TeleportValidationService, Tiki Tide Settings movement/teleport actions, Utility Bar Size/Mount, and installer integration.
- [x] Confirm the existing movement registration paths for Tiki Tide WalkSpeed/JumpPower/WorldGravity and Utility Bar BodyScale.
- [x] Harden MovementAuthority.Check so departed player targets cannot retain usable grants.
- [x] Restrict the special `ANY` check to the Fling marker.
- [x] Document that CharacterPhysicsGuard is detection-only and does not enforce movement, validate paths/displacement, or prove client integrity.
- [x] Document the Tiki Tide Settings TeleportTo consent, permission, cooldown, ticket, identity, and destination checks.
- [ ] Verify external Kohl's Admin, flight, vehicle/mount, knockback, freeze, and staff movement call paths before claiming coverage.
- [ ] Test respawn, latency, network ownership, legitimate launch/knockback, vehicles, and PC/mobile/console movement in Studio and published servers.
- [ ] Adversarially test client movement tampering, teleport replay, ticket expiry, destination mismatch, and unauthorized action attempts.
- [ ] Profile observer/ledger overhead and complete the gameplay regression matrix.

**Important limitations:** no automatic movement correction, kick, ban, freeze, or gameplay restriction is introduced. Physics anomalies are detection signals only. Do not enable velocity-based enforcement until legitimate movement and network ownership behavior has been measured. No Roblox runtime or exploit tests are claimed by the source commit.

**Implementation note:** see `CLUBMUSIC_PHASE19_MOVEMENT_ACTION_VALIDATION.md`.


### Phase 19 follow-up — delayed rigs and Kohl's adapter coverage

- [x] Change CharacterPhysicsGuard initialization to wait up to 10 seconds for custom Humanoids and HumanoidRootParts, with lifecycle revalidation after yielding.
- [x] Audit the supplied RegularCommandsSecurityServer alias map and confirm SecurityCore authorization plus bounded target/value validation runs in the command filter before native handlers.
- [x] Document that Kohl's MovementAuthority records are post-handler observer markers, not the permission gate; Flight/Frozen/Teleport/JumpImpulse/StarterWalkSpeed markers are not currently consumed by CharacterPhysicsGuard.
- [ ] Studio-test late-assembling rigs, respawn/departure/shutdown during waits, and every mapped Kohl's movement alias.
- [ ] Inspect actual Kohl's handler implementations and third-party mount/vehicle/knockback scripts before asserting their physics behavior is covered.

**Boundary:** adapter mapping and source-level permission flow are verified from the supplied integration file; native Kohl's internal movement behavior and runtime effects are not certified. See `CLUBMUSIC_PHASE19_MOVEMENT_ACTION_VALIDATION.md`.


## Phase 20 — Security Coverage Closure

**Status:** Scoped text-source inventory completed; binary/third-party review and the live-place acceptance matrix remain explicit gates.

- [x] Inventory the current ClubMusic, Tiki Tide Settings, UtilityBar, Kohl's adapter, teleport, movement, diagnostics, replay, threat, honeypot and spectator server boundaries.
- [x] Record server owners and trust boundaries for client-to-server remotes and server-only BindableFunctions.
- [x] Confirm the inspected text-source set contains no additional ProximityPrompt, ClickDetector or DragDetector handlers; do not generalize this to binary assets.
- [x] Document SecurityCore permission versus entitlement boundaries and preserve fail-closed behavior for unknown integrations.
- [ ] Inspect binary Roblox models, packaged third-party assets and the actual live-place hierarchy.
- [ ] Verify native Kohl's handlers and every actual vehicle/mount/knockback/prompt interaction before claiming complete coverage.
- [ ] Run the authorization, remote-abuse and cross-system regression matrix.

**Implementation note:** see CLUBMUSIC_PHASE20_SECURITY_COVERAGE_CLOSURE.md.

## Phase 21 — Unified Incident Response

**Status:** Source integration committed; incident storage and threat escalation acceptance tests remain open.

- [x] Fix the IncidentResponse existing-record coalescing callback to increment from old.eventCount rather than reading an uninitialized nextItem.
- [x] Add explicit ;cmthreatcase TTI-ID staff escalation from a retained server-local review item to the existing MemoryStore ManualReview case workflow.
- [x] Require IncidentResponse at the controller and case service, and preserve the threat service's independent GlobalModeration check.
- [x] Generate a bounded summary from fixed review metadata; reject server-level review conversion to a player case.
- [x] Keep case creation manual; no automatic persistent case opening or automatic punishment.
- [ ] Test first-write and repeated/coalesced event counts, throttles, storage failures, TTL, resolution and permissions.

**Implementation note:** see CLUBMUSIC_PHASE21_UNIFIED_INCIDENT_RESPONSE.md.

## Phase 22 — Staff Security Console

**Status:** Existing staff command bridge extended; runtime authorization and lifecycle tests remain open.

- [x] Add ;cmspectate UserId, ;cmspectateswitch UserId, ;cmspectateoff and ;cmspectatestate commands to the existing Administration group.
- [x] Route commands through the server-only admin bridge and spectator BindableFunction.
- [x] Recheck SecurityCore GlobalModeration in the controller and StaffSpectatorService.
- [x] Preserve existing camera adapter, audit/replay events, bounded command output and mobile UI.
- [ ] Test each command, unauthorized callers, target/staff departure, respawn, shutdown and movement restoration.
- [ ] Verify actual gameplay services that should honor TikiTideSpectatorNoWorldActions; do not claim universal lockdown until audited.

**Implementation note:** see CLUBMUSIC_PHASE22_STAFF_SECURITY_CONSOLE.md.

## Phase 23 — Performance & Compatibility Hardening

**Status:** Resource bounds and compatibility contracts documented; load/device profiling remains open.

- [x] Record existing bounded capacities and essential-task bypass requirements across replay, threat intelligence, honeypots, client integrity, spectator, incident storage and diagnostics.
- [x] Preserve the adaptive manager's policy that essential validation, authorization, rate limiting, receipts, moderation enforcement and event recording are never throttled.
- [x] Document PC/mobile/console, modern AudioPlayer, crossfade, independent local queues, playback-only global sync, purchase, entitlement and UtilityBar regression requirements.
- [ ] Profile high-player-count Heartbeat, remote bursts, memory, MemoryStore/DataStore pressure, adaptive mode transitions and maximum spectator load.
- [ ] Test low-end mobile, desktop and console input/UI behavior and published-server shutdown/installer lifecycle.
- [ ] Confirm no essential security path is dropped under Reduced/Critical load.

**Implementation note:** see CLUBMUSIC_PHASE23_PERFORMANCE_COMPATIBILITY_HARDENING.md.

## Phase 24 — Production Release & Legacy Retirement

**Status:** Release and rollback procedure documented; production sign-off remains gated.

- [x] Define the exact branch/revision pinning rule for the installer and test-place rollout.
- [x] Document rollback steps that preserve receipt ledgers, profile/session state and cross-server configuration.
- [x] Confirm the standalone legacy Music System remains reference-only and must not be installed beside the current controller.
- [x] Defer obsolete diagnostics retirement until dynamic consumers, embedded assets and live-place references are reconciled.
- [ ] Complete binary/third-party scope review and live-place hierarchy verification.
- [ ] Pass Studio and published two-server acceptance matrices and record the exact tested commit.
- [ ] Only then approve production rollout and any legacy cleanup.

**Implementation note:** see CLUBMUSIC_PHASE24_PRODUCTION_RELEASE_AND_RETIREMENT.md.



---

# Tiki Tide Unified Security & Intelligence Framework — Phases 25–39

**Status:** Forward development roadmap. Phases 1–24 have owner-reported operational acceptance; the repository still distinguishes that report from independently reproduced runtime certification. Each new phase is implemented and reviewed independently. Do not mark a phase complete until its source, integration, and stated acceptance evidence are recorded.

## Phase 25 — Advanced Exploit Prevention & Request Integrity
- Audit every client remote and cross-server receiver.
- Map authorization, entitlement, validation, rate limits, idempotency, concurrency, state ownership, and failure behavior.
- Add only narrowly scoped protections for confirmed gaps.
- Test duplicate, replayed, reordered, concurrent, malformed, and unauthorized requests.
- Reuse SecurityCore, SanityValidation, RateLimit, Idempotency, MessageValidation, and existing receipt protections.
- Reference: [Phase 25 scope](CLUBMUSIC_PHASE25_ADVANCED_EXPLOIT_PREVENTION.md).

## Phase 26 — Server-Authoritative Movement Envelope
- Extend movement validation only after measuring legitimate movement sources.
- Model authorized speed/jump/gravity settings, Utility Bar size, mounts, vehicles, knockback, launch pads, teleport tickets, respawns, network ownership, and latency.
- Add bounded displacement/path anomaly observation where it can be measured reliably.
- Keep correction/enforcement disabled until false-positive rates and safe recovery behavior are demonstrated.
- Never treat client-reported physics or one velocity spike as proof.

## Phase 27 — World & Environment Integrity
- Audit lighting, gravity, stage/club controls, terrain and protected environment state.
- Identify each legitimate server-side writer and its SecurityCore permission.
- Add detection-only drift checks for protected properties with bounded event-driven sampling.
- Do not overwrite live environment state automatically; staff or an explicitly authorized owner action must resolve drift.

## Phase 28 — Avatar, Tool, Mount & Vehicle Protection
- Complete inspection of mount tools, vehicle scripts, accessory/tool grants, companion clones, and third-party packages.
- Validate server ownership and approved grant/equip paths.
- Detect unauthorized tool or accessory state changes without removing legitimate assets automatically.
- Test respawn, avatar scaling, R6/R15, network ownership, and cleanup.

## Phase 29 — Economy, Entitlement & Reward Abuse Protection
- Audit every coin, boost, donation, title-slot, pass, developer-product, and reward mutation.
- Preserve the durable receipt ledger and ProcessReceipt as the purchase authority.
- Add transaction idempotency and concurrency protection only where a confirmed mutation path lacks it.
- Verify owner/group VIP rules and all existing pass/product IDs; never grant from client purchase-prompt telemetry.

## Phase 30 — Audio, Animation & Media Abuse Protection
- Audit all audio, boombox, animation, image/artwork, and media mutation entry points.
- Preserve modern AudioPlayer as the single playback authority and keep per-server queues independent under optional playback-only global sync.
- Validate server-owned catalog policy and permissions for DJ/staff actions.
- Do not install the standalone legacy Music System or create another playback controller.

## Phase 31 — Chat, Text & Social Safety Closure
- Audit every announcement, title, custom message, AFK text, bubble, teleport, and player-to-player action.
- Ensure TextService filtering is applied server-side before display/replication.
- Verify consent, target liveness, cooldowns, and permission checks for social actions.
- Keep native Roblox chat moderation responsibilities distinct from experience-owned text systems.

## Phase 32 — Account Risk & Ban-Evasion Signals
- Define privacy-limited, server-derived signals for repeat abuse and moderation evasion.
- Use platform-provided identifiers and authorized moderation records only; do not build device fingerprints or infer sensitive traits.
- Treat account linkage as an investigation clue, not proof of shared identity or automatic punishment.
- Keep evidence bounded, access-controlled, and subject to retention limits.

## Phase 33 — Behavioral Analytics & Replay Expansion
- Extend replay coverage only to validated server-side events and fixed signal codes.
- Add bounded aggregate trends for repeated action patterns, movement anomalies, and abuse clusters.
- Keep raw client payloads, chat content, secrets, and unnecessary personal data out of replay.
- Preserve server-local replay/diagnostics boundaries; no cross-server diagnostics aggregation.

## Phase 34 — Unified Incident Review Workflow
- Connect correlated threat review items to staff-managed cases with explicit authorization.
- Add evidence summaries, assignment/status, timestamps, and resolution reasons with strict size/retention bounds.
- Preserve independent SecurityCore checks at each service boundary.
- Require staff review for escalation; no automatic permanent bans.

## Phase 35 — Shadow Moderation & Temporary Restrictions
- Design reversible, scoped restrictions with expiry, reason codes, issuer, and audit trail.
- Separate containment from punishment; do not silently alter core player progression or purchases.
- Require confidence/evidence thresholds and staff authorization.
- Provide safe rollback and appeal paths before enabling any live restriction.

## Phase 36 — Cross-Server Moderation Consistency
- Use durable storage as the source of truth and MessagingService only as a best-effort notification path.
- Validate schema, issuer, sequence/revision, expiry, idempotency, and receiving-server authorization.
- Test outage, duplicate, delayed, reordered, and recovery behavior.
- Keep diagnostics local; this phase concerns moderation state distribution, not diagnostics sharing.

## Phase 37 — Staff Security Console & Investigation Tools
- Extend existing staff commands for incident review, threat evidence, replay, diagnostics, and spectator workflows.
- Apply SecurityCore permission checks in both the command adapter and the underlying service.
- Add bounded pagination and safe output formatting.
- Keep privileged APIs in ServerStorage; do not expose them through client remotes.
- Preserve staff spectator's documented visibility and world-action limitations unless separately redesigned and tested.

## Phase 38 — Security Self-Audit, Resilience & Performance
- Verify module manifests, installer pin, dependency availability, endpoint classes, and server-only placement.
- Add bounded local readiness reports and release drift checks without automatic repair or restart.
- Profile CPU/Heartbeat, memory, storage budgets, signal bursts, and shutdown cleanup.
- Keep client FPS/memory/ping and any client error buffer local-only unless a separately reviewed, privacy-safe telemetry design is approved.
- Do not retire legacy diagnostics, aliases, or rollback assets until consumer and live-place audits pass.

## Phase 39 — Final Certification & Controlled Retirement
- Reconcile repository sources, installer revision, binary assets, third-party packages, and the live Roblox hierarchy.
- Run the complete Studio multiplayer and published two-server acceptance matrices.
- Verify modern audio, crossfade, local queues, playback-only global sync, purchases, receipt recovery, VIP entitlements, Utility Bar, Settings, moderation, spectator, and PC/mobile/console compatibility.
- Pin the exact tested installer revision, preserve rollback, and document exclusions.
- Retire only proven-unused legacy components; never remove rollback assets or diagnostics consumers based on names alone.
- Publish only after owner sign-off and recorded acceptance evidence.

## Global requirements for Phases 25–39
1. SecurityCore remains the sole permission authority.
2. Server-side state and validation remain authoritative.
3. Existing remotes, profile schema, receipt ledger, and playback state owners are preserved unless a migration is specifically justified.
4. Diagnostics and replay remain local to each server; client diagnostics remain local to the client.
5. Honeypots, client integrity telemetry, and behavioral signals are clues, not proof.
6. No automatic permanent bans or gameplay punishment from one signal.
7. All tables, logs, queues, caches, retries, and background work remain bounded.
8. Essential security validation, purchase processing, and moderation enforcement are never disabled by optional-work budgets.
9. No secrets or privileged modules are placed in clients.
10. Every phase records source changes, static checks, runtime evidence, known exclusions, and rollback behavior.
