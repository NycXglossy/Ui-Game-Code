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
- The response includes error details and tracebacks; keep consumers server-side and do not forward the records to clients.

## Verification

Static source verification confirms:

- `GetGlobalHealth` remains registered.
- `GetGlobalDiagnostics` is registered on the existing API folder.
- Health and recovery status are read through protected calls.
- Recent error records are copied and capped at 20.
- The diagnostics callback contains no storage calls or state mutation.

No Roblox Studio runtime or live multi-server test was run by the assistant. In a dedicated test server, invoke the BindableFunction from a temporary trusted server Script and confirm that it returns health/recovery data without changing queue or playback state.
