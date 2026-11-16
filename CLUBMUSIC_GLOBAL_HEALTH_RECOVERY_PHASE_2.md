# ClubMusic Global Health and Recovery — Phase 2

## Scope

Adds a read-only, server-side diagnostics snapshot to the existing global service. It combines the current health state, recovery state, and the latest bounded error-handler records into one query.

This phase does not add another queue controller, playback owner, persistent logging store, client-facing remote, or automatic queue repair.

## Changed files

- `ClubMusic_Global_Service_server_1.lua` — registers the `GetGlobalDiagnostics` BindableFunction.

## Installation

1. Replace the existing `ClubMusic_Global_Service_server_1` Script in ServerScriptService with the updated source.
2. Keep the existing `ClubMusic_Global_Health_Service`, `ClubMusic_Global_Recovery_Service`, `ClubMusicErrorHandler`, and `MusicGlobalQueueService` ModuleScripts in ServerStorage.
3. Do not create a second global service Script or another copy of any existing module.
4. Keep `EnableInStudio = false` unless intentionally testing cross-server behavior in a dedicated test universe.

No new Explorer instances are required for Phase 2.

## API

The existing `ServerStorage.ClubMusicGlobalAPI` folder now exposes a `GetGlobalDiagnostics` BindableFunction.

Trusted server scripts can query it:

```lua
local ServerStorage = game:GetService("ServerStorage")
local api = ServerStorage:WaitForChild("ClubMusicGlobalAPI")
local getDiagnostics = api:WaitForChild("GetGlobalDiagnostics")

local ok, diagnostics = getDiagnostics:Invoke()
if ok and diagnostics then
    print("Global service enabled:", diagnostics.serviceEnabled)
    print("Health available:", diagnostics.healthAvailable)
    print("Recovery available:", diagnostics.recoveryAvailable)
    print("Error history available:", diagnostics.errorHistoryAvailable)
end
```

The returned snapshot contains:

- `generatedAt` — snapshot timestamp.
- `serviceEnabled` — whether cross-server operation is enabled in this server.
- `healthAvailable` and `health` — current health monitor status, if loaded.
- `recoveryAvailable` and `recovery` — current recovery coordinator status, if loaded.
- `errorHistoryAvailable` — whether the optional error handler supplied history.
- `recentErrors` — at most the latest 20 records from the existing per-server bounded error history.

The existing `GetGlobalHealth` BindableFunction remains unchanged.

## Safety and performance

- The diagnostics call is read-only and performs no DataStore, MemoryStore, or MessagingService operation.
- It does not start retries, trigger recovery, change health state, mutate the queue, or affect playback.
- It is a BindableFunction under ServerStorage, not a RemoteFunction; it is intended for trusted server scripts, not clients.
- The response is a point-in-time snapshot. Health and recovery may change immediately after it is returned.
- Error history remains local to the current server process. This phase does not provide cross-server aggregation or durable history.
- The server-side snapshot includes error details and tracebacks for trusted server scripts only. Client-facing admin output must use aggregate counts and must never forward error records or tracebacks.

## Verification

Static source verification confirms:

- `GetGlobalHealth` remains registered.
- `GetGlobalDiagnostics` is registered on the existing API folder.
- Health and recovery status are read through protected calls.
- Recent error records are copied and capped at 20.
- The diagnostics callback contains no storage calls or state mutation.

No Roblox Studio runtime or live multi-server test was run by the assistant. In a dedicated test server, invoke the BindableFunction from a temporary trusted server Script and confirm that it returns health/recovery data without changing queue or playback state.


## Local-only diagnostics boundary

Diagnostics are intentionally scoped to the current Roblox server process.

- No diagnostic heartbeat is published through MessagingService.
- No peer-server presence, health, metrics, or error history is collected.
- No diagnostic data is stored in DataStore or MemoryStore.
- Diagnostics do not issue kicks, restarts, queue repairs, or other control actions.
- No diagnostic details or server error records are exposed through client remotes.
- Existing cross-server features (such as moderation notifications and shared configuration) continue to operate independently; diagnostics only report the local server's view of their status.

The current GetGlobalDiagnostics snapshot remains a trusted server-to-server-script BindableFunction under ServerStorage. It is read-only and returns a point-in-time view.

## Follow-on diagnostics improvements

The next implementation stages are:

1. Harden and consolidate the diagnostics coordinator and preserve existing query APIs.
2. Add a bounded, server-local service registry.
3. Add local ServerHealth probes for heartbeat, memory, and frame stability.
4. Add an observational Watchdog for Auto DJ, queue progress, moderation, and recovery progress.
5. Expand local metrics and bounded ErrorHistory, correlating error IDs with health/watchdog state.
6. Update the trusted admin snapshot to display the new fields without exposing raw errors to clients.
7. Add a separate opt-in ClientDiagnostics component for client-side FPS, memory, ping, and frame spikes; client reports remain untrusted telemetry.
8. Retire obsolete diagnostic implementations only after all consumers have migrated.

No diagnostics component may become an enforcement authority or a dependency of SecurityCore.

## Verification

The coordinator and registry changes are statically inspected and committed. Roblox Studio runtime testing is still required. Test the same-server BindableFunction, ensure the snapshot stays read-only, and confirm that disabling or removing an optional probe reports NotInstalled/Unavailable rather than falsely marking the whole service unhealthy.
