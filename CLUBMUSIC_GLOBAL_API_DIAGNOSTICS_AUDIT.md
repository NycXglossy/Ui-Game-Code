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

**Remediation implemented (static):** the UI Server Controller's `adminBridgeGlobalCall` now special-cases only `GetGlobalAudit`: a table returned as the first provider value is normalized to the bridge's `true, entries` result. A non-table first value remains a failed read with a bounded fallback message. The Global Service provider was not changed, preserving its existing contract for other callers.

Other inspected diagnostics getters used by the UI bridge (`GetGlobalHealth`, `GetGlobalDiagnostics`, `GetGlobalOperationalStatus`, `GetGlobalMetrics`, and `GetGlobalConfig`) explicitly return `true, payload`, matching the bridge convention.

### Packaged assets and installer boundary

- The packaged `ClubMusic_Global_Optional_Services.rbxmx` contains an embedded `ClubMusic_Global_SafeCall_Service` ModuleScript source. The standalone Lua module remains a second source representation; edits must keep them synchronized if both are distributed.
- The Security Core installer source inspected in this pass does not install or reference the Optional Services package. It only looks up the Global API's `RecordGlobalSecuritySignal` BindableFunction for CharacterPhysicsGuard signal reporting. This does not establish which separate Studio workflow deploys Optional Services.
- A repository fetch of `Kohl's Admin.rbxmx txt.txt` returned empty content in this pass. Treat the Kohl's Admin package scan as **unverified**, not as a clean bill of health. The separate `RegularCommandsSecurityServer.lua` adapter remains the known integration boundary to inspect.
- No client RemoteEvent/RemoteFunction exposure of `ClubMusicGlobalAPI` was found in the inspected Global Service and UI Server Controller; the API folder is under ServerStorage and uses BindableFunction/BindableEvent instances.

### Second-pass decisions

1. Keep all 45 registered API names stable; account for the three optional SafeCall registrations when checking runtime presence.
2. Keep the Global API server-only and preserve the current dynamic late-discovery behavior.
3. Keep the focused `GetGlobalAudit` consumer-side normalization in place; verify it in Studio before declaring the admin diagnostics path runtime-compatible.
4. Do not claim the Kohl's Admin export or all embedded models have been exhaustively scanned; the fetched export content was empty.
5. Keep the Optional Services package and standalone SafeCall source synchronized until the actual Studio distribution path is confirmed.

### Compatibility test cases to run in Studio

- Start UI Server Controller before Global Service; verify calls fail closed while unavailable, then recover once the API folder appears.
- Start Global Service before UI Server Controller; verify the initial folder/event connection is established.
- Remove and recreate `GlobalEvent`; verify the controller attaches to the replacement exactly once.
- Invoke every diagnostics getter and producer with valid and invalid arguments; verify expected first-return success flag and payload shape.
- Specifically exercise `OperationalSecurityLog`: verify a populated audit list is accepted, an empty list is displayed as no recent events, and an unavailable audit service fails closed with a clear message.
- Run with SafeCall installed and absent; verify optional API presence is reported accurately and no core global feature depends on it.
- Confirm no raw SafeCall tracebacks or client-originated diagnostics are exposed to players.



## Third-pass: diagnostics exposure through the UI controller's client remotes

**Scope:** static inspection of the current `UI_Server_Controller_server (1).lua` only. This is a diagnostics-exposure check, not a repository-wide RemoteEvent/RemoteFunction security audit.

### Remote inventory observed in the controller

| Remote | Direction / handler | Observed safeguards | Diagnostics exposure assessment |
|---|---|---|---|
| `RequestAction` | Client → server, `OnServerEvent` | Delegates to the central action handler inside `pcall`; the action handler remains the authority boundary for action validation, permission checks, and rate limits | No diagnostics payload is accepted by this event. Action-handler authorization still requires its own full action-by-action audit |
| `PurchaseDiagnostic` | Client → server, `OnServerEvent` | Validates live Player, prompt type, positive integer item ID, allowed event shape; per-player limit of 12 events per 60 seconds; bounded local record buffer | Client reports are explicitly labeled unverified telemetry. They are not treated as receipt proof or used to grant purchases. Payload is reduced to bounded prompt-source / outcome text |
| `GetState` | Client → server, `OnServerInvoke` | Live-player check, shared query token bucket, per-player cooldown, protected snapshot generation | Returns the player's normal UI snapshot; no Global Diagnostics snapshot or SafeCall traceback is returned by this handler |
| `GetMusicCatalog` | Client → server, `OnServerInvoke` | Live-player check, global catalog token bucket, per-player cooldown, query/genre/offset/limit type and length validation, protected provider call | Catalog data only; no diagnostics records returned |
| `GetMusicPlaylists` | Client → server, `OnServerInvoke` | Live-player check, shared query token bucket, per-player cooldown, guarded refresh | Playlist data only; no diagnostics records returned |
| `StateChanged` | Server → clients | Server broadcast surface | Not a client request path; no diagnostic error payload was identified in this pass |
| `Notice` | Server → client | Server notification surface | Not a client request path; no diagnostic error payload was identified in this pass |

The server-only `ServerStorage.ClubMusicAdminBridge` is a BindableFunction, not a client RemoteFunction. Its handler validates a live Player and staff status before dispatch. The diagnostics commands use the server-side Global API bridge; no client remote was found that directly invokes `GetGlobalDiagnostics`, `GetGlobalSafeCallRecent`, `GetGlobalAudit`, or the Global API folder.

### Confirmed positive controls

- `PurchaseDiagnostic` records are marked as client-originated/unverified; ProcessReceipt remains the authoritative purchase completion path.
- The controller's diagnostics module is optional-load guarded. A missing or invalid ErrorHandler falls back to built-in startup diagnostics rather than exposing the module's private state.
- SafeCall recent records, including error/traceback fields, remain in the server-only Global API path in the inspected source.
- The existing `GetGlobalAudit` normalization is present in the current branch's `adminBridgeGlobalCall`; it accepts the provider's direct table return without changing the provider contract.

### Remaining limits / next audit boundary

1. This pass did not inspect every LocalScript client caller, every other server script, embedded model, or third-party admin package. It therefore does not certify repository-wide remote coverage.
2. `RequestAction` is a multiplexed event. Its individual action cases must be traced through `handleAction` before any statement can be made that every mutation has correct authorization, validation, and rate limiting.
3. Continue the wider security remote inventory separately across UtilityBar, Tiki Tide Settings, Kohl's Admin adapter, and other server scripts. Do not modify third-party package internals as part of this diagnostics-only pass.
4. Keep runtime tests outstanding: attempt to read diagnostics from an ordinary client, send malformed PurchaseDiagnostic telemetry, exceed its rate limit, and verify no traceback or private server snapshot reaches the client.


## Fourth-pass: RequestAction authorization and validation matrix

**Scope:** static trace of `ControllerFunctions.handleAction` and its `RequestAction.OnServerEvent` entry point in the current controller source. No source logic was changed in this pass.

### Shared entry controls

- Rejects a non-live player, invalid/oversized action string, unbounded payload, and action names absent from the fixed `ACTION_COOLDOWNS` allowlist.
- Payload is capped at 16 top-level keys; string keys/values and nested collections are bounded; numbers must be finite; nested values are restricted to bounded strings, finite numbers, and booleans.
- Applies per-player/per-server action budgets and action cooldowns before entering action-specific handlers.
- The normal UI RemoteEvent path does not set the trusted-admin flag. The separate server-only admin bridge authenticates staff before calling the shared action handler with its trusted-admin lane.

### Action groups and observed checks

| Action group | Actions | Authorization / validation observed |
|---|---|---|
| Player requests | `RequestTrack`, `RequestAudioAsset`, `VoteSkip` | Catalog track IDs must resolve to playable server catalog entries; request lock/block state, queue capacity, cooldown, per-player request limits, duplicates and current track are checked. Raw audio asset requests require staff, integer asset ID, optional allowlist, inspection concurrency/token budget, duration limit, and a second block-state check after the yielding inspection. Skip voting delegates to the server vote manager |
| Catalog management | `CatalogAddAudio`, `CatalogRemoveTrack` | Staff-only. Add validates asset ID, genre, optional image/decal asset, optional audio allowlist, inspection cooldown/concurrency/token budget, duration, and rechecks staff after yielding. Remove only accepts a server-known custom track, refuses current/queued tracks, and requires storage readiness/budget |
| Playlist management | `PlaylistCreate`, `PlaylistDelete`, `PlaylistAddTrack`, `PlaylistRemoveTrack`, `PlaylistMoveTrack` | Staff-only. Requires playlist service readiness and DataStore budget. Added track must be present in current server catalog. Service methods own playlist-ID/name/position validation |
| DJ booth controls | `DJPlayPlaylist`, `DJStopPlaylist`, `DJMoveUp`, `DJRemove`, `DJSkip`, `DJPause`, `DJRestart`, `DJClearQueue`, `DJToggleLock` | Each branch checks `isDJBoothController` (configured owner/co-owner level). Queue IDs are bounded and looked up server-side. Playback transitions are guarded; pause/resume/restart check audio operation results; queue operations act on local server queue |
| Moderation | `ModBlockUser`, `ModPurgeUser` | Admin-level check, then `findTarget` requires a live distinct target and hierarchy check. Block persists through Global API outside Studio; failed block remains locally blocked and failed unblock remains blocked. Purge removes only target's player-originated queue entries |
| Owner membership rewards | `ModSetPassTier` | Requires owner level (level >= 4), live distinct target/hierarchy validation, integer tier 0–3, and a loaded target profile; saves the owner-awarded tier |
| Daily rewards / title tags | `ClaimDailyReward`, `BuyTitleTag`, `EquipTitleTag` | Server validates day/streak/claim state; title purchases use server-side fixed prices and balance/ownership checks; equip requires an allowlisted tag already owned |
| Custom title settings | `SaveCustomTitle`, `SaveTitleSlot`, `SelectTitleSlot`, `ClearTitleSlot`, `SetTitleVisible` | Server validates text length, color/style/effect/font/slot data, ownership and unlocked slots. Title slot save requires Tiki Tide entitlement and server-side text filtering; client-supplied colors are not trusted |

### Findings and follow-up

1. The action dispatcher has a meaningful central validation/rate-limit boundary and each privileged action group performs its own authorization check. The observed rank tiers are delegated to SecurityCore Authorization through `GetLevel`; this file alone does not define the underlying group-rank mapping.
2. The `ModBlockUser` / `ModPurgeUser` handlers use `isAdmin`, and `findTarget` enforces strict target-rank hierarchy and prevents self-targeting. `ModSetPassTier` is owner-only.
3. `Playlist*`, `CatalogAddAudio`, `CatalogRemoveTrack`, and `RequestAudioAsset` use the controller's `isStaff` projection. Confirm the SecurityCore level-1 threshold remains the intended moderation/staff threshold (rank 150+) and that DJ-only rank 100 is not promoted to staff.
4. A number of rejected action branches return silently or notify rather than returning a structured false result. This is not an authorization bypass by itself, but it limits observability and should be considered separately from diagnostics exposure.
5. This is a static source review. It does not inspect every service method's internal validation, all client UI callers, or other remotes in UtilityBar / Tiki Tide Settings / Kohl's Admin. Do not infer complete repository-wide remote coverage.
6. Studio test matrix: attempt every privileged action as guest, DJ-only, moderator, admin, co-owner, and owner; test equal/higher-rank targets; malformed payloads; rapid repeats; failed Global moderation persistence; and confirm no diagnostic snapshots or tracebacks are returned to clients.


## Fifth-pass: SecurityCore rank separation and UtilityBar / Tiki Tide Settings remotes

### Authorization correction

Static review confirmed the prior rank projection treated GroupDJ rank 100 as authorization level 1. Because the main UI controller's `isStaff` projection uses level >= 1, a DJ could be classified as general staff. Corrected the shared SecurityCore rank mapping:

- GroupDJ threshold remains rank 100, but no longer elevates the general authorization level.
- Moderator threshold is explicitly rank 150 and maps to level 1.
- Admin remains rank 200 / level 2; Co-owner rank 254 / level 3; Owner rank 255 / level 4.
- `GlobalDJ` is handled as a narrow permission: a cached group rank >= 100 (or higher staff level) may pass it, without granting the DJ general staff status.
- Rank label for level 1 is now `MODERATOR`.
- Authorization remains cache-only and fail-closed when the rank cache is missing/expired.
- Updated `ClubMusic_Security_Core_Installer.lua` to fetch Authorization from commit `01889b884a8bc689b5d7bc90e1d15703f8fea304`.

### UtilityBar RemoteFunction

Reviewed `UtilityBar/UtilityBarExtendedActions.server.lua`:

- Fixed action allowlist; one shared 1.25-second per-player cooldown.
- Mount, Clone Companion, and Stage/Club Lighting require server-set entitlement attributes; client-supplied pass IDs/ownership are not accepted.
- Size is range-checked (0.5x–5x), uses R15 scale values, and registers self-only movement authority.
- Aura preset/target values are allowlisted; lighting presets are allowlisted and restricted to tagged `StageClubLight` objects.
- Added a live-player guard at the RemoteFunction entry point.
- **Open follow-up:** Size does not yet appear in the feature-pass attribute map. A dedicated Size Changer pass should only be enforced after its actual pass ID and server-owned entitlement attribute are configured; do not guess an ID.

### Tiki Tide Settings RemoteFunction / RemoteEvent

Reviewed `TikiTideSettings/TikiTideSettingsService.server.lua`:

- Request handler validates live player, action string and table payload, then applies a per-player cooldown.
- All settings actions require server-owned Tiki Tide entitlement.
- Teleport checks target validity and recipient consent; moderation override uses SecurityCore GlobalModeration and rechecks after authorization resolution.
- Gravity changes require GlobalConfig plus Tiki Tide entitlement, with reauthorization adjacent to mutation.
- Bubble and server announcements require GlobalAnnouncement, Roblox text filtering, cooldowns, and reauthorization after filtering yields.
- Broadcast RemoteEvent is server-to-client only in this service.
- The service fails closed when SecurityCore Authorization cannot be loaded.

### Remaining caveats

1. The DJ-only permission path is now separate in SecurityCore, but the actual client/server DJ Booth entry and control-mode toggle must still be traced to verify rank 100+ receives booth access while owner/co-owner-only control mode remains protected.
2. This pass did not inspect every UtilityBar / Settings client caller, every other server remote, or third-party package internals.
3. Studio verification is still required for rank 100, 150, 200, 254, and 255; expired authorization cache; pass entitlement failures; and remote spam/malformed payloads.
4. This remains a scoped static audit, not a repository-wide certification.


## DJ Control Mode permission split (2026-11-16)

Clarified and implemented the requested limited DJ role:

- Rank 100+ DJs are authorized through SecurityCore's narrow `GlobalDJ` permission. They can enter/toggle DJ Control Mode and use playback controls (skip, pause/resume, restart).
- Playlist rotation start/stop, queue reordering/removal, and queue clearing remain restricted to Owner/Co-owner (authorization levels 3+).
- The main controller now exposes `canUseDJBooth` and `canManageDJBooth` separately in the player-state snapshot. `perm` remains the general staff level, so DJ rank 100 is not mislabeled as staff.
- Authorization checks are server-side and fail closed if the SecurityCore cache is unavailable.
- Studio/client verification is still outstanding. The UI renderer should be checked to ensure its Control Mode button uses `canUseDJBooth` rather than `perm >= 3`; do not infer that client visibility is already updated from the server snapshot alone.


### Client UI permission projection follow-up

The ClubMusic renderer now reads the explicit `canUseDJBooth` and `canManageDJBooth` fields from the server state snapshot:
- Rank-100 DJs see DJ Booth playback controls and the Control Mode toggle.
- Only Owner/Co-owner see queue move/remove/clear controls and elevated playlist management.
- The Music tab also shows local playback controls to authorized DJs, while queue mutation controls remain elevated.
- General `perm` continues to represent staff level; it is not used as a substitute for the DJ entitlement.
- Runtime verification remains required for group ranks 100, 150, 200, 254, and 255.


## Sixth-pass: Global Service, UtilityBar, and Tiki Tide Settings remote boundary (2026-11-16)

### Global Service BindableFunction surface

Reviewed the current `ClubMusic_Global_Service_server_1.lua` source, including the server-created `ServerStorage.ClubMusicGlobalAPI` BindableFunction surface and MessagingService receive handlers.

- Global moderation/configuration mutations that accept an actor ID call the shared SecurityCore authorization check for the relevant permission (`GlobalModeration`, `GlobalAnnouncement`, or `GlobalConfig`) before mutation or publication.
- Authorization initialization failure leaves protected actions denied. The authorization helper wraps `Check` in `pcall` and requires an explicit `true` result.
- Global security-policy writes delegate to the policy service; its service-level authorization contract remains a dependency that must be retained when that module is changed.
- Cross-server messages pass through the dedicated MessageValidation service; if that service is absent or rejects/throws, the receiver rejects the message rather than using a weaker fallback.
- Message IDs are deduplicated with a bounded 2,048-entry, 120-second local cache. Receive handlers additionally validate message kind and relevant fields before firing the server-local BindableEvent.
- The diagnostics snapshot and SafeCall recent-record functions are server-only BindableFunctions under ServerStorage. They are not exposed as client remotes by the inspected Global Service source. The main controller's client-facing diagnostics projection remains separately constrained to aggregate data as documented above.
- The BindableFunction API is an internal server-to-server trust boundary, not a client security boundary. Every new server script that invokes a mutation must supply an actor identity that is independently authorized; do not treat possession of a BindableFunction reference as authorization.

### UtilityBar RemoteFunction

Reviewed `UtilityBar/UtilityBarExtendedActions.server.lua`:

- The RemoteFunction rejects non-live players and unknown action names.
- Feature pass checks use server-owned player attributes; no client-supplied pass ID or ownership claim is trusted.
- A shared per-player 1.25-second cooldown applies before dispatch.
- Size input is finite-number checked and clamped to the supported 0.5x–5x range; avatar and Humanoid components are resolved server-side.
- Aura presets/targets and Stage/Club Lighting presets/fixtures are allowlisted; clone scripts are removed and clone parts are non-colliding/non-queryable.
- Size remains intentionally absent from the feature-pass map until a real pass ID and server-owned entitlement attribute are configured. Do not infer or invent a pass ID.
- No additional authorization bypass was identified in this static pass.

### Tiki Tide Settings RemoteFunction / Broadcast RemoteEvent

Reviewed `TikiTideSettings/TikiTideSettingsService.server.lua`:

- The Request RemoteFunction accepts only a live player, bounded action string, table payload, and a per-player cooldown; action handlers validate the specific values they consume.
- Every settings action requires the server-set `HasTikiTideAccess` attribute. Privileged gravity and announcement actions additionally require SecurityCore permissions.
- Teleport validates a live distinct target, recipient consent or moderator permission, both players' continued presence, and character roots before moving the caller.
- Gravity is finite-number checked, clamped, and reauthorized immediately before mutation.
- Broadcast messages are filtered through TextService and permission/entitlement are rechecked after the yielding filter call; announcement and bubble cooldowns are rechecked before broadcast.
- Broadcast is server-to-client only in this service. No client-to-server listener was found on that RemoteEvent.
- SecurityCore unavailability fails closed for privileged actions; duplicate service startup is rejected.

### Pass result and boundaries

- No new client-reachable authorization bypass was identified in these inspected handlers.
- This pass extends the earlier controller, UtilityBar, Settings, and Global API audits, but it is not a formal certification of every script/model in the repository. GitHub code search did not return an indexed remote inventory for this branch, so remaining embedded assets and third-party packages cannot be claimed as exhaustively inspected.
- Kohl's Admin internals remain outside scope; inspect and maintain only the separate security adapter/add-on.
- Runtime verification is still outstanding: malformed and oversized payloads, rapid remote calls, expired/missing SecurityCore cache, permission revocation during yielding operations, cross-server message rejection/replay, and ordinary-client attempts to reach diagnostic APIs.
- Do not retire legacy diagnostics or mark the audit runtime-complete until the Studio and published-server test matrix passes.


## Seventh-pass: text-source remote inventory and UtilityBar lifecycle hardening (2026-11-16)

The branch tree was enumerated and text-based Lua/Luau sources were reviewed for remote creation, invocation, and event-handler patterns. The active ClubMusic, Tiki Tide Settings, and UtilityBar remote families are now listed in `CLUBMUSIC_DIAGNOSTICS_MASTER_RELEASE_REGISTER.md`.

Additional findings and changes:
- `UtilityBar/UtilityBarActions.server.lua` now rejects a non-live player and rechecks player connection after the yielding avatar-description lookup, before applying the description. This closes the disconnect-during-yield lifecycle gap.
- `UtilityBar/ToolShop.server.lua` now rejects a non-live player and rate-limits the read-only `GetShop` RemoteFunction to one query per player per 0.5 seconds. Per-player query state is cleared on departure.
- Tiki Tide Settings `Broadcast` is server-to-client only in the inspected service; no client-to-server listener was found.
- The UtilityBar extended-action, avatar-refresh, and ToolShop RemoteFunctions are separate from ClubMusic's RequestAction dispatcher and are documented as such.
- The root-level legacy `Music System` creates a separate `MusicRemotes` family. Its `DispatchAction` uses a fixed action allowlist and the legacy RoleSystem/rate-limiter path; `RequestSync` has a per-player cooldown. This path is not proven active or inactive in the published place, and it is not integrated with the current SecurityCore authorization contract. Do not delete or disable it without checking the live place hierarchy and client references.
- The five manager source files now exist in the repository. Their presence does not prove a manager migration: several are adapters around controller-owned operations, and the legacy `Music System` expects child modules under its own Roblox instance. The earlier Phase 0 source-availability statement is superseded; see the updated Phase 0 audit and master release register.

**Scope boundary:** This is a repository text-source inventory, not a decompilation or certification of binary `.rbxm`/`.rbxmx` assets, embedded third-party packages, or Kohl's Admin internals. The live Roblox place hierarchy remains unverified.

**Still required before release:** complete the Studio and published-server matrix in the master release register, reconcile the legacy `MusicRemotes` deployment status, and inspect binary/model assets or explicitly record their exclusion. Do not mark runtime verification complete based on static source inspection.
