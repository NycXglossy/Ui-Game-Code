# ClubMusic Global Operational Services — Phase 1

## Scope

This phase adds the six original operational services and the additional Metrics, Audit, and Rate Limit services. Config and Server Registry were requested twice under different list numbers, so each is implemented once.

All nine Phase 1 ModuleScripts are direct children of `ServerStorage` and are initialized by the existing `ServerScriptService.ClubMusic_Global_Service` Script. Phase 2 adds six security ModuleScripts, for fifteen global service modules total. Replace that existing Script with the repository version; do not add a second bootstrap Script.

## ModuleScripts to install

- `ClubMusic_Global_Server_Registry` — expiring MemoryStoreSortedMap heartbeats, JobId, PlaceId, player count, max players, and local health label. Entries expire after 180 seconds.
- `ClubMusic_Global_Event_Log_Service` — bounded, expiring operational event records (24-hour retention).
- `ClubMusic_Global_Watchdog_Service` — periodic health probes and warnings only; it never restarts or takes ownership of playback/queue controllers.
- `ClubMusic_Global_Config_Service` — validated, revisioned shared configuration persisted through DataStore and the existing shared DataStore budget.
- `ClubMusic_Global_State_Reconciliation_Service` — read-only periodic check that the authoritative global queue snapshot can be read. It does not overwrite state.
- `ClubMusic_Global_Maintenance_Service` — maintenance flag/message coordinated through Global Config.
- `ClubMusic_Global_Metrics_Service` — bounded local counters and latency samples flushed to an expiring MemoryStore aggregate. It tracks publish/event/error counts and accepts explicit latency samples.
- `ClubMusic_Global_Audit_Service` — bounded, expiring audit records for administrative actions, catalog changes, queue changes, maintenance, and security-relevant events (7-day retention).
- `ClubMusic_Global_RateLimit_Service` — facade over the existing shared token buckets. It deliberately does not create a competing limiter; action budgets use the facade when initialized.

## Existing bootstrap integration

The updated `ClubMusic_Global_Service_server_1.lua`:
- Initializes each module independently; a missing optional service is reported without preventing the other services from starting.
- Exposes server-only BindableFunctions under `ServerStorage.ClubMusicGlobalAPI`.
- Includes Registry, Metrics, and Watchdog status in `GetGlobalDiagnostics`.
- Preserves existing queue, playback, moderation, catalog, recovery, and health ownership.
- Keeps `EnableInStudio = false`.

## Server-only API BindableFunctions

- `GetGlobalOperationalStatus()`
- `GetGlobalServers(limit?)`
- `GetGlobalMetrics()`
- `GetGlobalAudit(limit?)`
- `GetGlobalEventLog(limit?)`
- `GetGlobalConfig()`
- `SetGlobalConfig(key, value, actorUserId)`
- `SetGlobalMaintenance(enabled, message, actorUserId)`
- `ConsumeGlobalRateLimit(key, capacity, refillPerSecond, cost)`
- `RecordGlobalMetric(name, value, latencySeconds?)`
- `RecordGlobalAuditEvent(kind, actorUserId, target, action)`

These are BindableFunctions inside ServerStorage, not public RemoteFunctions. Only trusted server Scripts/ModuleScripts should call them. Validate permissions in the calling server controller before invoking administrative setters.

## Configuration keys

- `maintenanceEnabled` (boolean; default false)
- `maintenanceMessage` (string, max 240 characters)
- `allowPlayerRequests` (boolean; default true)
- `metricsEnabled` (boolean; default true)
- `auditEnabled` (boolean; default true)

The keys are validated and unknown keys are rejected. `metricsEnabled` gates metric collection/flush, and `auditEnabled` gates audit and operational event-log writes. `allowPlayerRequests` is exposed as shared policy state for trusted controller consumers; this phase does not independently block player requests, so it must not be treated as an access-control gate until the controller explicitly enforces it.

## Installation

1. Create the nine Phase 1 ModuleScripts above and the six Phase 2 security ModuleScripts below as direct children of `ServerStorage`, using the exact matching repository source files.
2. Replace the existing `ServerScriptService.ClubMusic_Global_Service` source with `ClubMusic_Global_Service_server_1.lua`.
3. Keep `EnableInStudio = false`.
4. Publish the experience and enable API Services in a controlled published test environment before validating MemoryStore/DataStore behavior.
5. Query `ServerStorage.ClubMusicGlobalAPI.GetGlobalOperationalStatus` from a trusted server Script to inspect status.

## Limits and validation

- Registry, metrics, event log, and audit data use expiring MemoryStore records; they are operational telemetry, not durable archival storage.
- Config uses DataStore and consumes the existing shared DataStore budget.
- MemoryStore failure can mark an individual service degraded; no service silently claims cross-server success.
- Rate-limit service uses the existing shared token bucket implementation; no duplicate token store is created.
- The watchdog is observational and does not auto-restart systems.
- Maintenance is coordinated state only. This phase does not automatically kick players, stop playback, or block requests based on maintenance mode.
- This phase has static source integration only. Roblox Studio runtime, multi-server MemoryStore, and DataStore behavior still require your published test.

## Phase 2 — Global Security Services

Six additional ModuleScripts are initialized independently by the same global bootstrap:

- `ClubMusic_Global_Authorization_Service` — checks permissions through a server-only resolver supplied by the ClubMusic controller. It denies by default if the resolver is missing or the actor is not online.
- `ClubMusic_Global_Security_Monitor_Service` — bounded per-server signal aggregation and threshold alerts. It is observational; it does not automatically ban, kick, or restrict users.
- `ClubMusic_Global_Message_Validation_Service` — validates cross-server message topic, envelope version, sender identity, ID, timestamp, allowlisted kind, and encoded size. Existing topic handlers still validate their detailed payload schemas.
- `ClubMusic_Global_Idempotency_Service` — atomic expiring MemoryStore reservations for caller-supplied operation IDs (1–47 characters). A caller must reuse the same ID across retries. Existing queue mutations are not silently wrapped because their current APIs do not accept a stable operation ID.
- `ClubMusic_Global_Incident_Response_Service` — bounded incident records with authorized open/resolve operations and audit hooks. It does not perform automatic bans, kicks, or controller shutdown.
- `ClubMusic_Global_Security_Policy_Service` — validated shared security thresholds backed by the existing revisioned Global Config DataStore.

### Authorization levels

The controller exposes `ServerStorage.ClubMusicAuthorizationResolver`, using its existing server-verified rank cache:

- `GlobalDJ`: level 1 (staff / group DJ)
- `GlobalModeration`: level 2 (admin)
- `GlobalAnnouncement`: level 2 (admin)
- `GlobalConfig`: level 3 (co-owner or owner)
- `SecurityPolicy`: level 3 (co-owner or owner)
- `IncidentResponse`: level 3 (co-owner or owner)

The global bootstrap applies these checks to global DJ commands, ClearQueue, global moderation setters, announcements, configuration setters, and security-policy/incident operations. Authorization rejects offline actors and unknown permission names. Existing controller-side checks remain in place; this is an additional server-side check, not a replacement.

### Security policy keys

These validated keys are stored in the existing shared `ClubMusic_GlobalConfig_v1` DataStore:

- `messageMaxBytes`: 512–4096 (default 4096)
- `messageMaxAgeSeconds`: 30–300 (default 120)
- `suspiciousSignalThreshold`: 3–100 (default 8)
- `idempotencyTtlSeconds`: 30–600 (default 120)
- `monitoringEnabled`: boolean (default true)

### New server-only API BindableFunctions

- `GetGlobalSecurityStatus()`
- `AuthorizeGlobalAction(actorUserId, permission)`
- `GetGlobalSecurityPolicy()`
- `SetGlobalSecurityPolicy(key, value, actorUserId)`
- `ReserveGlobalOperation(operationId, ttlSeconds?)`
- `OpenGlobalSecurityIncident(kind, summary, actorUserId)`
- `ResolveGlobalSecurityIncident(incidentId, actorUserId)`
- `GetGlobalSecurityIncidents(limit?)`

Incident kinds are allowlisted: `SecurityAlert`, `ServiceDegraded`, `AbuseReport`, and `ManualReview`. Security monitoring currently records invalid message envelopes and explicit `ReportSignal` calls; it does not infer malicious intent from a single event.

### Phase 2 installation and validation

1. Add the six security ModuleScripts as direct children of `ServerStorage`.
2. Replace `ServerScriptService.ClubMusic_Global_Service` with the updated `ClubMusic_Global_Service_server_1.lua`.
3. Update `UI_Server_Controller_server (1).lua` so it creates the server-only authorization resolver.
4. Keep `EnableInStudio = false`.
5. Publish to a controlled test environment and inspect `GetGlobalSecurityStatus` and `GetGlobalOperationalStatus`.

This is static source integration only. Roblox Studio runtime, rank resolver behavior, MemoryStore atomic reservation behavior, and multi-server message handling still require your published test.
