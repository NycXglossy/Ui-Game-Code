# ClubMusic Diagnostics Improvement Plan

## Non-negotiable boundaries

Diagnostics are server-local and observational.

- No diagnostic DataStore or MemoryStore writes.
- No diagnostic MessagingService heartbeat, peer registry, or cross-server aggregation.
- No kicks, bans, restarts, retries, queue repairs, or playback control from diagnostics.
- No client RemoteFunction/RemoteEvent exposing server errors, tracebacks, or private service state.
- Client-side measurements, when added, are untrusted telemetry and never authorize or control server behavior.
- SecurityCore remains independent. Diagnostics may observe SecurityCore status but cannot change its policy or enforcement.

Existing cross-server ClubMusic features remain separate; diagnostics reports only the current server's view of their availability.

## Implemented repository changes

1. **Diagnostics coordinator** — `ClubMusic_Global_Diagnostics_Service.lua`
   - Preserves `GetGlobalHealth`, `GetGlobalMetrics`, and `GetGlobalDiagnostics`.
   - Uses protected optional status reads and distinguishes `NotInstalled` from failed/unavailable probes.
   - Preserves the legacy structured metric counters and adds numeric `aggregate.counters` for the admin command.
   - Returns local service registry, ServerHealth, Watchdog, ErrorHistory, and bounded recent errors.
   - Corrects the previous unconditional queue-module check: the separate queue ModuleScript is validated only when explicitly configured.

2. **Local Service Registry** — `ClubMusic_Local_Service_Registry.lua`
   - Bounded to 64 entries.
   - Tracks local service interfaces and required/optional status.
   - Reports availability and missing methods without starting, stopping, or repairing services.

3. **ServerHealth** — `ClubMusic_Server_Health_Service.lua`
   - Measures server Heartbeat timing using bounded rolling one-second buckets.
   - Samples process memory locally every 30 seconds.
   - Reports sustained severe frame delays.
   - Does not apply an arbitrary memory warning threshold by default; memory is reported with sample age.

4. **Observational Watchdog** — `ClubMusic_Local_Watchdog_Service.lua`
   - Receives local progress pulses for Playback, AutoDJ, Queue, Moderation, and Recovery.
   - Detects missing/stale expected progress and explicitly unhealthy reports.
   - Does not execute any corrective action.

5. **ErrorHistory** — `ClubMusicErrorHandler.lua`
   - Retains a maximum of 50 records and 100 recent deduplication keys.
   - Aggregates repeated errors, timestamps records, and exposes local status counters.
   - Keeps detailed messages and tracebacks server-side; the client-facing admin view receives aggregate counts only.

6. **Global Service and trusted admin integration**
   - `ClubMusic_Global_Service_server_1.lua` wires the registry, ServerHealth, Watchdog, ErrorHistory, and read-only SecurityCore status providers into the existing ServerStorage BindableFunction snapshot.
   - `UI_Server_Controller_server (1).lua` reports server-side AutoDJ, queue, playback, moderation, and recovery progress and displays local health, registry, watchdog, memory, aggregate error-history counts, and SecurityCore component health to authorized staff; detailed records remain server-side.
   - The coordinator reports Local, CrossServer, Performance, and Watchdog dimensions while keeping diagnostics local-only.
   - Snapshot copying is depth/size bounded, optional missing probes remain distinguishable from explicit degraded states, and health availability is no longer hard-coded.
   - `ClubMusic_Global_SafeCall_Service.lua` now bounds warning-deduplication keys to 100 with 120-second expiry and validates callbacks.
   - No client-facing diagnostic remote was added.

7. **Opt-in ClientDiagnostics** — `ClubMusic_Client_Diagnostics_Service.lua`
   - Client-local rolling FPS/frame-time and frame-spike observations.
   - Protected client memory sampling every 15 seconds and ping sampling every 5 seconds.
   - Explicit `Start()` opt-in; `Stop()` disconnects and cancels sampling.
   - Reports are marked `ClientLocalUntrusted`, remain on the client, and are never transmitted to the server.
   - The component does not receive server health, server errors, tracebacks, or private authorization data.

## ServerStorage installation

Create these ModuleScripts directly under ServerStorage using the matching repository source:

- `ClubMusic_Global_Diagnostics_Service`
- `ClubMusic_Local_Service_Registry`
- `ClubMusic_Server_Health_Service`
- `ClubMusic_Local_Watchdog_Service`
- `ClubMusicErrorHandler`

Keep the existing Global Service Script and UI Server Controller Script as single instances. Do not add a second queue controller or playback owner.

The new registry, ServerHealth, and Watchdog modules are optional-load guarded. If one is absent or fails to load, the service continues to start and the snapshot reports its status rather than crashing ClubMusic startup.

## ClientDiagnostics installation

Place `ClubMusic_Client_Diagnostics_Service.lua` as a ModuleScript named `ClubMusic_Client_Diagnostics_Service` under ReplicatedStorage. It does not start automatically. A trusted LocalScript may opt in:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Diagnostics = require(ReplicatedStorage:WaitForChild("ClubMusic_Client_Diagnostics_Service"))
local clientDiagnostics = Diagnostics.new()
clientDiagnostics:Start()

-- Read local-only, untrusted measurements when needed:
local snapshot = clientDiagnostics:GetStatus()

-- Stop when the owning UI/session no longer needs measurements:
-- clientDiagnostics:Stop()
```

The returned snapshot stays on the client. Do not forward it to server authorization, enforcement, or SecurityCore decisions.

## Remaining plan

8. Audit and retire obsolete diagnostic code only after every consumer has migrated and Studio tests pass. Preserve existing public BindableFunction names and legacy structured metric counters during the transition.


## Phase 14 integration update (2026-11-16)

The existing diagnostics stack was already substantially implemented but was not yet consolidated with the newer Phase 12/13 security services. Phase 14 now:

- Adds AdaptiveSecurityLoadManager status to the existing server-local diagnostics snapshot and operational status.
- Adds SecurityReplay status counters through its dedicated read-only ServerStorage BindableFunction; replay event contents remain outside health snapshots.
- Adds SafeCall call/failure/recovery counters without exposing detailed errors or tracebacks to clients.
- Adds a bounded `observabilityHealth` summary across Diagnostics, ServiceRegistry, ServerHealth, Watchdog, AdaptiveLoad, SecurityReplay, SafeCall, and ErrorHistory.
- Extends the existing authorized staff OperationalDiagnostics output with adaptive-load mode, replay retention/capacity, and SafeCall counters.

No diagnostic services were replaced or retired. SafeCall and ErrorHistory remain separate pending a complete consumer/semantics audit. Existing Global API names and aggregate metrics are preserved.

**Still unfinished:** the consumer sweep across dynamic calls and packaged/embedded assets; watchdog pulse acceptance tests; reconciliation of prior degraded watchdog/detail-registry/memory warnings against fresh runtime output; Studio and published-server verification; and performance profiling. Do not retire obsolete diagnostics code until those gates pass.

## Runtime verification still required

Static repository checks do not prove Roblox runtime behavior. In Studio and a dedicated published test server, verify:

- Diagnostics status and snapshot calls remain read-only.
- Registry reports installed/missing optional services correctly.
- Heartbeat and memory samples update without unbounded table growth.
- Playback, AutoDJ, and Queue pulses remain fresh during long tracks and paused playback.
- An intentional missing AutoDJ pulse reports stale progress but performs no recovery action.
- Error deduplication increments repeat counts while record and key caps remain bounded.
- Authorized admin diagnostics show local metrics, SecurityCore health states, and metadata only.
- ClientDiagnostics remains stopped unless a local client script explicitly opts in; FPS, memory, ping, and frame-spike measurements stay client-local.
- No server diagnostic information is sent to clients or stored/shared across servers.


## Compatibility audit progress

The first static Global API compatibility pass is documented in `CLUBMUSIC_GLOBAL_API_DIAGNOSTICS_AUDIT.md`.

- Confirmed 45 unique BindableFunction registrations in source plus the `GlobalEvent` BindableEvent; three SafeCall-related functions are conditional on the optional SafeCall module.
- Confirmed UI Server Controller consumers for `GetGlobalHealth`, `GetGlobalMetrics`, `GetGlobalDiagnostics`, `GetGlobalOperationalStatus`, and `RecordLocalWatchdogPulse`.
- Preserved all API names and the existing structured/aggregate metrics contract.
- Identified SafeCall and ErrorHistory as overlapping but distinct stores; neither is retired or merged in this pass.
- Identified the packaged SafeCall ModuleScript copy in `ClubMusic_Global_Optional_Services.rbxmx`; keep it synchronized with the standalone module until the Studio deployment source is confirmed.
- Confirmed ClientDiagnostics remains opt-in and isolated from server health and enforcement.

This is a static compatibility pass, not proof that every consumer in all embedded assets has been found. The remaining sweep must cover dynamic invocations, packaged third-party models, and Studio installer behavior. No runtime verification has been performed.


### Second compatibility pass (2026-11-16)

- Traced the UI Server Controller's dynamic `globalInvoke` bridge and its late-folder/event discovery logic.
- Compared the explicitly invoked Global API names with provider-side signatures.
- Fixed the `GetGlobalAudit` consumer mismatch in `UI_Server_Controller_server (1).lua`: the admin bridge now normalizes that one read-only list getter at the consumer boundary. The Global Service provider return contract remains unchanged.
- Verified that the Global Service source has 45 unique BindableFunction registrations, but only 42 are unconditional; the three SafeCall-related functions depend on optional module availability.
- The repository fetch for the Kohl's Admin export returned empty content, so that embedded package remains unverified. The separate adapter source is still the supported inspection boundary.
- Added a Studio compatibility test matrix covering startup order, late API discovery, event replacement, optional SafeCall availability, and the audit return-shape mismatch.

**Next verification task:** run static contract checks and Studio tests for `OperationalSecurityLog` with populated, empty, and unavailable audit results. No runtime test is claimed.


## Diagnostics exposure audit update (2026-11-16)

- Completed a static, controller-scoped review of the UI Server Controller's client remotes.
- Confirmed the controller's client-facing read functions return player state, catalog, or playlist data; the Global Diagnostics and SafeCall recent-record APIs remain on the server-only BindableFunction path in the inspected source.
- Confirmed PurchaseDiagnostic is bounded, rate-limited client telemetry and is explicitly not proof of a completed purchase.
- Confirmed RequestAction remains a multiplexed security boundary and still needs action-by-action review. This is not a full repository remote audit.
- No runtime or exploit-client verification has been performed. Keep the diagnostics exposure work in static-audit status until Studio tests confirm no diagnostic records or tracebacks are exposed.


## RequestAction security audit update (2026-11-16)

- Completed a static action-by-action review of the UI controller's multiplexed RequestAction handler.
- Documented shared payload bounds, action allowlist, per-player/server budgets, and the authorization/validation checks for request, catalog, playlist, DJ, moderation, membership-reward, daily-reward, and title actions.
- Confirmed DJ booth controls are owner/co-owner gated; moderation is admin gated with target hierarchy checks; membership rank rewards are owner-only.
- Follow-up: verify SecurityCore level-1 mapping remains rank 150+ (not DJ rank 100), and test all privileged action groups in Studio across the staff hierarchy.
- No runtime or exploit-client tests have been performed. This remains a static audit, not a repository-wide remote certification.


## SecurityCore and utility remote update (2026-11-16)

- Corrected the authorization rank mapping: rank 100 DJ is no longer general staff; rank 150 Moderator maps to level 1; Admin/Co-owner/Owner remain levels 2/3/4.
- Kept GlobalDJ as a narrow rank-100+ permission without elevating DJ to staff.
- Updated the Security Core installer to fetch the corrected Authorization module.
- Added a live-player guard to the UtilityBar RemoteFunction.
- Audited UtilityBar pass gates and Tiki Tide Settings entitlement, teleport consent, gravity, announcement, text-filtering, and cooldown checks.
- Remaining: trace actual DJ Booth access/control-mode toggle and test the new mapping in Studio. No runtime test is claimed.


## Limited DJ Control Mode implementation (2026-11-16)

- Rank 100+ DJs may toggle Control Mode and use skip, pause/resume, and restart.
- Playlist rotation, queue reorder/removal, and queue clearing remain Owner/Co-owner only.
- Added separate `canUseDJBooth` and `canManageDJBooth` player-state flags.
- Follow-up: inspect client renderer visibility conditions and test rank 100/150/200/254/255 in Studio. Runtime verification not yet performed.


### Client UI follow-up completed (static)

The renderer now uses the server-projected DJ permissions instead of assuming DJs are staff. Rank-100 DJs see local playback and Control Mode actions; queue mutation and playlist-management controls remain Owner/Co-owner only. This is a static source update only; Studio and published-server testing remain outstanding.


## Sixth-pass remote-boundary audit (2026-11-16)

Static review extended the diagnostics/security boundary across the Global Service BindableFunction API, UtilityBar RemoteFunction, and Tiki Tide Settings Request/Broadcast remotes.

- Global Service privileged writes use SecurityCore actor authorization and fail closed when Authorization is unavailable. Cross-server messages require the dedicated MessageValidation service and use bounded local message-ID deduplication.
- Diagnostics snapshots and SafeCall recent records remain server-only BindableFunctions; the inspected source does not add a client-facing diagnostics remote. Keep the UI controller's client projection aggregate-only.
- UtilityBar validates live players, action allowlists, server-owned entitlement attributes, bounded size values, and per-player cooldowns. Size pass enforcement remains pending a configured real pass ID and server-owned entitlement.
- Tiki Tide Settings validates live player/action/payload shape, entitlement, per-player cooldown, teleport consent, finite/clamped gravity, SecurityCore privileges, and reauthorizes after TextService filtering yields.
- No new client-reachable authorization bypass was identified in the inspected handlers.

**Static-audit boundary:** this is a wider scoped review, not proof that every embedded model, installer, third-party package, or remote in the repository has been enumerated. GitHub code search did not provide an indexed remote inventory for the working branch. Kohl's Admin internals remain out of scope; maintain the separate adapter only.

**Still required before sign-off:** Studio and published-server tests for malformed/oversized payloads, remote spam, authorization-cache expiry/unavailability, permission revocation during yielding operations, replay/invalid cross-server messages, and attempts by ordinary clients to access diagnostics. Legacy diagnostic code must not be retired until all consumers are migrated and runtime tests pass.


## Seventh-pass text-source inventory and release gate (2026-11-16)

- Enumerated the current branch tree and reviewed text-based Lua/Luau remote declarations and handlers across ClubMusic, Tiki Tide Settings, UtilityBar, and the legacy music script.
- Added live-player and post-yield connection checks to the avatar-refresh RemoteFunction.
- Added live-player validation and a 0.5-second per-player cooldown to the read-only ToolShop query RemoteFunction.
- Confirmed that Tiki Tide Settings Broadcast is server-to-client only in the inspected service.
- Confirmed from `CLUBMUSIC_MUSIC_INTEGRATION_2026-11-08.md` that the standalone legacy `Music System` and its `MusicRemotes` transport are reference-only, not runtime dependencies, and must not be installed alongside the secured controller. The current controller owns the migrated behavior. The live place should be checked for conformance, but the source file's presence in GitHub is not evidence of active deployment.
- Found the five manager source files in the current repository. They are adapters/helpers and do not prove that the old controller's queue/playback/skip/playlist state has been migrated. The Phase 0 audit has been updated to reflect the actual source availability and integration boundary.
- Added `CLUBMUSIC_DIAGNOSTICS_MASTER_RELEASE_REGISTER.md` as the single current record of implementation, remote inventory, exclusions, runtime tests, and release criteria.

### Remaining release blockers

1. Run the full Studio and published-server verification matrix in the master release register. These tests cannot be completed from GitHub source alone.
2. Confirm the live Roblox place follows the secured integration guide and does not contain a separately installed legacy `Music System` / `MusicRemotes` transport.
3. Review binary `.rbxm`/`.rbxmx` assets and embedded third-party packages, or explicitly keep them excluded from this scoped audit. Kohl's Admin internals remain out of scope; review only the separate adapter.
4. Confirm the exact branch commit installed in the test place before any production rollout.

**Release status:** Static text-source work is updated; runtime and live-place verification are pending. Do not install or call the diagnostics/security update production-ready until the blockers above are closed.


## Final source-level diagnostics closure pass (2026-11-16)

- Synchronized the embedded SafeCall ModuleScript in `ClubMusic_Global_Optional_Services.rbxmx` with the standalone bounded implementation (50 records; 100 warning keys; 120-second warning-key expiry).
- Bounded watchdog pulse metadata to 8 primitive fields; keys are short and validated, strings are capped at 140 characters, and numbers must be finite and within ±1,000,000,000.
- Completed the source-level pulse cadence review: Playback every second (including paused/reload states); Queue and AutoDJ every 30 seconds and on refill; Recovery event-driven/optional while idle; Moderation optional/event-driven. Stale windows are 12 seconds for Playback and 900 seconds for Queue/AutoDJ.
- Confirmed SafeCall and ErrorHistory have distinct consumers and semantics; keep both rather than merging them.

Source integration and the scoped in-repository text audit are complete. Runtime acceptance, historical warning reconciliation, performance profiling, full binary/third-party package review, and live-place verification remain open. No legacy diagnostics code is retired.
