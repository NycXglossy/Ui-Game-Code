# ClubMusic Diagnostics & Security — Master Release Register

**Date:** 2026-11-16  
**Branch:** `feature/sultan-settings-2026-11-10`  
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
- Client diagnostics projection remains aggregate-only.
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
9. Run the existing purchase/profile/session-lock, global playback sync, and two-server regression tests in the isolated environment. Do not use live production DataStores for test fixtures.

## Sign-off criteria
- [ ] Live-place hierarchy confirmed to use the secured ClubMusic transport, with no separately installed legacy `Music System` / `MusicRemotes` stack.
- [ ] Binary model/package scope reviewed or explicitly excluded by the project owner.
- [ ] Studio multiplayer test matrix passes.
- [ ] Published test-server matrix passes, including two-server MessagingService/MemoryStore behavior.
- [ ] No regressions in modern audio playback controls, crossfade, local queues, or optional playback-only global sync.
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
