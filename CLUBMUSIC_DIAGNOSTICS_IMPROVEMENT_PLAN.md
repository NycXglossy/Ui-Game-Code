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
   - `ClubMusic_Global_Service_server_1.lua` wires the registry, ServerHealth, Watchdog, and ErrorHistory into the existing ServerStorage BindableFunction snapshot.
   - `UI_Server_Controller_server (1).lua` reports server-side AutoDJ, queue, playback, moderation, and recovery progress and displays local health, registry, watchdog, memory, and aggregate error-history counts to authorized staff; detailed records remain server-side.
   - No client-facing diagnostic remote was added.

## ServerStorage installation

Create these ModuleScripts directly under ServerStorage using the matching repository source:

- `ClubMusic_Global_Diagnostics_Service`
- `ClubMusic_Local_Service_Registry`
- `ClubMusic_Server_Health_Service`
- `ClubMusic_Local_Watchdog_Service`
- `ClubMusicErrorHandler`

Keep the existing Global Service Script and UI Server Controller Script as single instances. Do not add a second queue controller or playback owner.

The new registry, ServerHealth, and Watchdog modules are optional-load guarded. If one is absent or fails to load, the service continues to start and the snapshot reports its status rather than crashing ClubMusic startup.

## Remaining plan

7. Add separate, opt-in ClientDiagnostics for FPS, client memory, ping, and frame spikes. Keep client telemetry isolated from server health and do not expose server error history.
8. Audit and retire obsolete diagnostic code only after every consumer has migrated and Studio tests pass.

## Runtime verification still required

Static repository checks do not prove Roblox runtime behavior. In Studio and a dedicated published test server, verify:

- Diagnostics status and snapshot calls remain read-only.
- Registry reports installed/missing optional services correctly.
- Heartbeat and memory samples update without unbounded table growth.
- Playback, AutoDJ, and Queue pulses remain fresh during long tracks and paused playback.
- An intentional missing AutoDJ pulse reports stale progress but performs no recovery action.
- Error deduplication increments repeat counts while record and key caps remain bounded.
- Authorized admin diagnostics show local metrics and metadata only.
- No diagnostic information is sent to clients or stored/shared across servers.
