# Phase 14 — Unified Diagnostics & Health

**Status:** Existing diagnostics architecture was already partially implemented. This phase connects the Phase 13 adaptive load manager and Phase 12 replay status into the existing server-local diagnostics snapshot, adds a bounded observability health summary, and exposes the new status to authorized staff. Legacy diagnostics retirement and Roblox runtime verification remain open.

## Existing foundation (not replaced)

Before Phase 14, the repository already contained:
- `ClubMusic_Global_Diagnostics_Service`: local coordinator, metric counters, health checks, and bounded snapshots.
- `ClubMusic_Local_Service_Registry`: bounded registry of local service interfaces and required/optional states.
- `ClubMusic_Server_Health_Service`: Heartbeat timing and process-memory observations.
- `ClubMusic_Local_Watchdog_Service`: expected progress pulses and stale/unhealthy detection for Playback, AutoDJ, Queue, Moderation, and Recovery.
- `ClubMusicErrorHandler`: bounded error history and deduplication.
- `ClubMusic_Global_SafeCall_Service`: protected operation outcomes and bounded recent failure records.
- `SecurityCore` status providers, bounded `SecurityReplayService`, and Phase 13 `AdaptiveSecurityLoadManager`.
- Existing server-only BindableFunction diagnostics and aggregate-only staff projection.

This phase does not replace these services, create a second watchdog, merge independent error stores, or change the playback/queue authority.

## Scope delivered

1. **Adaptive load visibility**
   - The Global Service reads the dedicated ServerStorage `GetTikiTideSecurityLoadStatus` BindableFunction.
   - The server-local diagnostics snapshot and `GetGlobalOperationalStatus` include adaptive mode, sampling, transition, and optional budget information.
2. **Replay visibility**
   - The Global Service reads the dedicated ServerStorage `GetTikiTideSecurityReplayStatus` read-only BindableFunction.
   - Replay capacity, retained count, drops, denied queries, and local-memory scope appear in diagnostics.
   - Diagnostics never query replay event contents; event review remains a separate permission-checked `;cmreplay` operation.
3. **SafeCall visibility**
   - SafeCall call/failure/recovery counters are included in the server-local snapshot and operational status.
   - Detailed errors and tracebacks remain server-side; the client projection is not expanded to include them.
4. **Unified observability summary**
   - The snapshot adds `operationalServices.observabilityHealth`, a bounded summary across Diagnostics, ServiceRegistry, ServerHealth, Watchdog, AdaptiveLoad, SecurityReplay, SafeCall, and ErrorHistory.
   - The summary reports component counts and fixed issue labels, not arbitrary error text.
   - Missing optional components are classified as Partial/Unavailable rather than silently reported Healthy.
5. **Authorized staff diagnostics**
   - The existing OperationalDiagnostics staff operation now displays observability summary, adaptive load mode, replay retention/capacity, and SafeCall counters.
   - Existing SecurityCore, watchdog, memory, heartbeat, registry, messaging, and error-history details remain.
   - The output remains bounded and does not include SafeCall tracebacks or replay event records.

## Boundaries preserved

- Diagnostics remain server-local and observational.
- No diagnostic DataStore, MemoryStore, MessagingService, client RemoteEvent, or client RemoteFunction is added.
- No health probe starts, stops, repairs, retries, or enforces against another service.
- No automatic playback repair, queue mutation, moderation, kick, ban, or restart is added.
- The Adaptive Load Manager continues to gate only its explicitly integrated optional work; it never throttles essential validation, authorization, rate limiting, receipts, moderation, or replay event recording.
- Existing `GetGlobalHealth`, `GetGlobalMetrics`, `GetGlobalDiagnostics`, and `GetGlobalOperationalStatus` names and legacy metric counters are preserved.
- Diagnostics and SecurityCore remain separate: diagnostics may observe security status but cannot change security policy or enforcement.

## Still incomplete

- Audit all dynamic consumers, packaged model assets, and embedded third-party packages before retiring any legacy diagnostic implementation.
- Resolve whether SafeCall and ErrorHistory should remain separate (current recommendation: preserve both until their consumers and semantics are fully inventoried).
- Verify all watchdog pulse expectations during long tracks, paused playback, AutoDJ idle periods, and disabled recovery.
- Reconcile the prior reported degraded watchdog/detail-registry/memory warnings against fresh live runtime output; source-level aggregation does not prove those warnings are fixed.
- Add status providers for any confirmed services that are still absent from the local registry, without registering speculative or non-existent services.
- Studio and published-server verification and performance profiling remain mandatory.

## Studio and published-server acceptance tests

1. Install the exact branch revision in an isolated test place and verify the existing diagnostics modules are in their documented ServerStorage/ReplicatedStorage locations.
2. Query `GetGlobalDiagnostics` and `GetGlobalOperationalStatus` from trusted server code. Confirm the new adaptive-load, replay, SafeCall, and observability-health entries are present.
3. Verify missing adaptive-load/replay endpoints are represented as NotInstalled/Unavailable, not as Healthy and not as a startup crash.
4. Verify adaptive load reports Normal/Reduced/Critical accurately while diagnostics continue to read status without changing mode.
5. Verify replay status reports capacity/retention/drop counters only; `GetGlobalDiagnostics` must not return replay event contents.
6. Verify SafeCall counts are visible to authorized staff while error text and tracebacks remain server-side.
7. Test watchdog stale/healthy transitions for playback, AutoDJ, queue, moderation, and recovery; confirm diagnostics performs no corrective action.
8. Test ServerHealth Heartbeat and memory sample age, including unavailable memory sampling.
9. Confirm ordinary clients cannot access the server-only BindableFunctions and the staff client projection contains no traces or private service state.
10. Test long-running sessions for bounded registry, metrics, error-history, replay, and SafeCall storage.
11. Profile Heartbeat and snapshot-call overhead under controlled load.
12. Re-run playback controls, crossfade, local queues, playback-only global sync, purchases, moderation, Tiki Tide Settings, Utility Bar, and spectator regressions.

## Exit criteria

The consolidated snapshot must report accurate local health and distinguish healthy, degraded, unavailable, not-installed, and partial states; all state reads remain observational and bounded; authorized staff see the new high-level operational data without private traces; no legacy component is retired before consumer audit and runtime tests pass. Source review alone is not runtime verification.


## Final source-level diagnostics closure pass (2026-11-16)

The final static pass resolved two boundedness/packaging gaps and completed the source-level watchdog pulse review:

- Synchronized the embedded `ClubMusic_Global_SafeCall_Service` ModuleScript inside `ClubMusic_Global_Optional_Services.rbxmx` with the standalone source. Both now cap recent failures at 50 records and warning-deduplication keys at 100 with 120-second expiry; the embedded copy no longer has an unbounded warning-key table.
- Bounded watchdog pulse metadata to at most 8 primitive fields, with short validated keys, 140-character strings, and finite numeric values capped at an absolute value of 1,000,000,000. This prevents a trusted server-side pulse caller from retaining an arbitrarily large metadata table.
- Confirmed statically that Playback pulses every second, including while paused or audio reload is in progress; Queue and AutoDJ are sampled every 30 seconds and on refill; Recovery is event-driven and not required to pulse while idle; Moderation is optional/event-driven. Playback has a 12-second stale window; Queue and AutoDJ have 900-second stale windows. AutoDJ intentionally reports degraded when it cannot meet the configured queue target, rather than silently treating an empty/unplayable catalog as healthy.
- SafeCall and ErrorHistory remain separate by design: SafeCall records protected-operation outcomes and recovery counters, while ErrorHistory captures broader controller/module error records with its own deduplication semantics. Both remain bounded and are consumed separately.

**Phase 14 source status:** the source integration and in-repository text-source checks are complete. This does not close the release gate. Studio/published-server pulse behavior, historical degraded-warning reconciliation, load profiling, full binary/third-party package review, and live-place revision/hierarchy verification remain external acceptance items. No legacy diagnostics implementation has been retired.


## Phase 15 compatibility note

Phase 15 adds a read-only ThreatIntelligence status provider to the existing operational snapshot and observability component summary. It does not change Phase 14's server-local/observational boundaries or retire any diagnostics implementation. The threat-correlation status is optional and reports Unavailable/NotInstalled when its installer endpoint is absent.


## Phase 16 completion integration

The Phase 16 diagnostics completion work extends the existing coordinator rather than replacing it. The server snapshot now reads the controller's server-only aggregate diagnostics endpoint and CharacterPhysicsGuard status; ServerHealth reports a bounded memory trend; SafeCall reports an explicit latest outcome; and staff diagnostics include purchase, moderation lookup, playback, and security signal summaries. Client measurements remain local and opt-in. See `CLUBMUSIC_PHASE16_DIAGNOSTICS_COMPLETION.md` for implementation scope and remaining runtime acceptance.
