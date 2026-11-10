# ClubMusic Global Operational Services — Phase 1

## Scope

This phase adds the six original operational services and the additional Metrics, Audit, and Rate Limit services. Config and Server Registry were requested twice under different list numbers, so each is implemented once.

All nine ModuleScripts are direct children of `ServerStorage` and are initialized by the existing `ServerScriptService.ClubMusic_Global_Service` Script. Replace that existing Script with the repository version; do not add a second bootstrap Script.

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

The keys are validated and unknown keys are rejected. The current phase records metrics/audit independently of these two advisory flags; those flags are reserved for follow-up policy wiring and must not be treated as access-control gates.

## Installation

1. Create the nine ModuleScripts above as direct children of `ServerStorage`, using the exact matching repository source files.
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
