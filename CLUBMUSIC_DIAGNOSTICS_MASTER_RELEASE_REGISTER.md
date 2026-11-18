# ClubMusic Diagnostics & Security — Master Release Register

**Date:** 2026-11-16  
**Branch:** `security/phase1-foundation`  
**Purpose:** Single release record for the diagnostics/security work, implemented changes, audit scope, and items that must remain open before installation.

## Release decision

**Do not install or publish from this register yet.** Static source work is updated and the inspected active remote surfaces are documented. Roblox Studio and published-server verification remain mandatory. Binary Roblox model/package contents and live-place deployment verification still prevent claiming a complete repository-wide certification.

This register distinguishes source implementation, static review, and runtime verification. A static pass is not a security certification.

## Implemented source changes

### Authorization and DJ permissions
- SecurityCore is the central rank/permission authority for the inspected ClubMusic controller and global services.
- Rank 100 DJ is a narrow `GlobalDJ` permission and is not general staff.
- Moderator starts at rank 150; Admin 200; Co-owner 254; Owner 255.
- DJs can use the limited booth Control Mode actions: skip, pause/resume, restart.
- Queue reorder/removal/clear and playlist management remain Owner/Co-owner-only.
- The server projects separate `canUseDJBooth` and `canManageDJBooth` flags; the renderer uses those flags for visibility.

### Diagnostics and server-side security
- Global diagnostics snapshots and SafeCall recent records are exposed through server-only BindableFunctions in ServerStorage, not client remotes in the inspected source.
- Client diagnostics measurements remain client-local and opt-in; no client telemetry is projected to the server or used for authorization.
- RequestAction is a multiplexed gameplay boundary with action allowlisting, bounded payload validation, per-player/server budgets, and action-specific authorization.
- Global API privileged mutations use SecurityCore actor authorization and fail closed when authorization is unavailable.
- Cross-server messages require MessageValidation and bounded message-ID deduplication.
- UtilityBar extended actions validate live players, action names, server-owned entitlements, cooldowns, and bounded values.
- Tiki Tide Settings validates entitlement, action/payload shape, teleport consent, finite/clamped gravity, TextService filtering, cooldowns, and reauthorization after yielding filter operations.

### Additional UtilityBar remote hardening in this release
- `UtilityBar/UtilityBarActions.server.lua`: added a live-player guard and rechecks that the player remains connected after the yielding avatar-description lookup, before applying the description.
- `UtilityBar/ToolShop.server.lua`: added a live-player guard and a 0.5-second per-player query cooldown for the read-only `GetShop` RemoteFunction; the cooldown entry is cleared on player departure.

## Current client/server remote inventory (text-source review)

### ClubMusicRemotes
| Remote | Direction | Purpose / boundary |
|---|---|---|
| `RequestAction` | Client → server | Multiplexed action dispatcher; action and payload validation, budgets, and per-action authorization. |
| `GetState` | Client → server | Read-only state query; per-player/global query throttles. |
| `GetMusicCatalog` | Client → server | Read-only catalog query; bounded query arguments and throttles. |
| `GetMusicPlaylists` | Client → server | Read-only playlist query; throttled and storage-readiness guarded. |
| `StateChanged` | Server → client | State snapshots. |
| `Notice` | Server → client | Server-authored notices. |
| `PurchaseDiagnostic` | Client → server | Untrusted prompt telemetry only; bounded to 12 events/player/minute and never treated as receipt proof. ProcessReceipt remains authoritative. |

### TikiTideSettingsRemotes
| Remote | Direction | Purpose / boundary |
|---|---|---|
| `Request` | Client → server | Settings request RemoteFunction; live-player, action/payload, entitlement, cooldown, consent, and permission checks. |
| `Broadcast` | Server → client | Filtered announcement/bubble delivery. The inspected service has no client-to-server listener on this event. |

### UtilityBarRemotes
| Remote | Direction | Purpose / boundary |
|---|---|---|
| `RefreshOwnAvatar` | Client → server | Own-avatar refresh; 15-second cooldown, live-player guard, and post-yield connection/character checks. |
| `ExecuteUtility` | Client → server | Extended utility actions; live-player guard, allowlist, server-owned entitlement checks, cooldown, and bounded values. |
| `ToolShop` | Client → server | Read-only `GetShop` query; live-player guard and 0.5-second per-player cooldown. |

### Original standalone Music System — retired from the active runtime architecture
The repository still retains the original root-level `Music System` source and its companion legacy modules as reference assets. However, the canonical integration guide explicitly says this standalone script is **not a runtime dependency** and must not be installed alongside ClubMusic. Its queue, playback, validation, skip-vote, playlist, role, and transport responsibilities have been replaced or absorbed by the secured `UI_Server_Controller`, `MusicCatalogService`, `MusicPlaylistService`, and `ClubMusicRemotes` architecture.

The legacy script itself still contains code that would create a separate `MusicRemotes` folder and use its own `RoleSystem` if someone manually installed it. That source file remaining in GitHub does not mean those remotes are active. Do not install the standalone script, its legacy role system, or its manager children. Treat source cleanup/archive deletion as a separate optional housekeeping task, not a release blocker. The live Roblox place should still be checked to confirm it follows the documented secured hierarchy.

### Server-only BindableFunction surfaces
The Global API, diagnostics snapshot/recent-record providers, and Kohl's adapter bridge use ServerStorage BindableFunctions in the inspected source. These are server-to-server trust boundaries, not client remotes. Each mutation caller must still provide an actor that the receiving service independently authorizes.

## Manager-module integration status

The repository now contains all five named manager source files:
- `MusicQueueManager.luau`
- `MusicPlaybackManager.luau`
- `MusicValidationService.luau`
- `MusicSkipVoteManager.luau`
- `MusicPlaylistManager.luau`

The earlier Phase 0 audit's statement that these sources were absent is stale. The current queue/playback/skip/playlist modules are largely controller adapters or bounded helpers; they do not establish that a separate manager architecture has been installed or that controller-owned state has been migrated. The root-level `Music System` also expects child modules under its own script hierarchy. The actual Roblox instance hierarchy must be checked before any manager installation or migration is declared complete. The controller remains the single authority for its current queue, playback, permissions, and remote contract.

## Explicit exclusions / incomplete evidence
- Binary `.rbxm` / `.rbxmx` assets and embedded third-party packages were not exhaustively decompiled or reviewed in this text-source pass.
- Kohl's Admin internals are not certified by this register; only the separate ClubMusic/Tiki Tide adapter and hardening integration are in scope.
- No repository review can prove that the currently published Roblox place contains the exact source revision in this branch.

## Required Roblox runtime verification before installation
Run in a dedicated test universe/place, not against production data:

1. Run `ClubMusic_SecuritySmokeTest.client.lua` from a temporary test client and inspect both client and server output. Verify malformed/oversized payloads, non-finite values, unknown actions, invalid catalog paging, and no state mutation.
2. Exercise remote bursts from one and multiple clients. Verify per-player and server-wide throttles engage and recover without blocking normal UI traffic.
3. Test ordinary player, DJ rank 100, Moderator 150, Admin 200, Co-owner 254, and Owner 255 against the relevant booth, queue, playlist, moderation, global configuration, and diagnostics operations.
4. Test SecurityCore missing/unavailable/expired cache and permission revocation during yielding operations. Protected mutations must fail closed.
5. Publish invalid, expired, wrong-scope, and replayed cross-server messages. Confirm MessageValidation rejects them and no local mutation/broadcast occurs.
6. From an ordinary client, attempt to locate or invoke diagnostics APIs. Confirm no diagnostic records, traces, or privileged service methods are client-reachable.
7. Test avatar refresh while respawning/leaving and rapid Tool Shop query calls; confirm cooldowns and safe rejection.
8. Inspect the live place hierarchy to confirm it matches the documented secured ClubMusic layout; specifically confirm the standalone legacy `Music System` and `MusicRemotes` are not installed, and review the five ClubMusic adapters, Kohl's adapter, and installer scripts.
9. Run purchase/profile/session-lock recovery, per-server playback/queue isolation, and retained cross-server global-feature regression tests in the isolated environment. Do not test or enable cross-server playback sync; do not use live production DataStores for test fixtures.

## Sign-off criteria
- [ ] Live-place hierarchy confirmed to use the secured ClubMusic transport, with no separately installed legacy `Music System` / `MusicRemotes` stack.
- [ ] Binary model/package scope reviewed or explicitly excluded by the project owner.
- [ ] Studio multiplayer test matrix passes.
- [ ] Published test-server matrix passes, including two-server MessagingService/MemoryStore behavior.
- [ ] No regressions in modern audio playback controls, crossfade, and independent per-server queues; verify retired playback-sync code remains absent.
- [ ] No regression in DJ role separation or Kohl's adapter behavior.
- [ ] Installation package/revision is pinned to the verified commit and only then presented for installation.

**Current status:** Source-level changes and scoped text-source audits are documented. Runtime verification and live-place reconciliation are still open. Do not label this release production-ready or install it until the sign-off checklist is complete.


## Diagnostics source closure addendum (2026-11-16)

A final source-level pass synchronized the embedded SafeCall ModuleScript in `ClubMusic_Global_Optional_Services.rbxmx` with the standalone implementation, including the 100-key/120-second warning deduplication bound. The local watchdog pulse metadata is now capped at eight validated primitive fields. Source review confirmed Playback pulses each second even during pause/reload, Queue and AutoDJ pulse every 30 seconds plus refill events, and Recovery/Moderation are optional event-driven probes. SafeCall and ErrorHistory remain separate because they record different failure lifecycles.

These changes close the in-repository source integration tasks for Phase 14 only. They do not satisfy Studio/published-server tests, historical warning reconciliation, load profiling, binary/third-party package review, or live-place revision verification. No legacy diagnostic implementation is retired.


## Phase 14 source closure and Phase 15 correlation addendum (2026-11-16)

- Phase 14 source-level diagnostics integration is closed for this branch. The packaged SafeCall copy is synchronized with the standalone bounded implementation, watchdog pulse metadata is capped at eight validated fields, and the controller pulse cadence has been statically reviewed.
- SafeCall and ErrorHistory remain separate because they capture different operation/error lifecycles. Neither implementation is retired.
- Phase 15 adds `ClubMusicSecurityCore/SecurityThreatIntelligence.lua`, a server-local, bounded correlation service. It consumes fixed-code events from ReportSignal, RecordGlobalSecuritySignal, SecurityMonitor threshold alerts, unhealthy watchdog pulses, and SafeCall failures.
- Correlation requires at least two distinct categories and signal codes before creating a Medium review item; one weak or repeatedly duplicated category cannot independently create an item. High confidence requires three categories, three codes, and the higher score threshold.
- The SecurityCore installer stages the new module. The server-only `TikiTideThreatIntelligence` endpoint and read-only status endpoint are added; the authorized `;cmthreat [UserId] [Limit]` command provides bounded staff review.
- Threat correlation is advisory, per-server memory only, and does not kick, ban, restrict, alter gameplay, or automatically create a persistent IncidentResponse case. Existing IncidentResponse remains an independent staff-managed workflow.

**Still not release-ready:** no Roblox Studio or published-server runtime tests have been performed. Installer rollback, authorization, threshold/cap/expiry behavior, adapter fidelity, client isolation, performance, historical watchdog/registry/memory warning reconciliation, binary/third-party package scope, live-place hierarchy, and regression tests remain required. Do not publish this branch to production until the dedicated test-place matrix passes.


## Phase 16 — Diagnostics Completion (2026-11-16)

**Source status:** Implemented. **Runtime status:** Open; do not mark production-ready.

- [x] Add bounded 20-sample server memory trend, freshness and stale-state reporting.
- [x] Add server-only aggregate controller diagnostics for authoritative receipt outcomes, purchase prompt telemetry distinction, join moderation lookup outcomes, and playback backend/queue state.
- [x] Include controller diagnostics and CharacterPhysicsGuard in the unified health snapshot.
- [x] Expand `;cmdiagnostics` with purchase, moderation, playback, memory trend, SecurityMonitor and physics signal summaries.
- [x] Add outcome-aware bounded global metric recording while preserving legacy three-argument API calls.
- [x] Add explicit latest SafeCall outcome and synchronize packaged SafeCall source.
- [x] Add client-local memory/ping sample freshness and a disabled-by-default local diagnostics bootstrap.
- [x] Confirm client measurements are never transmitted and cannot authorize/enforce.
- [ ] Install the optional client module/bootstrap in a test place and verify local-only status.
- [ ] Run Studio and published-server receipt, moderation, playback, watchdog, memory and authorization tests.
- [ ] Reconcile historic watchdog/registry/memory warnings against fresh server output.
- [ ] Profile diagnostics sampling/snapshot overhead and complete gameplay regression matrix.

**Not included at Phase 16 completion:** HoneypotManager and client-integrity sensors were not yet implemented; Phase 17 and Phase 18 subsequently add those as separate security telemetry systems. Client error-log aggregation remains unimplemented. Phase 16 client FPS/memory/ping diagnostics remain local-only; Phase 18 fixed-code security reports are separate, bounded, and untrusted. Full per-action moderation outcome counters are not claimed; join lookup health and existing Audit/IncidentResponse summaries remain the available evidence.

**Boundaries preserved:** diagnostics are server-local/client-local, no diagnostics DataStore/MemoryStore/MessagingService writes or client-to-server diagnostic remotes, no automatic recovery/enforcement/gameplay changes, and no legacy diagnostics code retired.


## Phase 17 — Honeypot Manager (2026-11-16)

**Source status:** Implemented and integrated with existing SecurityCore installer, ThreatIntelligence, SecurityReplay, diagnostics, and staff `;cmdiagnostics`. **Runtime status:** Open.

- [x] Four inert decoy remotes isolated in a dedicated ReplicatedStorage folder.
- [x] Fixed signal codes only; no raw client arguments or payload retention.
- [x] Five-second per-player cooldown, 256-subject cap, aggregate counters, and leave cleanup.
- [x] ServerStorage-only status endpoint and local diagnostics exposure.
- [x] No automatic enforcement, persistent writes, cross-server sharing, or real remote contract changes.
- [ ] Studio/published-server tests, installer rollback/cleanup, collision behavior, signal fidelity, bounded-load profiling, and gameplay regression matrix.



## Phase 18 — Client Integrity Telemetry (2026-11-16)

**Source status:** Implemented in the SecurityCore installer and unified diagnostics. **Runtime status:** Open.

- [x] Fixed-code dependency-presence observations for UI_Network, UI_Renderer, and the ClubMusicRemotes contract.
- [x] Dedicated RemoteEvent receiver with exact allowlist, server-derived identity, per-player interval, eight-report cap, 200-subject cap, and leave cleanup.
- [x] Accepted reports route only to Info-level server-local SecurityReplay entries; no ThreatIntelligence score, authorization, moderation, or enforcement.
- [x] Status exposed through ServerStorage and ;cmdiagnostics; installer stages the LocalScript with rollback.
- [ ] Studio/published tests, malformed/burst/forgery tests, dependency-failure tests, replay fidelity, and overhead/regression profile.

**Trust boundary:** client reports are untrusted and can be suppressed or forged. Dependency-presence checks are not cryptographic attestation. Existing client FPS/memory/ping diagnostics remain local-only.


## Owner-reported runtime acceptance and Phases 20–24 update (2026-11-16)

The project owner reports that the previously implemented Tiki Tide/ClubMusic systems and earlier phases are working in their experience. This is recorded as owner-reported runtime acceptance; it is not an independent reproduction or a substitute for retaining test logs. The new Phase 20–24 source edits in this update have not been run in Roblox Studio or a published test server during this work session.

### Phase 20 — Security Coverage Closure
- Added CLUBMUSIC_PHASE20_SECURITY_COVERAGE_CLOSURE.md.
- Recorded the tracked text-source remote/action inventory and its server owners: ClubMusic RequestAction/state/catalog/playlists/purchase telemetry, Tiki Tide Settings, UtilityBar, Kohl's adapter, teleport tickets, movement observer, spectator and local diagnostics/security services.
- Explicitly bounded the audit: no additional client-triggered ProximityPrompt/ClickDetector/DragDetector handler was found in the inspected text sources; binary assets, native Kohl's internals and the live place still require separate inspection.
- No broad new remote, client authority, or permissive fallback was introduced.

### Phase 21 — Unified Incident Response
- Fixed ClubMusicSecurityCore/IncidentResponse.lua so an existing incident's eventCount is incremented from old.eventCount, not the uninitialized nextItem.
- Added ;cmthreatcase TTI-ID. An authorized IncidentResponse user can explicitly convert a retained current-server threat review item into a MemoryStore ManualReview case.
- Controller validates the ID, queries the server-local ThreatIntelligence endpoint, constructs a bounded summary from fixed metadata, and calls the existing incident service. The threat service and incident service retain independent SecurityCore permission checks.
- No automatic case creation, kick, ban, shadow restriction, movement correction or gameplay restriction was added.

### Phase 22 — Staff Security Console
- Added ;cmspectate UserId, ;cmspectateswitch UserId, ;cmspectateoff and ;cmspectatestate through the existing Kohl's Admin Administration command group.
- Controller checks SecurityCore GlobalModeration and calls the ServerStorage-only spectator endpoint. StaffSpectatorService independently rechecks authorization.
- No client remote or mobile UI change was added. Existing visibility and NoWorldActions limitations remain documented.

### Phase 23 — Performance & Compatibility Hardening
- Added a phase document recording bounded capacities and required performance/device/regression tests.
- Preserved essential security-path bypass from adaptive optional-work budgets.
- No runtime load profile or device test is claimed.

### Phase 24 — Production Release & Legacy Retirement
- Added a release/rollback procedure and production sign-off checklist.
- The legacy standalone Music System remains reference-only; do not install it beside the current controller.
- No diagnostics implementation, SafeCall/ErrorHistory store, watchdog, registry, compatibility alias or rollback asset is deleted in this update.
- Installer pinning must be updated to a commit that contains the approved Phase 20–24 sources before the installer is used.

### Phase 20–24 source commits
- Phase 21 incident coalescing fix: 47871142fcf96f1e66a4e308ed52cc1d423be596
- Staff spectator controller bridge: 81b5ec94616a06d620fa1d1a3866a719576be4c5
- Staff spectator addon commands: fedbeed719aebed0ce9e3ff76193828051102feb
- Threat-review case escalation: ea8c512ca7b6eb9789d11ee4537748eb3eb69750
- Threat-review addon command: c1d18e35aba5bfe850a03aad81b41ef446ae4bd4
- Phase 20–24 documentation commits are recorded in the branch history and linked from the roadmap.

**Release status:** The five phases have source/docs updates. Production readiness still requires exact installer pinning, Studio/published acceptance of the new commands and incident coalescing fix, binary/third-party/live-place inspection, and the release checklist in Phase 24. Do not describe these new changes as runtime-tested until those tests are recorded.

- Phase 23 follow-up: AdaptiveSecurityLoadManager now has a separate ThreatReviewQueries token bucket (Normal 0.5/s burst 2; Reduced 0.1/s burst 1; Critical disabled). The SecurityCore installer gates only optional threat-review Query operations with this budget; Record, authorization, incident creation, and all essential security paths remain unthrottled.
- Phase 24 installer pin: ClubMusic_Security_Core_Installer.lua now pins source commit eba230a9606465fb2d19fd4e4a803df66e3a3c82, which contains the Phase 20–24 code and staff command integrations. The installer pin update is commit 9501945f385a0cc921bbaede63b458942e491fea.


## Owner-reported acceptance and Phases 25–39 roadmap (2026-11-16)

The project owner has stated that the implemented systems and phases are working in their experience. Record this as owner-reported runtime acceptance; it is not an independent reproduction by this repository update. Phase-specific release evidence should still be retained where available.

- [x] Record Phase 25–39 as the next ordered development program.
- [x] Preserve the existing SecurityCore, RateLimit, Idempotency, MessageValidation, replay, threat-intelligence, honeypot, diagnostics, incident-response, and spectator boundaries.
- [x] Define Phase 25 as an audit-first advanced exploit-prevention pass; no duplicate remote gateway or security authority is introduced before a concrete gap is confirmed.
- [ ] Complete Phase 25 endpoint-by-endpoint authorization, payload, rate-limit, replay, concurrency, and state-owner inventory.
- [ ] Complete Phases 26–39 in order with separate source commits and acceptance records.
- [ ] Keep all Studio/published-server certification claims tied to reproducible evidence and the exact installed revision.

The Phase 25–39 plan is recorded in `CLUBMUSIC_FUTURE_ADDITIONS_ROADMAP.md`; Phase 25 acceptance scope is in `CLUBMUSIC_PHASE25_ADVANCED_EXPLOIT_PREVENTION.md`. The future phase headings are plans, not completed implementations.


## Phase 14.1 — Local Staff Controls diagnostics (2026-11-18)

**Source status:** Implemented on `phase14.1-local-staff-diagnostics`.
**Runtime status:** Not verified; release gate remains open.

- [x] Extend local registry with expected Instance class/parent checks and dynamic restoration verification.
- [x] Register GlobalAPI and the ServerHealth, Watchdog, and Diagnostics ModuleScript dependencies.
- [x] Add bounded 20-entry local health transition history, degraded duration, consecutive degraded checks, and last recovery timestamp.
- [x] Add average estimated server FPS and maximum Heartbeat frame-time values to ServerHealth.
- [x] Integrate Diagnostics overview into the Phase 22 Staff Controls console using the existing authorized staff command path.
- [x] Read client FPS/ping/memory from the existing client-local diagnostics module only while the authorized staff overview is open.
- [x] Preserve detailed diagnostics commands and all Phase 14/16 diagnostic service APIs.
- [ ] Studio test staff authorization, revocation, dashboard refresh, category switching, close/reopen, and sampler lifecycle.
- [ ] Test dependency removal, wrong-class/reparenting, and restoration in a disposable test place.
- [ ] Verify the 20-transition cap and state-duration/recovery behavior under repeated state changes.
- [ ] Profile server/client overhead at low and full player counts and during long-running playback/crossfade/queue activity.
- [ ] Complete purchase, moderation, playback, two-server local-queue isolation, retained global-feature, and Utility Bar regression tests.
- [ ] Complete binary/package and live-place hierarchy review before any production installation.

No live Roblox place was modified. No diagnostics sharing, persistence, client telemetry transmission, automatic recovery, enforcement, or legacy retirement was introduced. See `CLUBMUSIC_PHASE14_1_LOCAL_STAFF_DIAGNOSTICS.md` for the implementation and test matrix.



## Phase 13.1 adaptive workload integration addendum (2026-11-18)

**Development branch:** `phase13.1-adaptive-load-integration`
**Base:** `phase14.1-local-staff-diagnostics`
**Source status:** Phase 13.1 source integration committed; not merged or installed.
**Runtime status:** All Roblox Studio, published test-server, load-profile, and gameplay regression gates remain open.

- AdaptiveSecurityLoadManager now reports bounded attempted/accepted/deferred counters for each optional task, cumulative mode durations, current mode duration, and recovery healthy-window streak.
- ReplayQueries and ThreatReviewQueries retain their existing query-only budget integration.
- AnalyticsAggregation now defers only optional metrics aggregation when its token budget is unavailable. Global health checks, ServerHealth, and watchdog sampling are not gated.
- DiagnosticsSampling now controls only passive aggregate movement measurement inside CharacterPhysicsGuard. The sample cadence adapts to Normal/Reduced/Critical mode; event-driven movement property checks, MovementAuthority, TeleportValidationService, and security event recording remain active.
- BackgroundMaintenance remains reserved because no safe optional maintenance worker was identified. Profile persistence, receipt handling, storage cleanup, and security retention are not deferred.
- Added a client-local visual-quality LocalScript for explicitly tagged ClubEffect particle rates and StageClubLight shadows. It reads a server-local Workspace attribute; no RemoteEvent/RemoteFunction or client telemetry is introduced. Light Enabled/Color/Brightness remain owned by existing Stage & Club Lighting controls.
- Existing OperationalDiagnostics output inside the authorized Staff Controls console now exposes adaptive workload counters, mode trend, and movement sampling counts.
- The SecurityCore installer now stages, backs up, promotes, and rolls back the visual-quality LocalScript. Its module/client release pin is `8a028a2e28cfc245263486eb607f52d52183d390`, containing the updated AdaptiveSecurityLoadManager, CharacterPhysicsGuard, and client script.
- Passive movement measurement uses 0.5s / 1.5s / 3.0s intervals in Normal / Reduced / Critical, with a 3.5s maximum accepted sample gap. Event-driven movement checks remain active.

### Phase 13.1 release gates still open

- [ ] Luau syntax/type review in Roblox Studio.
- [ ] Installer stage/promotion/rollback acceptance in a disposable Studio place.
- [ ] Adaptive mode, hysteresis, mode-duration, and token-bucket tests.
- [ ] VIP speed, size, mount, teleport, respawn, and scripted movement regression tests.
- [ ] Client visual restoration, dynamic tag, and Stage & Club Lighting regression tests.
- [ ] Staff authorization and diagnostics lifecycle tests.
- [ ] Server/client performance profiling and full gameplay regression tests.
- [ ] Published test-server acceptance.

No Roblox runtime testing was performed by the source update. Do not install or publish this branch until the release gates pass and the project owner explicitly approves deployment.


## Phase 33 — Developer Product receipt migration (source-only)

- `ClubMusicSecurityCore.ReceiptAuthority` remains the single receipt ingress coordinator; the controller retains exactly one `MarketplaceService.ProcessReceipt` adapter.
- Added `ClubMusicSecurityCore.ReceiptTransactionService` for the durable profile receipt journal, pending-receipt recovery, session-lock checks, and in-memory reconciliation.
- Added `ClubMusicSecurityCore.ReceiptHash` and migrated both the controller and Global Service to it. The standalone root-level `ClubMusic_ReceiptHash.lua` was deleted after its consumers were moved.
- Removed controller-owned `persistReceipt` / `recoverPendingProductReceipt` implementations and receipt-memory cache tables. The controller now provides profile/session and reward adapters to Security Core.
- Preserved `ClubMusic_ProductReceipts_v1`, `ClubMusic_XPBoostReceipts_v1`, journal key formats, full PurchaseId comparisons, Prepared/Completed states, pending markers, profile schema compatibility, legacy XP key reads, product IDs, and reward mappings.
- The Global Service continues to own the shared XP boost transaction journal because it coordinates the cross-server boost timer. No duplicate global receipt implementation was introduced.
- Updated installer module inventory and pinned source snapshot for `ReceiptHash` and `ReceiptTransactionService`; added Phase 33 migration documentation.

**Validation boundary:** Source changes only. The disposable Studio purchase matrix, injected DataStore failures, interrupted-receipt recovery, profile-save race, and two-server XP boost regression tests are still mandatory. No production DataStore or live Roblox place was changed. Do not delete historical journal records, legacy profile receipt fields, or legacy XP compatibility reads.


## Phase 0–33 Performance & Compatibility Consolidation (2026-11-18)

**Working branch:** `phase0-33-performance-compatibility`  
**Baseline:** `7292321a62dfe0cc16559240a3e1a5c3af0f8414` (Phase 13.1 branch head at consolidation start).  
**Status:** Targeted source improvements committed; cross-phase static review and Roblox runtime/device profiling remain in progress. This is not a production release or runtime sign-off.

### Local-first architecture contract

- Client-local: graphics quality, visual effects, UI state, input, per-listener presentation, frame sampling, and optional client diagnostics. Client observations are untrusted and are not sent to the server for performance scoring or authorization.
- Server-instance-local: Now Playing, playback clock, Auto DJ, playlists' active cursors, request queues, skip votes, transient caches, adaptive load state, watchdogs, health samples, and diagnostic histories.
- Server-authoritative: purchases and receipt journals, profile/session writes, entitlements, permissions, moderation decisions, request validation, and all gameplay mutations.
- Cross-server: only explicitly global features with a demonstrated product requirement and existing consumers, such as global moderation, announcements, catalog invalidation, and shared XP boost/receipt coordination. Cross-server playback synchronization and diagnostics aggregation are retired / prohibited.

### Source changes in this consolidation

1. `TikiTideAdaptiveVisualQuality.client.lua`
   - Combines each client's mobile / saved graphics quality with the current server's adaptive-load mode.
   - Applies only to explicitly tagged club effects and lights; supports existing `ClubEffect` / `StageClubLight` tags and the `ClubVFX` / `ClubLight` aliases.
   - Preserves and restores original particle rates, Enabled states, Beam states, and light Shadows when the script or tags are removed.
   - No remotes, client telemetry, DataStore, MemoryStore, or cross-server calls.
   - Commit: `7292321a62dfe0cc16559240a3e1a5c3af0f8414`.

2. `UI_Server_Controller_server (1).lua`
   - Removed the retired playback-sync snapshot commit/apply functions, playback message handlers, eight-second status poller, follower gates, and playback-sync calls from track transitions and DJ pause/restart/skip paths.
   - Retained the old action name only as a compatibility rejection with a clear retired message.
   - State/diagnostics projection now explicitly reports playback sync as retired and queues as local.
   - Removed obsolete sync configuration and action cooldown entries.
   - Commits: `e2e54cba9ba6f362dda64c132616b4b9cb28d135`, `e6184c15b46df342956aaad5a9a6a58fa9c3be79`.

3. `MusicValidationService.luau`
   - Replaced full-cache scans on metadata cache misses with bounded FIFO eviction (constant-time insertion/eviction).
   - Applied the same bounded cache discipline to the legacy music-ID metadata cache.
   - Added a short configurable negative-cache TTL for transient Marketplace metadata failures to avoid repeated provider calls during bursts.
   - Preserved the controller's independent AudioPlayer preload and experience-permission checks; cached metadata is not treated as proof that an asset is playable.
   - Commit: `89ea911b64f9337eebed57da86921b4db3d2a722`.

### Cross-phase preservation rules

- Phases 0–12: keep controller state ownership and existing UI/network contracts; adapters must not create duplicate queue/playback/playlist authorities.
- Phases 13–18: adaptive budgets may defer optional queries/aggregation only; diagnostics remain bounded and local; essential validation, authorization, moderation, receipt work, and security-event recording remain active.
- Phases 19–24: movement and incident services remain server-authoritative and detection-only where specified; preserve fail-closed protected actions and Studio isolation; do not add high-frequency polling.
- Phases 25–32: preserve existing endpoint validators, SecurityCore authorization, bounded evidence, movement/environment safety, economy/entitlement invariants, and chat filtering. Performance changes must not weaken security or alter third-party Kohl's adapter contracts.
- Phase 33: preserve the single ProcessReceipt adapter, durable receipt journal, session locks, product mappings, and XP receipt compatibility.

### Remaining audit and acceptance work

- Review all tracked first-party scripts and installers for unnecessary cross-server dependencies, duplicate state owners, unbounded caches, repeated descendant scans, connection leaks, and redundant polling.
- Reconcile the live Studio hierarchy and packaged/binary assets; text-source review cannot certify installed Roblox instances or third-party packages.
- Run Luau parsing/static analysis; no parser was available during the initial source pass.
- Run Studio multiplayer and published isolated test-place matrices for purchases/receipt recovery, local queue isolation, cross-server global features, remote bursts, diagnostics, adaptive transitions, movement/respawn, and repeated installer execution.
- Profile Heartbeat delay, server memory, client frame time, and network traffic at normal/peak player counts on low-end mobile, desktop, and console.
- Keep mobile UI and controls unchanged unless a mobile-specific compatibility issue is measured and explicitly addressed.

**Release boundary:** No Roblox Studio place, published server, live DataStore, live MemoryStore, or production asset was changed by these GitHub commits. Source commits and static checks do not establish a measured FPS/memory improvement. Do not call this complete or production-ready until the profiling and regression matrix is recorded.

### Additional local-playback retirement and installer compatibility updates

- Removed the retired Cross-Server Playback panel and toggle from `UI_Renderer (2).lua`, and removed the action from `UI_Network.lua` allowlists/cooldowns. The controller rejects legacy action submissions without making a global API call.
- Aligned `ClubMusic_Security_Core_Installer.lua` and `ClubMusic_Global_Service_server_1.lua` to the same SecurityCore release snapshot, `142562f0727f8c3fa748a9bd00dbd1871e5f4fe9`. The pinned snapshot was fetched and confirmed to contain the updated visual client and receipt/adaptive-load modules.
- Current implementation details and acceptance requirements are recorded in `CLUBMUSIC_PHASE0_33_PERFORMANCE_COMPATIBILITY_CONSOLIDATION.md`.
