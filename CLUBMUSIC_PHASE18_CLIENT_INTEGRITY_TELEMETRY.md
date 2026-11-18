# Phase 18 — Client Integrity Telemetry

**Status:** Source implementation committed; Studio and published-server acceptance remains open.

## Purpose and scope

Phase 18 adds a narrow client-side dependency-presence observer. It checks whether the expected ClubMusic client modules and remote objects are present after a 60-second startup grace period. This is **not** a secure client attestation mechanism and does not prove that client code is genuine, unmodified, or running honestly.

The client is fully untrusted. An exploiter can suppress, forge, replay, or modify any client report. Missing reports are not evidence of tampering. The server remains authoritative for all permissions, purchases, movement, moderation, queue/playback state, and gameplay actions.

## Implemented source

- Added `ClubMusicSecurityCore/ClientIntegrityTelemetry.lua`, staged by the SecurityCore installer and pinned to the matching source release.
- Added `ClientIntegrityTelemetry.client.lua`, installed as a LocalScript under `StarterPlayerScripts`.
- The client waits for the server-created `TikiTideClientIntegrityTelemetry_v1` RemoteEvent; it never creates a fallback remote.
- After a 60-second grace period, the client checks only the expected dependency presence/class:
  - `ReplicatedStorage.UI_Network` ModuleScript
  - `ReplicatedStorage.UI_Renderer` ModuleScript
  - `ReplicatedStorage.ClubMusicRemotes` Folder
  - `RequestAction`, `StateChanged`, and `Notice` RemoteEvents
  - `GetState` RemoteFunction
- It sends only fixed, allowlisted signal codes for missing/wrong-class dependencies, plus a probe-completed code when the folder is present. It sends no arbitrary arguments, text, stack traces, device information, memory, FPS, ping, asset IDs, or local file paths.
- Server-side receiver derives the Player/UserId from Roblox's RemoteEvent callback, validates the exact signal allowlist, limits each player to eight unique reports, applies a one-second minimum interval, caps tracked players at 200, and clears per-player state on departure.
- Valid reports are written only to the existing server-local SecurityReplay timeline with severity Info. They are **not** fed into ThreatIntelligence scoring, authorization, moderation, or enforcement.
- Adds server-only `ServerStorage.GetTikiTideClientIntegrityStatus`, exposed through existing unified diagnostics and staff `;cmdiagnostics`.
- Installer fetches the pinned module and LocalScript, stages the LocalScript with the existing client camera installer, and includes backup/rollback handling.
- No client FPS/memory/ping diagnostics are transmitted. This security-signal endpoint is separate from the client-local diagnostics service.
- No automatic kick, ban, shadow restriction, gameplay nerf, movement correction, or incident creation.

## Trust and privacy boundaries

- A `probe_completed` report means only that the client script claims it completed its limited dependency check. It is not a cryptographic handshake or integrity proof.
- A missing dependency report may reflect a deployment/configuration issue, replication timing, or client modification. Review it as a clue, not a verdict.
- No report, or a report that all dependencies were present, cannot prove that the client is untampered.
- The RemoteEvent is visible to clients and can be called manually. Server validation and quotas bound its impact; they do not make client telemetry trustworthy.
- Client reports are server-local replay observations only. No DataStore, MemoryStore, MessagingService, or cross-server diagnostic aggregation is added.


## Proposed extensions — movement observations and observer liveness

**Status:** Design additions only. These items are not represented as implemented source until the corresponding server and client code is reviewed, committed, and tested.

### 18.6 — Client movement observation signals

The supplied example LocalScript monitors Humanoid.WalkSpeed and reports when the value exceeds a fixed threshold. Do not install that implementation as written.

- A fixed client threshold such as 24 studs/second is not authoritative and can produce false positives during legitimate Tiki Tide Settings, Utility Bar, VIP, or authorized administrator movement changes.
- The client can change its own Humanoid properties, suppress the LocalScript, forge the RemoteEvent call, or report an arbitrary value. A client-reported speed is not evidence of actual server-observed movement.
- Do not transmit the numeric WalkSpeed, concatenated diagnostic text, stack traces, or arbitrary property values.
- If a client-side property-change observation is retained for troubleshooting, send only a fixed allowlisted code such as client_walkspeed_observed_change. Its meaning is strictly “this client observer noticed a local property-change event,” not “the player cheated” or “the speed was invalid.”
- Treat the signal as an untrusted SecurityReplay observation at Info severity. It must not independently create a threat score, incident, moderation action, movement correction, permission decision, or gameplay restriction.
- Server-side movement evaluation remains separate and authoritative. Reuse the existing MovementAuthority and CharacterPhysicsGuard observations; do not add a parallel movement enforcement system or assume that an approval marker proves a client report is genuine.
- Do not introduce a universal WalkSpeed threshold until actual movement sources, authorized modifiers, device behavior, network ownership, and latency have been inventoried and measured.

### 18.7 — Observer heartbeat and liveness

The example sends a heartbeat every five seconds with client os.clock(). Do not use that design as an integrity proof.

- A heartbeat can show only that the server received a message claiming the observer is active. It cannot prove that the expected LocalScript is genuine, unmodified, or the source of the message.
- If liveness monitoring is needed, use a fixed allowlisted heartbeat code with no client timestamp, arbitrary payload, or client-generated identity.
- Record receive time using the server's own clock. Do not compare client os.clock() or client wall-clock timestamps with server time.
- Give heartbeat traffic its own bounded rate limit and last-received state. Repeated heartbeats must not be treated as unique dependency reports or consume the existing eight-unique-report allowance.
- Prefer a substantially slower interval (for example, 30–60 seconds) over a five-second loop; choose the final interval only after profiling server event volume and deciding what operational detection delay is acceptable.
- A missing or late heartbeat is an observer-liveness timeout, not evidence of exploitation. It may result from startup delay, replication, client shutdown, disconnect, network interruption, or deliberate suppression.
- Heartbeat state must be bounded, cleared on PlayerRemoving, and exposed only as aggregate or appropriately staff-authorized diagnostics. It must not create unbounded per-player histories or persistent cross-server records.
- Do not add automatic kicks, bans, shadow restrictions, or gameplay changes for missed heartbeats.

### 18.8 — Character lifecycle and connection cleanup

Any optional client property observer must follow character lifecycle safely.

- Handle an already-existing character and subsequent CharacterAdded events.
- Wait for the Humanoid with a bounded timeout and verify that the character is still the player's current character before attaching observers.
- Disconnect the previous Humanoid property-change connection when the character is replaced or removed; do not accumulate connections across respawns.
- Ignore callbacks from stale characters and destroyed Humanoids.
- Do not create a tight polling loop. Prefer the property-change signal and bounded work.
- Ensure observer startup failure or missing character parts does not block UI startup or gameplay.

### 18.9 — Server correlation boundary

- Keep client observations and server movement observations distinguishable in SecurityReplay and diagnostics.
- Correlation may help staff investigate timing and configuration mismatches, but a client signal must never upgrade an unverified server observation into a confirmed violation.
- Use server-observed character state and the existing movement services for any authoritative decision. Preserve the current detection-only posture unless a separately reviewed phase explicitly authorizes a narrowly scoped enforcement design.
- Do not store player positions, paths, or detailed movement histories for this telemetry. Any future measurement proposal must define its privacy, retention, bounds, and performance cost before implementation.

### 18.10 — Abuse and regression acceptance

Before enabling these extensions, test:

1. Forged, malformed, duplicate, extra-argument, and high-frequency movement-observation reports.
2. Repeated heartbeat calls, heartbeat floods, delayed heartbeats, missing heartbeats, and forged heartbeat calls.
3. Legitimate speed changes through Tiki Tide Settings, Utility Bar, approved administrator actions, respawns, and other inventoried movement sources.
4. Character replacement while a property callback is pending; verify stale callbacks are ignored and old connections are disconnected.
5. Missing Humanoid, delayed character assembly, destroyed character, and player departure during observer startup.
6. Verify client numeric values, timestamps, and arbitrary text are not accepted as authoritative evidence.
7. Verify heartbeat state has independent rate limits, bounded memory, server receive timestamps, and PlayerRemoving cleanup.
8. Verify all client-originated signals remain untrusted Info-level observations and never reach ThreatIntelligence scoring or enforcement.
9. Profile event volume and server overhead at realistic player counts before choosing the heartbeat interval.
10. Re-run playback, crossfade, local queue, playback-only global sync, purchases, moderation, Utility Bar, Settings, spectator, and diagnostics regressions.

**Integration constraint:** Reuse the existing TikiTideClientIntegrityTelemetry_v1 endpoint and ClientIntegrityTelemetry service if these extensions are implemented. Do not create a second ClientTelemetry RemoteEvent or a parallel receiver. The server must explicitly support and separately rate-limit any new signal category before the client begins sending it.

## Runtime acceptance still required

1. Run the installer in a disposable Studio place; verify module staging, LocalScript staging, promotion, backup retention, rollback, and shutdown behavior.
2. Verify the server creates exactly one `TikiTideClientIntegrityTelemetry_v1` RemoteEvent and the LocalScript never creates one.
3. With all expected UI dependencies present, verify the client sends only `client_integrity_probe_completed` after the startup grace period.
4. Remove or change one dependency in a test copy; verify only the matching fixed signal is recorded and no gameplay behavior changes.
5. Fire malformed strings, extra arguments, duplicate codes, and bursts manually; verify allowlist rejection, duplicate suppression, interval throttling, per-player caps, tracked-player bounds, and PlayerRemoving cleanup.
6. Verify all accepted records are Info-level SecurityReplay events with server-derived UserId and empty metadata; verify none reach ThreatIntelligence scoring.
7. Verify the server status endpoint is ServerStorage-only and `;cmdiagnostics` displays accepted/rejected/duplicate counters with the untrusted boundary.
8. Verify a missing, disabled, or forged client observer never authorizes, denies, kicks, bans, restricts, or otherwise changes a player.
9. Verify the existing client-local FPS/memory/ping diagnostics remain local-only and no diagnostics payload is transmitted.
10. Profile burst overhead and run playback, crossfade, local queues, playback-only global sync, purchases, moderation, Utility Bar, Settings, spectator, and diagnostics regression tests in Studio and published servers.

**Exit criteria:** bounded receiver and memory use, no client trust in authorization/enforcement, correct replay-only signal routing, safe installer rollback, no gameplay regressions, and successful Studio/published-server testing.

**Release note:** This is dependency-presence telemetry, not tamper-proof client integrity detection. Source implementation is not runtime certification.
