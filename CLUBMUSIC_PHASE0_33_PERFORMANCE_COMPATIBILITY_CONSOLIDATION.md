# Phase 0–33 — Performance & Compatibility Consolidation

**Working branch:** `phase0-33-performance-compatibility`  
**Baseline:** `7292321a62dfe0cc16559240a3e1a5c3af0f8414`  
**Status:** In progress. Targeted source improvements are committed; full static review, Luau parsing, Studio testing, published test-place profiling, and live hierarchy reconciliation remain open.  
**Deployment:** Source-only. No Roblox place or production service was changed.

## 1. Governing architecture: local first

Keep state and work at the narrowest scope that can correctly own it.

| Scope | Responsibilities |
|---|---|
| Client-local | Graphics quality, tagged visual effects, UI presentation/state, input, per-listener audio presentation, frame sampling, optional client diagnostics |
| Server-instance-local | Now Playing, playback clock, Auto DJ selection/refill, queue, playlist cursor, skip votes, request counters, transient caches, adaptive load mode, watchdog, health samples, diagnostics histories |
| Server-authoritative | Entitlements, authorization, moderation decisions, request validation, purchases, durable receipt journal, profile/session writes, gameplay mutations |
| Cross-server only when required | Global moderation, announcements, catalog invalidation, shared XP boost/receipt coordination, and other explicitly approved global features with real consumers |

Cross-server playback synchronization is retired. Each server must own its own playback state and request queue. Cross-server diagnostics aggregation is prohibited. Do not add DataStore, MemoryStore, MessagingService, RemoteEvents, or RemoteFunctions for data that can remain local.

Client-side performance measurements and diagnostics stay on the client and are never sent to the server or used for authorization. The existing ClientIntegrityTelemetry is a narrow, separate security exception: it sends only fixed allowlisted integrity/liveness signal codes at low frequency for server-side review; payload values, device metrics, frame rates, timestamps, and free-form text are not transmitted. These observations remain untrusted and never authorize or punish. Essential server validation, authorization, purchase processing, moderation enforcement, and security-event recording must never be throttled by adaptive load.

## 2. Source changes committed in this pass

### A. Client-local graphics quality

File: `TikiTideAdaptiveVisualQuality.client.lua`

- Combines the local player's mobile / saved graphics quality with the current server's adaptive-load mode.
- Supports `ClubEffect` and `StageClubLight` plus `ClubVFX` and `ClubLight` aliases.
- Scales ParticleEmitter rates, disables low-priority particles/beams on low-end devices, and disables tagged light shadows under low graphics or degraded server load.
- Preserves and restores prior ParticleEmitter Rate/Enabled, Beam Enabled, and Light Shadows values when tags are removed or the script is destroyed.
- No remotes, telemetry, persistence, or cross-server traffic.

Commit: `7292321a62dfe0cc16559240a3e1a5c3af0f8414`.

### B. Remove retired playback-sync work

File: `UI_Server_Controller_server (1).lua`

- Removed playback snapshot commit/apply helpers, playback message handlers, the eight-second playback leader/status poller, follower-only queue/skip/pause/restart guards, and no-op commit calls.
- Kept the historical action identifier as a compatibility rejection with an explicit retired message; it cannot enable synchronization.
- State and diagnostics report playback synchronization as retired and playback/queues as local.
- Removed obsolete playback-sync config and action cooldown entries.
- Preserved global moderation, announcements, catalog invalidation, and XP boost coordination through their separate service paths.

Commits: `e2e54cba9ba6f362dda64c132616b4b9cb28d135`, `e6184c15b46df342956aaad5a9a6a58fa9c3be79`.

### C. Bounded audio metadata cache

File: `MusicValidationService.luau`

- Replaced full-cache scans on metadata cache misses with bounded FIFO eviction, avoiding an O(n) scan for each new metadata entry.
- Applied bounded cache insertion to both the active audio metadata cache and the compatibility music-ID cache.
- Added a short configurable negative-cache TTL for transient Marketplace metadata failures to reduce repeated provider calls during bursts.
- Preserved the controller's independent AudioPlayer preload and experience-permission/playability checks. Cached metadata is never treated as proof that an asset is playable.
- Cache size remains configurable and bounded (default 128, maximum 1024).

Commit: `89ea911b64f9337eebed57da86921b4db3d2a722`.


### G. Threat-intelligence hot-path work

File: `ClubMusicSecurityCore/SecurityThreatIntelligence.lua`

- Added a server-local incident ID index so an existing review item is found in O(1) instead of scanning the retained incident list for every qualifying signal.
- Throttled subject/incident expiry sweeps to at most once per five seconds. The retained maps/lists remain capacity-bounded, and expiry may be delayed by no more than the sweep interval.
- Clears index entries on subject expiry, incident expiry, oldest-item eviction, and service shutdown.
- Does not add a task loop, remote, persistence, cross-server traffic, or change signal scoring, review thresholds, or enforcement (there is none).
- Commit: `50289e2525605bb308462465f9cd50253dec054d`; documentation: `c37a624484dec7624e098d49233e843b6d199f22`.


### H. Reduce optional movement network-query frequency

File: `ClubMusicSecurityCore/CharacterPhysicsGuard.lua`

- Kept the existing adaptive movement displacement sample cadence and event-driven movement property checks unchanged.
- Network ownership and ping context are now queried at most once per five seconds per character, rather than on every accepted movement sample (which can run every 0.5–3 seconds).
- Exposed a separate network-observation sample count and interval so aggregate movement sample counts remain interpretable.
- This is optional server-local measurement only; it adds no remote, persistence, cross-server state, or enforcement.
- Source commit: `373f1cb1448cc58ec22093248132c117fa77349`; Phase26 documentation: `ed22d4b67ce8cb818c2affd5d11bcecdcd20ab85`.

## 3. Phase 0–33 compatibility map

| Phase range | Preserve while optimizing |
|---|---|
| 0–4 | Single controller state owner; existing queue/playback/remote adapters; no duplicate managers or request remotes |
| 5–9 | Durable receipt idempotency, VIP entitlement authority, avatar/audio validation, and filtered text |
| 10–12 | Social action limits, staff spectator lifecycle, bounded replay/analytics; no automatic enforcement from telemetry |
| 13–18 | Adaptive budgets only defer optional work; local diagnostics and bounded histories; essential security paths remain active |
| 19–24 | Server-authoritative movement and incident handling, fail-closed protected actions, Studio isolation, and incident-storage guards |
| 25–28 | Existing remote validators, one SecurityCore permission authority, movement/environment integrity, asset provenance, and detection-only boundaries |
| 29–31 | Product/reward idempotency, entitlement policy, audio/media ownership, and TextService/Roblox chat compatibility |
| 32–33 | Advisory account-risk signals, explicitly authorized moderation, and the single ProcessReceipt adapter with durable journal/recovery |

No optimization may create a second role authority, rate limiter, receipt journal, playback owner, queue, or remote gateway. UtilityBar remains independent from ClubMusic. Desktop/server changes must not alter mobile layout or controls unless a mobile-specific regression is measured and intentionally addressed.

## 4. Audit findings and work still open

The initial source scan found these periodic / potentially expensive paths, which require profiling before changing cadence or semantics:

- Controller playback clock and watchdog: preserve transition generation checks, modern AudioPlayer ownership, crossfade preparation, and local queue advancement.
- XP settlement and profile persistence: preserve fractional XP accounting, session locks, receipt pending markers, write locks, and durable saves. Do not skip writes based only on an assumed dirty flag.
- Dance Floor rewards: current scan is every 10 seconds and caps tagged-zone inspection; measure before increasing cadence or altering reward eligibility.
- Group/pass refresh and profile saves: measure Marketplace/DataStore budgets and join/leave behavior before reducing or batching work.
- Global moderation reconciliation and XP boost reconciliation: remain cross-server only because those features are intentionally global; keep bounded retry and failure behavior.
- Diagnostics: workspace effect inventory is opt-in and one-shot; keep it out of normal frame loops and yield during large scans.
- UtilityBar mount/clone/lighting actions: inspect template/character descendant scans and verify they are event/action-driven, bounded, and scoped to tagged assets.
- Binary Roblox models and third-party Kohl's Admin packages are not fully certified by text-source inspection.

## 5. Required acceptance matrix

### Client/device compatibility
- [ ] Low-end mobile, high-end mobile, desktop, and console.
- [ ] Automatic graphics quality and explicit levels 1–3 / 4–10.
- [ ] Tag add/remove, nested tagged folders, runtime-created effects, and script teardown restore original visual settings.
- [ ] Verify actual map assets use the intended tags and that Stage & Club Lighting controls do not fight the local optimizer.
- [ ] Confirm mobile joystick/jump controls, UI layout, inventory, and utility bar remain unchanged.

### Server/load and local isolation
- [ ] Normal and peak player counts; Heartbeat delay, memory, and network rates.
- [ ] Burst remote traffic from one and multiple players.
- [ ] Adaptive Normal/Reduced/Critical transitions and recovery hysteresis.
- [ ] Local queue, Now Playing, playback clock, playlist cursor, skip votes, and crossfade remain independent in two servers.
- [ ] No playback leader lease, shared playback snapshot, playback topic, or playback polling remains active.
- [ ] Global moderation, announcements, catalog invalidation, and XP boost coordination still work in isolated test data.
- [ ] Diagnostics remain server-local; client diagnostics remain client-local and untrusted.

### Security, storage, and lifecycle
- [ ] Essential validation/authorization remains active in every adaptive-load mode.
- [ ] Marketplace cache FIFO eviction, positive TTL, transient failure TTL, and provider recovery.
- [ ] Audio metadata cache hit still performs actual AudioPlayer preload and experience permission checks.
- [ ] DataStore/MemoryStore throttling, temporary outage, profile session-lock contention, and recovery.
- [ ] Receipt Prepared/Completed recovery, duplicate ProcessReceipt calls, and pending profile marker preservation.
- [ ] Repeated join/leave/respawn, server shutdown, and repeated installer execution do not leak connections or duplicate services.

## 6. Validation boundary

Static source changes are not proof of FPS, memory, or latency improvement. The current pass has not run a Luau parser/compiler, Roblox Studio multiplayer tests, published test-server tests, or controlled device profiling. The live place hierarchy and embedded/binary assets still need reconciliation. Do not merge, install, or publish this branch as production-ready until the acceptance matrix is recorded in a dedicated test place.


### D. Installer / Global Service release alignment

- The Security Core installer and Global Service now both pin the same reviewed module/client source snapshot: `142562f0727f8c3fa748a9bd00dbd1871e5f4fe9`.
- Verified that this pinned snapshot contains the updated adaptive visual client, receipt transaction service, receipt hash module, and adaptive load manager.
- The separate Phase 32 module pin remains independent.
- Commits: installer `e2ed24a13f8998ee52edb6451c0e022938ef2396`; Global Service `7960f321acd030703057251f5f4a6064825a2450`.

### E. Request-song architecture compatibility

The standalone `RequestSongEvent` / `songQueue` sample is not installed. The existing ClubMusic `RequestAction` / `RequestTrack` path remains the only request ingress and queue owner. It already applies server-side validation, request cooldowns and budgets, entitlement checks where required, duplicate/current-track checks, queue capacity, and catalog validation. Do not add a parallel queue, pass lookup, or asset metadata request path.

### F. Remove the retired sync control from the client surface

- `UI_Renderer (2).lua`: removed the Cross-Server Playback section and its toggle button from the DJ Booth.
- `UI_Network.lua`: removed the retired action from client allowlists and cooldown maps (including duplicate entries).
- The server retains only a compatibility rejection for old clients that still send the retired action.
- Commits: renderer `c7b2630c0875d8bdca0ae2d5301f8b127332b8f4`; network `a010461abd588f4b2a17a6568ed72d11433373eb`.


## Follow-up audit correction — local fallback limiter TTL

At branch head `ee80c913ea9943f08fd441adf6bce47199b2ab25`, the global service referenced an undefined `CONFIG.BudgetKeyTtlSeconds` while pruning its server-local fallback token buckets. Added the explicit `FallbackBucketIdleSeconds = 300` setting and wired the prune threshold to it. This prevents the periodic idle-bucket cleanup from comparing a number against nil after the first 15-second prune interval. The cleanup remains local, bounded, and independent of MemoryStore. Also corrected stale source comments that still described retired playback synchronization as opt-in.

Validation: source-level reference check only; no Luau compiler or Roblox runtime test was run.


A follow-up static audit also found that the global service referenced six undefined action/player/audio budget settings. Added explicit values aligned with the controller's configured ingress budgets: global actions 180 tokens/refill 90 per second, per-player actions 18/refill 12 per second, and audio 3/refill 0.25 per second. This avoids passing nil budget arguments into the shared limiter path. The retired-playback header comment was corrected at the same time. These are source-level consistency fixes; no live service or runtime test was performed.


## Local-only rate-limit alignment

A further review found the global service's optional RateLimit facade was being initialized with `consumeLocalBudget` under a different dependency name than the facade requires. The action/state/DataStore/audio consumers also treated the facade's shared-bucket result as mandatory, so the local-only fallback path could reject requests even when its per-server token bucket allowed them. The facade is no longer instantiated by the global service. Existing action, state, DataStore, audio, and compatibility API checks now use bounded per-server token buckets directly and explicitly report `scope = ServerLocal` / `usesSharedBuckets = false`. The fallback retains its configured capacity cap and refill ceiling, and the refill is now additionally capped by each budget's requested refill (so a low-rate audio bucket cannot inherit a faster generic fallback refill). Invalid key/capacity/refill/cost inputs are rejected before bucket arithmetic. The existing bindable name `ConsumeGlobalRateLimit` remains for compatibility, but returns `allowed, false` to identify that the decision is local, not cross-server shared.

Validation: static source inspection and reference checks only; no Luau compiler, Roblox Studio, multiplayer, or live-server test was run.


The same stale shared-result requirement was also present in the global XP boost DataStore budget helper and its read/activation paths. Those checks now honor the local per-server budget result while leaving the actual XP boost record and receipt journal in the existing cross-server DataStores. In other words, the *state* remains global because XP boosts are shared, but the *request budget* is local to each server.


## Active MusicValidationService cache alignment

The controller resolves the ModuleScript named `MusicValidationService` from ServerStorage (or the packaged `ClubMusic_ServerStorage_Modules` folder). The active root `MusicValidationService.lua` and the embedded ModuleScript source in `ClubMusic_ServerStorage_Modules.rbxmx` had still contained the older O(n) eviction scan and did not include the short failure cache, even though the separate `MusicValidationService.luau` source already contained a circular FIFO implementation. Updated the controller-facing module without changing its constructor or public method contract: bounded O(1) circular FIFO eviction, generation-safe stale queue entries, configurable short failure TTL (default 5 seconds), and bounded positive metadata TTL. The packaged ModuleScript source was synchronized to the same exact content so the normal ServerStorage package install receives the optimization. The controller still performs its own audio preload/playability validation; metadata cache hits do not authorize playback.

Validation: confirmed the controller's ModuleScript lookup name, confirmed the package's embedded ModuleScript source matches the canonical root file, and statically reviewed FIFO/expiry behavior. No Luau compiler or Roblox runtime test was run.


## Client map-audit allocation guard

The optional client diagnostics module previously enabled its one-shot Workspace effects inventory by default whenever the module was started. That scan calls `workspace:GetDescendants()`, which allocates a full descendant array before yielding through the inspection loop; on this project's large scene this can create an avoidable startup memory/CPU spike. The map audit now defaults to `DisabledByDefault` and runs only when a caller explicitly constructs the service with `auditWorkspaceEffects = true`. FPS/frame sampling, periodic client memory sampling, and optional modern AudioPlayer observation remain independent. The bootstrap is enabled by default when installed; all measurements remain client-local/untrusted. The separate installer added below now installs both required instances into their expected Roblox locations.

Validation: source re-fetch confirmed the default is false unless explicitly true; no client runtime test or memory measurement was performed.

## Client diagnostics bootstrap scope correction

The client diagnostics bootstrap is enabled by default again. The earlier global disable prevented all client-local FPS/frame-time, memory, and optional modern AudioPlayer observations from starting, even though the expensive workspace inventory had already been made opt-in. The bootstrap now starts the diagnostics service with default options; `auditWorkspaceEffects` remains false unless a caller explicitly opts in. This restores useful local diagnostics without adding remotes, transmission, persistence, or cross-server aggregation.

Validation: re-fetched the bootstrap and service source; confirmed the bootstrap enables the local sampler and the service constructor defaults `auditWorkspaceEffects` to false / `DisabledByDefault`. No Roblox runtime test or performance measurement was performed.

## Full-menu typography traversal consolidation

In `UI_Renderer (2).lua`, the menu typography pass previously traversed all descendants of the full panel and then traversed the content descendants a second time, even though the content container is already within the panel. Merged the content-specific TextLabel font/wrapping rules into the existing panel traversal. The same base-size capture, device scale/clamps, font choices, TextScaled behavior, and long-description wrapping are retained, while one redundant descendant-array traversal per tab render is removed. No mobile layout, sizing thresholds, controls, or tab content behavior was intentionally changed.

Validation: source-level exact-block replacement, followed by re-fetch and checks for a single typography descendant traversal and preserved device scale/wrapping rules. No Luau compiler or Studio UI regression test was run.

## Compact HUD visibility candidate index

The full-menu renderer previously called `PlayerGui:GetDescendants()` on menu/panel visibility changes to locate duplicate compact HUDs. Replaced repeated whole-PlayerGui scans with a maintained list of matching GuiObjects: one initial discovery scan, incremental `DescendantAdded`/ `DescendantRemoving` maintenance, and iteration only over matching candidates when hiding duplicates. Newly added duplicate HUDs are still hidden immediately when a blocking panel is open; removed instances are removed from the index. This does not change mobile layout or the visibility rules.

Validation: re-fetched the renderer and confirmed there is one initial PlayerGui discovery scan, incremental add/remove tracking, and no PlayerGui descendant scans inside visibility-sync callbacks. No Luau compiler or Studio runtime UI test was run.

### Navigation icon tint-target cache

- The full-menu renderer now indexes each native navigation icon's tintable Frames and UIStrokes once when the tab button is created.
- Tab changes update the cached parts directly instead of calling `GetDescendants()` on every icon during every render. The icon geometry is static after construction; badge and button styling remain independently updated.
- Static source verification confirms there is no icon descendant scan in `renderTab()` and one construction-time scan per icon. No Roblox Studio/runtime or device performance test is claimed.

### Menu typography target index

- `applyMenuTypography()` now builds its text-object target list with one initial panel scan, then maintains that list through `DescendantAdded` and `DescendantRemoving` signals.
- Repeated tab renders and desktop/mobile layout changes update the maintained text targets instead of traversing the entire panel hierarchy each time. Existing per-device text scaling, base-size attributes, font selection, and wrapping rules are preserved.
- Static source checks only; no Studio lifecycle, viewport-resize, or device regression test has been run.

### Menu typography no-op update guard

- Added a dirty/device/viewport guard around menu typography updates. When the text-object set, detected device class, and viewport width are unchanged, `applyMenuTypography()` returns without rewriting text properties.
- New text descendants mark the target list dirty; device or viewport-width changes force a fresh typography pass. Existing per-device scale, clamp, font, and wrapping calculations remain unchanged.
- This reduces redundant property writes during repeated menu/layout callbacks. Static source verification only; no Roblox Studio runtime or device profiling was performed.

### Hidden compact HUD visualizer guard

- The 30 FPS visualizer clock continues to accumulate active playback time, but the renderer now skips loudness queries and bar updates when the compact HUD is hidden and no expanded-menu visualizer/title animation needs work.
- Compact HUD bars update only while the local ScreenGui is enabled and the HUD is visible. Expanded-menu visualizer behavior and title animations remain independently gated by expanded state.
- This does not change the visualizer cadence or playback clock. Static source checks only; no Studio/runtime or device profiling was performed.


## Client diagnostics package installation alignment

The client diagnostics bootstrap previously existed as a source file but had no installer path that placed its required ModuleScript in the exact location it waits for. The bootstrap expects `ReplicatedStorage.ClubMusic_Client_Diagnostics_Service`, while the bootstrap itself belongs under `StarterPlayer/StarterPlayerScripts`. Added `ClubMusic_Client_Diagnostics_Installer.lua`, a dedicated Studio Command Bar installer pinned to the reviewed branch snapshot. It fetches both sources before changing instances, validates existing object classes, stages both instances, and retains the previous pair with `_Previous` suffixes for rollback. It does not add remotes, transmit diagnostics, or enable the Workspace effects inventory.

Validation: source-level review confirms the installer destination names match the bootstrap's direct ReplicatedStorage lookup and StarterPlayerScripts placement. The installer was not executed in Studio; no live place was changed. The diagnostics bootstrap still starts local sampling by default when installed, and the Workspace audit remains disabled unless explicitly requested.


### Performance compatibility follow-up — Studio audio installer snapshot and receipt module

- Audited `ClubMusic_Studio_CommandBar_Installer.lua` against the active controller's module resolution. The controller loads `ReceiptHash` only from `ServerStorage/ClubMusicSecurityCore/ReceiptHash`; the standalone root-level `ClubMusic_ReceiptHash.lua` has been retired and is absent from the reviewed tree.
- Updated all eleven audio/catalog/playlist/queue/validation source URLs to the same immutable branch snapshot (`b8ee084b4dc001b084e4b36c79f02031097cbe76`), verified each file exists at that commit, and removed the stale root-level receipt-hash install entry. The Security Core installer remains the sole installer for `ClubMusicSecurityCore.ReceiptHash` and `ReceiptTransactionService`.
- Corrected the installer inventory/count and stale playback-sync comment to reflect the local-only queue/playback architecture. Added a stopped-simulation guard and preflight class validation for all existing audio module destinations before any source replacement.
- Static checks only. The installer has not been executed in Studio; no live place was changed.


### Performance compatibility follow-up — ServerStorage RBXMX receipt module cleanup

- Audited `ClubMusic_ServerStorage_Modules.rbxmx` against the active Security Core receipt migration. Its five active catalog/playlist/queue/validation ModuleScripts exactly match their canonical root source files, including the generation-safe bounded `MusicValidationService` cache.
- Removed the obsolete embedded root-level `ClubMusic_ReceiptHash` ModuleScript from this legacy package. Receipt hashing now belongs only to `ServerStorage/ClubMusicSecurityCore/ReceiptHash`, installed with `ReceiptTransactionService` by the Security Core installer; the old package could otherwise reintroduce a retired duplicate.
- Verified the remaining package inventory contains exactly `MusicCatalogService`, `MusicPlaylistService`, `MusicQueueManager`, `MusicQueueManagerService`, and `MusicValidationService`. Audio client/server RBXMX ModuleScripts were also checked and exactly match their canonical `.luau` sources.
- `ClubMusic_Global_Optional_Services.rbxmx` still contains the dormant `MusicGlobalPlaybackAuthority` artifact; it was not removed because package consumers/installation use have not been fully established. Active playback sync remains retired in the controller, global service, renderer, and network layer.
- Static package/source comparison only. No Roblox model was imported into Studio and no live place was changed.


### Performance compatibility follow-up — Global Optional Services RBXMX audit

- Audited `ClubMusic_Global_Optional_Services.rbxmx` (blob `38ad38f092d942b720f3891be6f2414e00791b51`). Its five ModuleScripts are `ClubMusic_Global_Event_Log_Service`, `ClubMusic_Global_RateLimit_Service`, `ClubMusic_Global_Authorization_Service`, `ClubMusic_Global_SafeCall_Service`, and `MusicGlobalPlaybackAuthority`.
- The embedded SafeCall module exactly matches the canonical `ClubMusic_Global_SafeCall_Service.lua` source. The embedded `MusicGlobalPlaybackAuthority` exactly matches its root source file, but it has no active reference in the reviewed controller/global-service/network/installer path; it remains a dormant compatibility artifact and is not installed by the current audio installer.
- The active Global Service resolves Authorization, RateLimit, and EventLog through the version-pinned `ServerStorage/ClubMusicSecurityCore` exports first. The embedded standalone copies in this optional-services package are not the active source path; the Global Service's legacy consolidated-bundle fallback is a separate compatibility route. The package is not referenced by the current Studio Command Bar installer.
- No embedded module was removed: external Studio place hierarchies and manual package consumers have not been exhaustively enumerated, so deleting compatibility artifacts would be premature. No new cross-server playback, rate-limit, or diagnostics behavior was enabled.
- Legacy binary `.rbxm` assets (Audio Sound Count, Music Group, and Music Remote 1–5) cannot be decoded by the text-only repository fetch path. The tracked Kohl's Admin `.rbxmx` entry also returned an empty payload, so its model hierarchy/source cannot be certified from this repository snapshot. The separate Kohl's addon and hardening-patch Lua sources remain reviewable, but do not prove the imported third-party model contents.
- Static repository/source inspection only. No Roblox model was imported into Studio, no live place was changed, and no runtime/device tests were performed.


### Performance compatibility follow-up — Global Service lifecycle cleanup

- Audited the active Global Service optional-module loader and shutdown ownership. The split `ServerStorage/ClubMusicSecurityCore` path is preferred; a present-but-invalid split folder fails closed. The legacy consolidated Security Service fallback is attempted only when the split folder is absent, and its exported modules are validated before use. The consolidated fallback source contains no playback-authority or cross-server playback implementation; active playback sync remains retired.
- Found two instantiated services omitted from the script-destruction cleanup callback: the Global Config service owns a 30-second refresh task, and SecurityCore Authorization owns PlayerAdded/PlayerRemoving connections. Added both `globalConfigService` and `globalAuthorizationService` to the existing ConnectionJanitor-managed Stop list. The cleanup remains bound to `script.Destroying`; service methods are called under `pcall` by the existing cleanup loop.
- Re-fetched the changed Global Service and confirmed both services appear in the cleanup list alongside Audit, EventLog, SecurityMonitor, Idempotency, IncidentResponse, Diagnostics, ServerHealth, and Watchdog. No remotes, permissions, DataStore schemas, purchase paths, moderation rules, shared coordination, or playback behavior were changed.
- The remaining non-looping services (Maintenance, SecurityPolicy, MessageValidation, and EventLog facade) expose no-op Stop methods in the reviewed source; no extra cleanup behavior was necessary. Authorization is obtained through the SecurityCore shared instance and its Stop method disconnects owned player connections.
- Static source inspection only. No Luau compiler, Studio runtime, live place, or device test was used.


## Performance compatibility follow-up — optional startup failure isolation

The Global Service startup path now wraps each optional operational service `Start()` independently. A thrown startup error is bounded in the warning, triggers best-effort `Stop()` cleanup for partially initialized resources, marks that service unavailable in the local registry, and clears its active service reference. Later services and the shutdown janitor can still initialize. The SecurityCore Authorization startup retains its separate protected, fail-closed path. The diagnostics coordinator already uses protected delayed startup. Message validation remains fail-closed: if it cannot start, inbound cross-server envelopes are rejected. No purchase/receipt, moderation enforcement, permission, persistence schema, remote, or cross-server coordination behavior was weakened.

Static source review only; no Luau compiler, Roblox Studio runtime, live place, or device test was available. The change has not been installed or deployed.


## Performance compatibility follow-up — background task shutdown guard

The delayed diagnostics startup is now tracked and cancelled on script destruction, and its callback checks a shutdown flag before starting. Shutdown observation is connected even if the optional ConnectionJanitor module is unavailable. MessagingService retry loops and the durable moderation reconciliation loop now cooperatively stop when shutdown begins; reconciliation also checks the flag between player records. When the janitor is present, its existing cancellation/disconnection cleanup remains active. The moderation reconciliation interval, durable lookups, pending-state behavior, and ban enforcement are unchanged.

Static source review only; no Luau compiler, Roblox Studio runtime, live place, or device test was available. The change has not been installed or deployed.


## Performance compatibility follow-up — MessagingService subscription lifecycle

The Global Service now retains each active topic subscription in an explicit server-local connection registry in addition to the optional ConnectionJanitor. Script destruction disconnects every retained subscription even when the janitor module is unavailable. A subscription that completes after shutdown begins is immediately disconnected rather than being registered. Inbound callbacks return immediately once shutdown starts. Each topic supervisor checks the returned RBXScriptConnection's Connected state at a five-second interval and retries after a disconnect, instead of leaving a stale Active status indefinitely. The four existing allowlisted topics (announcements, moderation, XP boost, and catalog invalidation) and their envelope validation, replay suppression, and handlers are unchanged; no new topics or cross-server features were added.

Static source inspection only. No Luau compiler, Roblox Studio runtime, live place, or device test was performed; the change has not been installed or deployed.


## Performance compatibility follow-up — MessagingService publishing limits and delivery semantics

The Global Service publisher now JSON-encodes each outgoing envelope before calling MessagingService and rejects payloads that exceed a conservative 900-byte ceiling. The receiver's MessageValidation dependency uses the same effective ceiling: the lower of the existing shared security-policy `messageMaxBytes` setting and the 900-byte hard cap. This preserves administrator-configured lower limits while preventing a policy value from exceeding Roblox's documented 1 KiB MessagingService message limit. Encoding failures and oversize payloads are counted as publish failures and never sent.

Publish success means the backend accepted the publish call; it does not mean every subscribed server received or processed the message. Roblox documents delivery as best-effort and not guaranteed. The service does not blindly retry failed publishes: retrying can amplify throttling or duplicate side effects. Durable moderation state continues to reconcile on its existing 180-second loop; XP boost state is read by each controller on its existing staggered 45–60-second refresh. Catalog and track-moderation invalidation failures are now explicitly warned; track moderation remains durable, but other servers can retain a cached decision until their existing 300-second cache expires or an authoritative read refreshes it. Announcement publication remains best-effort and reports only whether the backend accepted the request.

No topic schema, message handler, durable write, receipt behavior, or authorization rule was changed. Static source inspection only; no Luau compiler, Roblox runtime, delivery test, or live deployment was performed.


## Track moderation and catalog invalidation reconciliation audit (2026-11-18)

- Confirmed that track-block decisions are stored durably in the shared GlobalControl DataStore under one key per validated track ID. Reads use the existing bounded server-local DataStore budget; no global scan/index exists or is needed.
- Confirmed that each server caches per-track moderation decisions for up to 300 seconds. The publisher already sends track moderation updates on the existing Catalog MessagingService topic with `trackId` and `blocked`; however, the receiver previously treated every Catalog message as a generic catalog refresh and ignored those fields. The local GlobalEvent path only updates the publishing server, so remote servers could retain stale decisions until cache expiry.
- Updated the controller's existing Catalog message handler to validate optional track IDs and boolean moderation state, refresh the receiving server's local decision cache, and immediately remove blocked tracks from its local request queue / current playback. Unblock invalidations update the cache without queue mutation. Self-originated messages do not repeat local moderation work.
- Generic custom-catalog refresh behavior and its existing jittered 180–210 second reconciliation remain unchanged. This is the bounded fallback for missed catalog invalidations; it refreshes the existing single catalog key through the existing DataStore budget gate and preserves last-known-good data on failures.
- No new MessagingService topics, DataStores, MemoryStore keys, remotes, diagnostics telemetry, global queue state, or cross-server diagnostics were introduced. Durable writes and authorization remain unchanged.
- Static source inspection only. MessagingService delivery, DataStore behavior, moderation propagation latency, Luau compilation, Studio/runtime behavior, and deployment were not tested.


## Durable global moderation reconciliation audit (2026-11-18)

- Confirmed that moderation changes use per-user durable DataStore keys and `UpdateAsync`, preserving the other enforcement flag and bounded history. MessagingService is only the fast notification path; successful durable writes remain authoritative even if publishing fails.
- Join checks read ban and request-block state together. Failed or unavailable reads remain unknown, not unbanned: the controller restricts moderation-sensitive actions, marks `GlobalModerationPending`, and retries with bounded exponential backoff. A verified global ban kicks; a failed read alone never kicks.
- The server-local reconciliation loop checks every currently online player against the durable record every 180 seconds, with 1.1-second pacing between reads. A failed read keeps the player pending/restricted; a successful read applies the durable ban and request-block state. The loop does not enumerate DataStore keys or depend on MessagingService delivery.
- Found and fixed a fail-open schema edge case: a successful read containing a non-table value or non-boolean `globalBan` / `requestBlocked` field was previously treated as an empty, unblocked record. Now only a missing key (`nil`) is a valid empty record; malformed records return `lookupFailed`, preserving the fail-closed pending behavior without kicking on data corruption.
- Existing per-server DataStore token-bucket protection remains in place (20-token burst, 5-token/second refill, further shared with this server's other DataStore operations). Reconciliation is paced at 1.1 seconds per player; no new shared budget, MemoryStore, DataStore, MessagingService topic, remote, or diagnostics telemetry was added.
- No changes to moderation authorization, write semantics, ban enforcement, request-block enforcement, player profile persistence, or client trust boundaries.
- Static source inspection only. DataStore fault injection, MessagingService delivery, multi-server propagation, Luau compilation, Studio/runtime behavior, and deployment were not tested.


## Durable moderation write integrity and concurrency audit (2026-11-18)

- Audited the per-user moderation `UpdateAsync` transform and confirmed it modifies only the requested enforcement field on the latest record supplied to the transform. Concurrent changes to `globalBan` and `requestBlocked` therefore merge against the latest stored value rather than a stale pre-read snapshot; same-field concurrent changes retain normal last-successful-write semantics.
- Confirmed that authorization and reason validation occur before the durable write, and replay logging, MessagingService publishing, and local event dispatch occur only after `UpdateAsync` succeeds. No external side effects occur inside the retryable transform callback.
- Found and fixed a corruption edge case: a non-table record or non-boolean enforcement flag now aborts the update instead of being replaced by an empty record, which could otherwise clear the other moderation flag. A cancelled/failed update returns failure and does not publish a success notification.
- Moderation history is rebuilt as a compact array of at most 20 validated entries. Malformed history members and non-array keys are ignored; accepted entries retain only the allowlisted field, boolean value, positive integer actor ID, bounded reason text, and finite timestamp. The new entry is prepended, preserving the existing newest-first history behavior and cap.
- Internal update arguments now independently require an allowlisted field, boolean value, and positive integer actor ID. Existing BindableFunction authorization and admin-only `GetModerationHistory` access remain unchanged.
- Static source checks only. No Luau compilation, DataStore concurrency/fault-injection tests, Roblox Studio/runtime test, or deployment was performed.


## Moderation record size and write-budget audit (2026-11-18)

- Confirmed the moderation record is keyed by validated user ID and uses one `UpdateAsync` per accepted moderation action. Reads and writes share the existing bounded server-local DataStore token bucket; its effective cap is 20 tokens with a 5-token/second refill (the generic caller capacities are clamped to the configured fallback ceiling). No additional DataStore read, retry loop, or shared budget service was added.
- Tightened the write transform to persist only the documented moderation schema: `globalBan`, `requestBlocked`, `updatedAt`, `updatedBy`, `reason`, and the bounded `history` array. This avoids carrying arbitrary unknown keys forward and prevents unrelated legacy/corrupt metadata from inflating every subsequent record write.
- The two enforcement flags are copied from the latest `UpdateAsync` value after schema validation, then only the requested flag is changed. The history remains capped at 20 compact, validated entries with reasons truncated to the configured 120-character limit. This gives the record a predictable small upper bound rather than allowing unbounded history or arbitrary nested metadata.
- Failed local budget admission rejects before the DataStore call. A failed/cancelled `UpdateAsync` does not emit replay records, publish notifications, or fire the local moderation event. Durable state remains authoritative; MessagingService remains best-effort and periodic reconciliation remains the recovery path.
- Static source checks only. No live DataStore request-budget measurements, repeated-write load test, concurrency/fault injection, Luau compilation, Studio/runtime test, or deployment was performed.


## Moderation reconciliation budget isolation (2026-11-18)

- Audited all consumers of the shared `all:datastore` server-local token bucket. Join-time moderation, moderation writes/history, track moderation, configuration/state and XP receipt operations continue to share one aggregate budget; no independent bucket or multiplied request allowance was introduced.
- Found that background online-player reconciliation used the same unrestricted token admission as foreground operations. Although its 1.1-second per-player pacing is below the bucket's 5-request/second refill, a large initial burst could consume tokens needed by foreground work.
- Added an optional minimum-remaining-token floor to the existing local bucket admission path. Reconciliation reads alone request a three-token floor; they are deferred when spending would cross that floor. Foreground callers retain the existing behavior and can use the reserve when necessary. The bucket capacity, refill ceiling, key, and total aggregate budget remain unchanged.
- Reconciliation remains fail-closed on budget exhaustion: the player stays `GlobalModerationPending` and no kick occurs solely due to an unavailable read. The next scheduled reconciliation cycle retries. Join-time reads and moderation/purchase operations do not inherit the background reserve restriction.
- Static source checks only. No measured DataStore budgets, large-player-count load test, Roblox runtime test, Luau compilation, or deployment was performed.


## Moderation reconciliation retry scheduling (2026-11-18)

- Audited join-time retries and periodic online-player reconciliation. Join-time controller checks already use one combined authoritative moderation read and bounded exponential retry; verified state is not treated as a ban when a read fails.
- Found that a player whose previously verified state became unavailable during the periodic sweep was marked pending but could wait for the next full 180-second interval (plus scan duration) before the next background retry.
- Changed the existing server-local reconciliation worker to run a pending-only follow-up sweep 15 seconds after a sweep encounters read failures. The follow-up checks only players still marked `GlobalModerationPending`; verified players are skipped. If any pending reads still fail, another pending-only sweep follows after 15 seconds. Once pending players are resolved, the worker returns to the normal full sweep interval.
- The worker remains sequential and keeps the 1.1-second inter-read pacing and three-token shared DataStore reserve. It adds no per-player retry threads, no request burst, no additional budget bucket, and no cross-server state. Failure continues to restrict moderation-sensitive actions without kicking solely on lookup failure.
- Static source checks only; no high-player-count simulation, backend outage/fault injection, Luau compilation, Studio runtime test, or deployment.


## Join-time moderation retry and duplicate initialization audit (2026-11-18)

- Audited the controller's `PlayerAdded` handler and startup `Players:GetPlayers()` sweep. Because the event connection is established before the startup sweep, a joining player can be observed by both paths. Added a per-Player-instance idempotency guard at `onJoin` entry and release it on `PlayerRemoving`, preventing duplicate profile/join initialization and duplicate moderation retry workers for the same live Player object.
- Join-time moderation retries remain one worker per Player, stop when the Player leaves, and retain the existing bounded exponential schedule (1, 2, 4, 8, then at most 15 seconds). Added stable per-user staggering to the retry delay, capped at 15 seconds, to reduce synchronized retry bursts when multiple players join during a DataStore outage.
- Confirmed the existing departure cleanup removes `blockedUsers` and other per-user request state. The retry worker still exits after its next wake if the Player has left; no new persistent worker registry or cross-server state was added.
- Security semantics unchanged: unresolved moderation remains request-restricted, only a successful authoritative lookup can clear pending state, and only a confirmed global ban can kick.
- Static source checks only. No concurrency simulation, high-player-count test, DataStore outage injection, Luau compilation, Studio runtime test, or deployment.


## Moderation transition ordering and stale-event protection (2026-11-18)

- Found a race between join-time moderation retries and cross-server moderation notifications: a yielding GetModerationState lookup could return an older record after a newer unblock/block notification had already updated local state. The retry could then overwrite the newer local restriction decision. The same unversioned event path could also process a delayed older global-ban notification after a newer unban.
- Added a monotonic per-user moderation revision to the existing durable moderation record. Each successful UpdateAsync increments it; legacy valid records without a revision are treated as revision zero. Malformed revision values fail closed. The existing GetModerationState BindableFunction returns the revision as an additional trailing value, and existing moderation notifications carry the same committed revision.
- The controller tracks only the latest revision observed for each online user. Incoming moderation notifications are applied only when their revision is strictly newer; delayed/out-of-order events are ignored. Join-time and retry lookups are also rejected as stale when their returned revision is older than a notification observed while the lookup yielded. Stale results leave the player restricted/pending until a sufficiently current durable read succeeds.
- Global-ban notifications now require the same valid revision ordering, including explicit globalBan=false events advancing the revision without enforcement. Request-block events still purge queued requests on block and clear the local block on unblock. Per-user revision state is released on PlayerRemoving.
- No new remote, DataStore, MemoryStore, MessagingService topic, cross-server diagnostics, client telemetry, or enforcement authority was added. The revision is part of the existing durable moderation record and existing notification/API contracts only.
- Static source inspection only. No Luau compilation, DataStore concurrency/fault-injection, MessagingService ordering test, Studio/runtime test, or deployment was performed.


## Moderation reconciliation revision ordering and MessagingService forwarding (2026-11-18)

- Follow-up audit found the first revision rollout had not carried the revision through the inbound MessagingService moderation handler. The handler now validates a positive integer revision and forwards it with the existing moderation event, allowing remote controllers to apply only strictly newer updates.
- Found that the periodic durable reconciliation worker directly cleared GlobalModerationPending and kicked on the basis of a yielding GetAsync result, before checking whether a newer moderation notification had arrived. It also emitted an unversioned requestBlocked-only event that the revision-aware controller could not use.
- Replaced that direct mutation with one local ModerationReconcile snapshot containing both durable enforcement flags and the record revision. The controller applies the snapshot only for the currently online player and only when its revision is equal to or newer than the latest observed revision. A current snapshot enforces a confirmed global ban, otherwise repairs request-block state and clears pending. An older snapshot has no effect.
- Failed DataStore reads still mark pending and trigger the existing pending-only retry sweep; no kick occurs from a failed read. Existing 1.1-second pacing, three-token reserve, 180-second full sweep and 15-second pending retry remain unchanged.
- No new remote, DataStore, MemoryStore, MessagingService topic, diagnostics aggregation, or client telemetry was added. Static source inspection only; no Luau compilation, backend fault injection, multi-server ordering test, Studio/runtime test, or deployment.
