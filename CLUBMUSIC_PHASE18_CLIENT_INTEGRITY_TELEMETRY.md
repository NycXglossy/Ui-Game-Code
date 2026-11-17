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
