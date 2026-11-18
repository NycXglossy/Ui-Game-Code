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

Client-side performance measurements are untrusted and must not be sent to the server or used for authorization. Essential server validation, authorization, purchase processing, moderation enforcement, and security-event recording must never be throttled by adaptive load.

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
