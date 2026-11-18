# Phase 16 — Diagnostics Completion

**Status:** Source implementation completed for the scoped diagnostics features. Roblox Studio and published-server acceptance tests remain open. This phase completes the missing source-side diagnostic projections without replacing the existing diagnostics coordinator, registry, ServerHealth, Watchdog, SafeCall, ErrorHistory, replay, or threat-intelligence services.

## Implemented

### Server runtime and memory trends
- ServerHealth continues to measure Heartbeat timing over a 60-second rolling window.
- Added a bounded 20-sample process-memory history (approximately ten minutes at the existing 30-second sample interval).
- Reports average/minimum/maximum memory, change since the oldest retained sample, sample count, last attempt, and sample age.
- Marks memory data Stale after 90 seconds without a successful sample. No arbitrary hard memory threshold is enabled by default.
- No memory-pressure response, restart, cleanup, or gameplay change is performed.

### Controller-local purchase, moderation, and playback diagnostics
- Added server-only `ServerStorage.GetClubMusicLocalDiagnostics` BindableFunction.
- Purchase summary reports total prompt/receipt telemetry, authoritative ProcessReceipt callback count, grants, retry-pending outcomes, rejected unregistered products, duplicates, and last success/failure timestamps.
- Client prompt reports remain explicitly unverified and are not counted as completed purchases.
- No PurchaseId, player name, raw receipt secret, or detailed error is returned by the aggregate endpoint.
- Moderation summary reports server-side join lookup attempts, successful/failed lookups, pending checks, ban/block result counts, and last success/failure times. Studio's intentionally isolated moderation path is not counted as a production lookup failure.
- Playback summary reports active source type, playing/paused state, queue depth, modern-backend configuration/migration status, and migration-failure count. It does not expose track names, audio asset IDs, or user identities.
- Global Diagnostics reads this endpoint on demand; no RemoteEvent/RemoteFunction was added.

### Security and operational summaries
- Unified snapshot now includes controller diagnostics and CharacterPhysicsGuard status.
- Security health includes CharacterPhysicsGuard as an observed component.
- Staff `;cmdiagnostics` includes memory trend, purchase/receipt outcomes, moderation lookup health, playback backend/queue state, SecurityMonitor and CharacterPhysicsGuard signal counts, ResourceGuard lane occupancy/rejections, StorageGuard circuit state, and client-telemetry boundaries.
- Existing `;cmpurchases`, `;cmreplay`, `;cmthreat`, `;cmsecurity`, and `;cmerrors` remain separate detailed review commands.
- `RecordGlobalMetric` accepts an optional `Success`, `Failure`, or `Observed` outcome and retains bounded aggregate counts, latency, and last outcome timestamps. Existing three-argument callers remain compatible.
- SafeCall now exposes an explicit latest outcome (`Success`, `Failure`, or `Recovered`) so the diagnostics health state does not rely on second-resolution timestamp comparisons. Standalone and packaged SafeCall module sources are synchronized.

### Client-local diagnostics
- Existing opt-in client module remains strictly client-local and untrusted.
- Added freshness states for client memory and ping samples.
- Added `ClubMusic_Client_Diagnostics_Bootstrap.client.lua`, disabled by default. When explicitly enabled in a test client, it creates a local-only `PlayerScripts.GetClubMusicClientDiagnostics` BindableFunction for reading FPS/frame-time, frame spikes, memory, and ping.
- No client telemetry is sent to the server, and it cannot authorize, restrict, or punish players.


### Optional status-provider startup guard (source hardening follow-up)
- The global diagnostics reader now checks that a ServerStorage status BindableFunction has an assigned `OnInvoke` callback before calling `Invoke`.
- If the endpoint exists but its owner has not bound the callback yet, the snapshot reports `Starting` instead of invoking an unbound BindableFunction and potentially yielding indefinitely.
- This guard applies to the optional adaptive-load, replay, threat-intelligence, controller, and CharacterPhysicsGuard status providers.
- It does not create endpoints, change authorization, or add recovery behavior.

## Explicitly not implemented by this phase

- **Honeypot sensors:** this branch does not contain an installed HoneypotManager/decoy-remote subsystem. Diagnostics reports this as not installed rather than inventing activation counts. Honeypot creation and integration belongs to a separate security implementation phase.
- **Client integrity sensors:** no trusted client-integrity sensor exists in the inspected source. Client-reported integrity is untrusted by definition; no such signal is used for authorization or enforcement.
- **Client error-log aggregation:** client errors are not collected or transmitted. The client diagnostics module reports local sampling errors only.
- **Cross-server diagnostics aggregation:** intentionally excluded. Global service availability is a local server's view only; no peer health or diagnostic messages are collected.
- **Full per-action moderation outcome counters:** join moderation lookup health is instrumented here. Staff moderation decisions continue to use existing Audit/IncidentResponse sources; no new moderation mutation path was added.

## Resource and security boundaries

- Diagnostics remain server-local or client-local.
- No diagnostic DataStore, MemoryStore, or MessagingService writes were added.
- No new server/client remotes were added.
- No polling loops beyond the existing ServerHealth sampler or explicitly opted-in client sampler were added.
- The controller endpoint is a ServerStorage BindableFunction and returns aggregate metadata only.
- No automatic recovery, queue repair, playback action, restart, kick, ban, shadow restriction, or gameplay modification is performed.
- Existing modern AudioPlayer, crossfade, per-server queue, optional playback-only global sync, purchase ledger, and Utility Bar behavior are not intentionally changed.

## Runtime acceptance still required

1. Verify the ServerStorage diagnostics endpoint is available only to server scripts and is created once.
2. Verify purchase callback/grant/pending/failure/duplicate counters against controlled receipt test cases without storing PurchaseId.
3. Verify moderation counters in published servers and ensure Studio isolation is not reported as a failure.
4. Verify queue depth and AudioPlayer/legacy source reporting during idle, playing, paused, reload, and crossfade.
5. Verify memory history remains capped at 20 samples and stale state appears after failed/stale sampling.
6. Verify SafeCall latest outcome changes Failure → Recovered/Success and standalone/package parity.
7. Verify metric outcome validation and compatibility with existing three-argument calls.
8. Install the client module in ReplicatedStorage and bootstrap in StarterPlayerScripts; enable only in a test client and inspect the local BindableFunction. Confirm no telemetry crosses to the server.
9. Verify `;cmdiagnostics` output is bounded and readable; test all relevant staff permission levels.
10. Reconcile the previously reported watchdog, service-registry, and memory warnings using fresh output.
11. Profile sampling and snapshot overhead.
12. Re-run modern playback controls, crossfade, independent local queues, playback-only global sync, purchases, moderation, Utility Bar, Settings, and spectator regression tests.

**Release note:** Source implementation is not Roblox runtime verification. Do not publish or retire legacy diagnostics code until the runtime matrix passes.


## Phase 17 follow-up — Honeypot integration

The previously listed HoneypotManager exclusion was the Phase 16 scope at that time. Phase 17 now adds a separate detection-only HoneypotManager and exposes its server-local status through the existing diagnostics snapshot and staff output. Phase 16's other runtime acceptance requirements remain open; Phase 17 has its own runtime acceptance checklist in `CLUBMUSIC_PHASE17_HONEYPOT_MANAGER.md`.


## Phase 18 follow-up — Separate security telemetry from local diagnostics

Phase 16's client FPS/frame-time/memory/ping diagnostics remain client-local and are not transmitted. Phase 18 adds a distinct, bounded security-signal RemoteEvent for fixed dependency-presence observations only. It does not transmit diagnostic metrics or logs, and accepted client reports are untrusted Info-level replay entries only; they are excluded from ThreatIntelligence scoring and all authorization/enforcement decisions. See CLUBMUSIC_PHASE18_CLIENT_INTEGRITY_TELEMETRY.md.


## Phase 16 follow-up — periodic server runtime diagnostics

- Extended the existing `ClubMusic_Server_Health_Service.lua`; no second diagnostics script, Heartbeat listener, or independent sampler was introduced.
- Every 15 seconds, the existing service samples the documented server-local `Stats.InstanceCount`, `Stats.DataSendKbps`, and `Stats.DataReceiveKbps` properties through protected reads and emits one concise `[CLUB DIAGNOSTICS]` output line.
- The output reports a rolling-window average server FPS estimate derived from the existing 60-second Heartbeat delta-time buckets, rather than treating one `Heartbeat:Wait()` interval as a stable FPS measurement.
- Total memory continues to use the existing protected `Stats:GetTotalMemoryUsageMb()` sample every 30 seconds and the existing bounded 20-sample trend history. The 15-second diagnostic line reuses the most recent memory sample; it does not add a second memory sampler.
- Runtime-stat read failures are represented as partial/unavailable fields and do not stop the health service.
- The proposed fixed 2,500 MB warning was intentionally not enabled. Phase 16 keeps arbitrary hard memory thresholds disabled by default; memory trend, sample freshness, and existing configurable threshold behavior remain authoritative.
- No kicks, bans, restarts, cleanup actions, throttling, DataStore/MemoryStore/MessagingService writes, remotes, or cross-server reporting were added.

**Runtime acceptance:** verify the three Stats properties return finite values on a dedicated published server, the log cadence is approximately 15 seconds, memory samples remain approximately 30 seconds apart, missing Stats values are reported as partial rather than crashing, and the existing diagnostics snapshot/staff diagnostics output remains compatible. Source changes are not Studio or production runtime certification.


## Phase 16 follow-up — opt-in client audio observations

- Extended the existing opt-in client-local diagnostics service; the existing bootstrap remains disabled by default.
- Every 10 seconds, the client checks the replicated, controller-owned modern AudioPlayer folders under SoundService and records whether a managed AudioPlayer is playing and its current TimePosition.
- While a managed AudioPlayer is playing, the test client prints a concise local diagnostic line with playback time and the most recently sampled client Data Ping value.
- This intentionally does not use the old `workspace.ClubAudio.MainTrack` Sound path. The modern backend creates managed AudioPlayer instances under SoundService, not a legacy MainTrack Sound.
- Roblox AudioPlayer does not expose Sound.PlaybackLoudness. Loudness is therefore explicitly reported as unsupported/null; no fake loudness value or additional AudioAnalyzer processing graph was introduced.
- Track titles and audio asset IDs are not exposed by this local diagnostic. The source is identified as `Modern AudioPlayer`; the current source graph does not provide a verified human-readable track title to this client sampler.
- Observations remain client-local, untrusted, and absent from server telemetry. No RemoteEvent, RemoteFunction, server authorization, moderation, recovery, queue, or playback-control behavior was added.
- Runtime acceptance: enable the existing client diagnostics bootstrap only in a test client; verify a managed AudioPlayer is discovered during normal playback and crossfade, the log cadence is approximately 10 seconds while playing, ping is a recent local sample, pause/stop states are not reported as playing, missing audio graphs return a bounded NotFound/Unavailable state, and client diagnostics remain disabled by default.

**Limitation:** This is playback-state/time diagnostics for the modern AudioPlayer backend, not a loudness meter or track-title resolver. Do not add an AudioAnalyzer solely to reproduce the legacy Sound.PlaybackLoudness field without a separate measured need and audio-graph performance review.
