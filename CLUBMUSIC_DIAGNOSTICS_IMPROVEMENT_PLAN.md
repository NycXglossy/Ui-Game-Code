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
- Found a confirmed return-contract mismatch: `GetGlobalAudit` returns its entries directly, while the Kohl's/admin bridge helper requires the first provider return to be `true`. The `OperationalSecurityLog` path can therefore reject a successful audit read. This is documented for a narrow compatibility fix; provider behavior is not changed in this audit commit.
- Verified that the Global Service source has 45 unique BindableFunction registrations, but only 42 are unconditional; the three SafeCall-related functions depend on optional module availability.
- The repository fetch for the Kohl's Admin export returned empty content, so that embedded package remains unverified. The separate adapter source is still the supported inspection boundary.
- Added a Studio compatibility test matrix covering startup order, late API discovery, event replacement, optional SafeCall availability, and the audit return-shape mismatch.

**Next implementation task:** fix the `GetGlobalAudit` consumer contract without changing the provider's existing return shape, then run static contract checks before Studio verification. No runtime test is claimed.
