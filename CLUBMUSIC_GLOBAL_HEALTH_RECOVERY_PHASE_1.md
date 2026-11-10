# ClubMusic Global Health and Recovery — Phase 1

## Scope

Adds operational visibility and bounded recovery checks to the existing cross-server ClubMusic service. This phase does not add another playback controller, queue owner, or persistent queue schema.

## Files

- `ClubMusic_Global_Health_Service.lua` — ModuleScript for service-health reporting.
- `ClubMusic_Global_Recovery_Service.lua` — ModuleScript for retrying transient authoritative queue reads.
- `ClubMusic_Global_Service_server_1.lua` — existing ServerScriptService Script, updated to load and start both modules, expose a health query, and forward operational failures to `ClubMusicErrorHandler`.

## Installation

1. Replace the existing `ClubMusic_Global_Service_server_1` Script in ServerScriptService with the updated file.
2. Add `ClubMusic_Global_Health_Service` as a ModuleScript directly under ServerStorage.
3. Add `ClubMusic_Global_Recovery_Service` as a ModuleScript directly under ServerStorage.
4. Keep the existing `MusicGlobalQueueService` ModuleScript directly under ServerStorage.
5. Do not add a second copy of the global service Script or the local UI controller.
6. Keep `EnableInStudio = false` unless intentionally testing cross-server behavior in a separate test universe.

Deploy the three code files together. The new modules are optional-load guarded: if either is missing or fails to load, the existing global queue service continues to initialize and logs the operational-service problem.

## Health reporting

The health module checks:
- Whether the existing cross-server service is enabled.
- Whether the existing Global API folder and GlobalEvent are available.
- Whether the existing global queue module is present as a ModuleScript.
- Whether the recovery coordinator reports healthy storage, a transient failure, or a pending catalog reservation.

It writes these attributes on `ServerStorage.ClubMusicGlobalAPI`:
- `HealthStatus`
- `HealthDetail`
- `HealthUpdatedAt`
- `RecoveryStatus`

The existing API folder also exposes a `GetGlobalHealth` BindableFunction. It returns a success boolean and a health-status table when the monitor is available.

## Recovery behavior and safety boundaries

The recovery coordinator:
- Uses the existing shared DataStore budget gate before probing.
- Invalidates only the short-lived local snapshot cache before retrying an authoritative queue read.
- Retries transient storage failures with bounded exponential backoff from 30 seconds up to 180 seconds.
- Reports pending catalog add/remove reservations for operator visibility.

It intentionally does **not** clear, expire, or rewrite a pending catalog reservation. A reservation may represent a catalog write that committed just before a server stopped. Resume the original catalog add/remove operation using the existing catalog workflow; do not manually edit the global queue DataStore.

The recovery module never plays audio, advances playback, enqueues entries, or changes queue ownership.

## Verification

- GitHub files were fetched after commit and their resulting blob hashes were confirmed.
- Static source checks confirmed both modules exist, the existing global service wires them optionally, the health query is registered, and the recovery module contains no queue mutation or reservation-clearing path.
- No Roblox Studio runtime or live multi-server test was run by the assistant. Verify in a dedicated test universe before publishing.


## Error-handler integration

The existing `ServerStorage.ClubMusicErrorHandler` is loaded optionally by the global service. The same ModuleScript instance is shared by `require()` within each server process, so health and recovery diagnostics enter the same bounded local error history used by the UI controller on that server.

- Health reports a transition into a degraded health state.
- Recovery reports a transition into a degraded shared-storage probe state.
- Repeated identical states are not reported every polling cycle; each service reports only when its state/detail signature changes.
- The error handler remains a reporting sink. It does not start recovery, and recovery does not call back into the error handler for a retry decision.
- If the error handler is absent or fails, the global service falls back to `warn()`; the operational services remain optional and must not block startup.

This history is per server process, not a cross-server central database. Cross-server aggregation is not added in this phase.
