# ClubMusic Global API and Diagnostics Consumer Audit

**Branch:** `feature/sultan-settings-2026-11-10`  
**Audit status:** Static compatibility pass; runtime verification and a full embedded-asset consumer sweep remain open.

## Scope and method

Inspected the current branch tree and the Global Service, Diagnostics coordinator, UI Server Controller, registry, ServerHealth, Watchdog, ErrorHandler, SafeCall module, SecurityCore status providers, and the packaged Global Optional Services asset. The audit records confirmed source-level call sites and deliberately does not treat an unobserved reference as proof that no consumer exists.

The Global Service creates `ServerStorage.ClubMusicGlobalAPI`. Its BindableFunctions and BindableEvent are server-only interfaces, not client remotes.

## Confirmed diagnostics API inventory

| API | Direction / consumer | Current purpose | Disposition |
|---|---|---|---|
| `GetGlobalHealth` | UI Server Controller → Global Service | Returns coordinator health status | Preserve; active admin health command |
| `GetGlobalMetrics` | UI Server Controller → Global Service | Returns structured local metrics | Preserve; active admin diagnostics command |
| `GetGlobalDiagnostics` | UI Server Controller → Global Service | Returns bounded server-local snapshot | Preserve; active admin diagnostics/error summary |
| `GetGlobalOperationalStatus` | UI Server Controller → Global Service | Returns diagnostics plus operational/SecurityCore status | Preserve; active status and diagnostics commands |
| `RecordLocalWatchdogPulse` | UI Server Controller → Global Service | Reports local playback/queue/AutoDJ progress | Preserve; active producer path |
| `RecordGlobalMetric` | Server scripts → Global Service | Adds a named metric to coordinator | Preserve; no external caller confirmed in inspected call sites |
| `GetGlobalSafeCallStatus` | Server scripts → Global Service | SafeCall aggregate status | Preserve pending complete consumer scan |
| `GetGlobalSafeCallRecent` | Server scripts → Global Service | SafeCall recent failure records, including error/traceback fields | Preserve server-only; no consumer confirmed in inspected call sites |

The SafeCall functions are registered only when the optional SafeCall module loads. They are BindableFunctions under ServerStorage, not client-facing remotes.

## Global API contract inventory

The current Global Service registers 45 BindableFunctions. Preserve names and argument/return behavior unless a staged migration proves every caller has moved.

- **Budgets and moderation:** `ConsumeActionBudget`, `ConsumeStateBudget`, `ConsumeDataStoreBudget`, `ConsumeAudioBudget`, `IsGloballyBanned`, `GetModerationState`, `SetGlobalBan`, `IsRequestBlocked`, `SetRequestBlocked`, `GetModerationHistory`, `IsTrackBlocked`, `SetTrackBlocked`.
- **Messaging and global state:** `PublishAnnouncement`, `PublishCatalogChange`, `IsEnabled`, `GetGlobalXPBoost`, `ActivateGlobalXPBoost`.
- **Diagnostics and health:** `GetGlobalMemoryStoreStatus`, `GetGlobalSafeCallStatus`, `GetGlobalSafeCallRecent`, `GetGlobalMetrics`, `GetGlobalOperationalStatus`, `RecordLocalWatchdogPulse`, `RecordGlobalMetric`, `GetGlobalHealth`, `GetGlobalDiagnostics`.
- **Audit and event log:** `GetGlobalAudit`, `RecordGlobalAuditEvent`, `RecordGlobalEvent`, `GetGlobalEvents`.
- **Configuration and maintenance:** `GetGlobalConfig`, `SetGlobalConfig`, `SetGlobalMaintenance`.
- **Rate limiting:** `ConsumeGlobalRateLimit`.
- **Security and incidents:** `RecordGlobalSecuritySignal`, `AuthorizeGlobalAction`, `GetGlobalSecurityStatus`, `GetGlobalSecurityPolicy`, `SetGlobalSecurityPolicy`, `ReserveGlobalOperation`, `OpenGlobalSecurityIncident`, `ResolveGlobalSecurityIncident`, `GetGlobalSecurityIncidents`.
- **Reconciliation and signals:** `RunGlobalReconciliation`, `ReportSignal`.

The `GlobalEvent` BindableEvent is also part of the compatibility surface. The UI Server Controller subscribes to it and reconnects if the Global API folder or event appears after its own startup.

## Confirmed consumer map

### UI Server Controller

The UI Server Controller owns the dynamic `globalInvoke(name, ...)` bridge. It re-resolves `ClubMusicGlobalAPI` when the Global Service starts late and invokes only BindableFunctions found in ServerStorage.

Confirmed diagnostics calls:
- `RecordLocalWatchdogPulse` — progress reporting from the controller's operational loops.
- `GetGlobalHealth` — OperationalHealth admin command.
- `GetGlobalDiagnostics` — OperationalDiagnostics and error-history summary.
- `GetGlobalOperationalStatus` — operational status and component state display.
- `GetGlobalMetrics` — metrics admin command.

It also consumes non-diagnostic Global Service methods for XP boost, moderation, catalog notifications, and admin/security operations. These are why the whole BindableFunction surface is inventoried above rather than treating the diagnostics subset as disposable.

### Global Service

The Global Service is the API provider and Diagnostics coordinator owner. It loads:
- `ClubMusic_Global_Diagnostics_Service`
- `ClubMusic_Local_Service_Registry`
- `ClubMusic_Server_Health_Service`
- `ClubMusic_Local_Watchdog_Service`
- `ClubMusicErrorHandler`
- optional `ClubMusic_Global_SafeCall_Service`

It injects read-only SecurityCore status callbacks into the Diagnostics coordinator. Diagnostics does not call enforcement APIs or make policy decisions.

## Duplicate and overlapping implementations

### SafeCall versus ErrorHistory

These are overlapping but not interchangeable:
- **SafeCall** records failures from operations explicitly wrapped with `Run`, plus explicit failure/recovery reports. Its recent records include error and traceback details.
- **ClubMusicErrorHandler / ErrorHistory** aggregates reported service errors and repeat counts in a separate bounded history.
- The Diagnostics coordinator reads ErrorHistory status and recent errors, but does not currently merge SafeCall's detailed records into that stream.

**Decision:** retain both for now. Do not merge or delete either until all SafeCall producers are inventoried and the desired privacy/retention behavior is tested. Keep SafeCall recent records server-only.

### Packaged SafeCall source

`ClubMusic_Global_Optional_Services.rbxmx` contains an embedded SafeCall ModuleScript source in addition to the standalone `ClubMusic_Global_SafeCall_Service.lua`. This is a packaged source copy, not proof of a second running instance. Keep the embedded and standalone copies synchronized if the module changes; verify which asset is used during Studio installation.

### ClientDiagnostics

`ClubMusic_Client_Diagnostics_Service.lua` is opt-in and client-local. It is not wired into the server coordinator and does not transmit telemetry. Keep it separate; client measurements remain untrusted and must not affect security decisions.

### Legacy Global Security Service

`ClubMusic_Global_Security_Service.lua` does not expose the confirmed diagnostics API methods in the inspected source. It is a separate legacy security implementation, not a duplicate of the current Diagnostics coordinator. Its retirement belongs to the SecurityCore migration, not this diagnostics compatibility pass.

## Decisions from this pass

1. No existing BindableFunction or BindableEvent is renamed or removed.
2. Keep all diagnostics calls server-only under ServerStorage.
3. Preserve the structured metric counters and aggregate metric compatibility shape.
4. Keep SafeCall and ErrorHistory distinct until producers and semantics are fully audited.
5. Keep ClientDiagnostics isolated from server health and enforcement.
6. Do not remove legacy or packaged source paths based only on the absence of a call in the inspected scripts.

## Remaining work

1. Search every script and embedded model payload for dynamic API names and `ClubMusicGlobalAPI` references, including installed Kohl's Admin assets and other packaged models.
2. Confirm the source of `ClubMusic_Global_Optional_Services.rbxmx` in the Studio installer workflow and whether the embedded SafeCall module is the actual deployed copy.
3. Inspect every `globalInvoke` / `adminBridgeGlobalCall` call against the provider signatures and document argument/return expectations.
4. Add a Studio compatibility test that starts the UI Controller before and after the Global Service, verifies late API discovery, exercises every diagnostics BindableFunction, and confirms `GlobalEvent` reconnects.
5. Only then mark unused APIs deprecated. Remove an API only after its consumer set is proven empty and a compatibility window has passed.

## Runtime status

No Roblox Studio or published-server execution was performed by this static audit. Runtime behavior remains unverified.

## Second pass — dynamic consumers, signatures, and packaged assets (2026-11-16)

### Dynamic bridge and late-start behavior

The UI Server Controller implements `ControllerFunctions.globalInvoke(name, ...)`. It:
- Re-resolves `ServerStorage.ClubMusicGlobalAPI` when the cached folder is missing, replaced, or no longer parented to ServerStorage.
- Looks up the requested child by name and requires it to be a `BindableFunction`.
- Packs and forwards the original arguments through `Invoke` inside `pcall`.
- Returns the invocation-success flag followed by up to three provider return values.

The event subscriber independently watches the initial API folder, a late-created API folder, and a late-created `GlobalEvent` child. It keys connections by event instance, so a replacement event can be attached without duplicating a connection to the same instance.

### Verified dynamic consumer names

The UI Server Controller contains dynamic invocations for:
- `GetGlobalXPBoost`
- `RecordLocalWatchdogPulse`
- `IsTrackBlocked`
- `ActivateGlobalXPBoost`
- `PublishCatalogChange`
- `SetRequestBlocked`
- `AuthorizeGlobalAction`
- `ReportSignal`
- `GetModerationHistory`
- `GetGlobalSecurityStatus`
- `GetGlobalSecurityIncidents`
- `OpenGlobalSecurityIncident`
- `ResolveGlobalSecurityIncident`
- `GetGlobalSecurityPolicy`
- `SetGlobalSecurityPolicy`
- `GetGlobalHealth`
- `GetGlobalDiagnostics`
- `GetGlobalOperationalStatus`
- `GetGlobalMetrics`
- `GetGlobalAudit`
- `GetGlobalConfig`
- `RunGlobalReconciliation`
- `SetGlobalMaintenance`
- `IsEnabled`
- `GetModerationState`

The Global Service source contains exactly 45 unique `bindFunction` registrations. Three SafeCall-related registrations (`GetGlobalMemoryStoreStatus`, `GetGlobalSafeCallStatus`, and `GetGlobalSafeCallRecent`) are conditional on the optional SafeCall module being available; therefore the runtime API may expose fewer than 45 functions when that optional module is absent. The rest are registered directly by the Global Service.

### Confirmed return-contract mismatch

**Finding: `GetGlobalAudit` is incompatible with the current admin bridge helper.**

- Provider: `GetGlobalAudit` returns `globalAuditService:GetRecent(...)` directly; it does not prefix the result with `true`.
- Consumer: the UI Server Controller calls it through `adminBridgeGlobalCall`.
- Bridge behavior: `adminBridgeGlobalCall` requires the provider's first return value to be exactly `true`, interpreting that first value as an acceptance flag.
- Result: if `GetRecent` returns its normal entries table as the first value, the bridge rejects a successful read and reports the operation as rejected. The `OperationalSecurityLog` command therefore has a source-level contract defect.

**Remediation decision:** preserve the existing `GetGlobalAudit` provider contract until all callers are known; update the admin bridge in a narrowly scoped compatibility patch to accept this read-only list-returning API, or introduce a separately named normalized wrapper after confirming no other consumer relies on the current return shape. Do not change the provider return shape blindly.

Other inspected diagnostics getters used by the UI bridge (`GetGlobalHealth`, `GetGlobalDiagnostics`, `GetGlobalOperationalStatus`, `GetGlobalMetrics`, and `GetGlobalConfig`) explicitly return `true, payload`, matching the bridge convention.

### Packaged assets and installer boundary

- The packaged `ClubMusic_Global_Optional_Services.rbxmx` contains an embedded `ClubMusic_Global_SafeCall_Service` ModuleScript source. The standalone Lua module remains a second source representation; edits must keep them synchronized if both are distributed.
- The Security Core installer source inspected in this pass does not install or reference the Optional Services package. It only looks up the Global API's `RecordGlobalSecuritySignal` BindableFunction for CharacterPhysicsGuard signal reporting. This does not establish which separate Studio workflow deploys Optional Services.
- A repository fetch of `Kohl's Admin.rbxmx txt.txt` returned empty content in this pass. Treat the Kohl's Admin package scan as **unverified**, not as a clean bill of health. The separate `RegularCommandsSecurityServer.lua` adapter remains the known integration boundary to inspect.
- No client RemoteEvent/RemoteFunction exposure of `ClubMusicGlobalAPI` was found in the inspected Global Service and UI Server Controller; the API folder is under ServerStorage and uses BindableFunction/BindableEvent instances.

### Second-pass decisions

1. Keep all 45 registered API names stable; account for the three optional SafeCall registrations when checking runtime presence.
2. Keep the Global API server-only and preserve the current dynamic late-discovery behavior.
3. Record `GetGlobalAudit` as a confirmed return-shape mismatch requiring a focused compatibility fix before declaring admin diagnostics consumers fully compatible.
4. Do not claim the Kohl's Admin export or all embedded models have been exhaustively scanned; the fetched export content was empty.
5. Keep the Optional Services package and standalone SafeCall source synchronized until the actual Studio distribution path is confirmed.

### Compatibility test cases to run in Studio

- Start UI Server Controller before Global Service; verify calls fail closed while unavailable, then recover once the API folder appears.
- Start Global Service before UI Server Controller; verify the initial folder/event connection is established.
- Remove and recreate `GlobalEvent`; verify the controller attaches to the replacement exactly once.
- Invoke every diagnostics getter and producer with valid and invalid arguments; verify expected first-return success flag and payload shape.
- Specifically exercise `OperationalSecurityLog` and verify `GetGlobalAudit` returns entries through the admin bridge after the compatibility fix.
- Run with SafeCall installed and absent; verify optional API presence is reported accurately and no core global feature depends on it.
- Confirm no raw SafeCall tracebacks or client-originated diagnostics are exposed to players.

