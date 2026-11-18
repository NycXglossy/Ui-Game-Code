# Phase 14.1 — Server-Local Diagnostics in Staff Controls

**Source status:** Implemented on the `phase14.1-local-staff-diagnostics` development branch.
**Runtime status:** Open. Roblox Studio and published test-server acceptance remain required. This branch is not approved for live installation.

## Objective

Extend Phase 14/16 observability without replacing the existing diagnostics stack. Put the staff-facing overview inside the Phase 22 Tiki Tide Staff Controls console. Every server health reading describes only the Roblox server instance currently hosting the staff member. Client performance readings describe only the viewing staff member's client.

## Implemented source changes

### 1. Dependency integrity and restoration verification

- Extended `ClubMusic_Local_Service_Registry` with `RegisterDependency`.
- A dependency records its expected Roblox Instance class and expected parent.
- Every registry status read rechecks that the instance still exists in the expected hierarchy and has the expected class.
- Missing, destroyed, reparented, or wrong-class dependencies report `Unavailable`; restoring the same instance to its expected hierarchy reports healthy on the next read.
- Registered the required `ServerStorage.ClubMusicGlobalAPI` folder and the local ServerHealth, Watchdog, and Diagnostics ModuleScripts.
- Service interface checks remain separate from hierarchy checks. The registry does not start, stop, repair, or replace a service.

### 2. Performance profile

- Preserved the existing 60-second Heartbeat frame-time window and 30-second memory sampling.
- Added average estimated server FPS and maximum observed frame time to the ServerHealth snapshot.
- Existing bounded memory history, freshness, min/max/average and trend remain in place.
- The default arbitrary hard memory threshold remains disabled. No fixed FPS threshold is used to trigger gameplay changes.

### 3. Staff Controls diagnostics overview

- Added a Diagnostics overview inside the existing `StaffConsoleGui`; no separate ScreenGui or F8 HUD is created.
- The overview requests the existing allowlisted `Diagnostics` staff command through `SecurityAction` and displays the returned aggregate server snapshot.
- The existing detailed Diagnostics commands remain available from the overview's **Detailed Commands** control or by selecting the Diagnostics category again.
- Client FPS, ping, and client memory are read from the existing opt-in `ClubMusic_Client_Diagnostics_Service` directly on the staff member's client.
- Client sampling starts only when an authorized staff member opens the Diagnostics overview, stops when the console closes or another category is selected, and can be restarted when the overview is reopened.
- Client readings are labeled untrusted and local-only. They are never transmitted to the server and never influence authorization, enforcement, or server health.

### 4. Health history and trend detection

- Added a bounded 20-entry health state transition history to `ClubMusic_Global_Diagnostics_Service`.
- The status snapshot reports current-state duration, degraded duration, consecutive degraded checks, transition count, and last recovery timestamp.
- Repeated degraded checks are observable without creating unbounded history.
- The staff `OperationalDiagnostics` output now includes the latest transition, trend counters, dependency count, server FPS, and worst-frame timing.
- History is in-memory and scoped to the current server process. It is not persisted or shared.

### 5. Dependency recovery verification

- The registry dynamically revalidates the expected class and parent on each status read.
- A dependency returning to the expected hierarchy is reported healthy on the next read.
- This is observation only. No automatic repair, restart, retry, reparenting, cleanup, or enforcement occurs.

### 6. Performance regression and acceptance matrix

The following checks are release gates and have **not** been executed by this source change:

1. Confirm the exact ModuleScript hierarchy in an isolated Studio test place.
2. Confirm the staff console remains hidden and unavailable to non-staff; verify authorization is server-side and remains valid after rank changes/revocation.
3. Open/close the Diagnostics overview repeatedly; verify client sampler Start/Stop lifecycle, no duplicate RenderStepped connections, and no duplicate sampler tasks.
4. Verify server FPS, frame-time, memory freshness/trend, instance count, registry, watchdog, and transition history are consistent with server Output.
5. Temporarily remove, reparent, and restore the registered Global API folder and optional diagnostics ModuleScripts in a disposable test place. Confirm state changes to Unavailable and back to Healthy without service repair.
6. Verify history caps at 20 entries, transition counters remain bounded, degraded duration resets on recovery, and no transition is written for unchanged state.
7. Profile diagnostics overhead with an empty server, a full server, long-running music playback, paused playback, crossfade, queue refill, and a long session.
8. Compare baseline and diagnostics-enabled server frame-time, memory, and instance count. Investigate material overhead before acceptance; do not assume a universal numeric threshold.
9. Run playback controls, modern AudioPlayer, crossfade, local request queues, optional playback-only global sync, purchases, moderation, staff commands, and Utility Bar regression tests.
10. Verify no diagnostics DataStore/MemoryStore writes, MessagingService messages, client-to-server diagnostic remotes, cross-server health aggregation, or diagnostic persistence exist.
11. Confirm no diagnostic traces, raw error records, private service state, user identities, track names, or asset IDs appear in the staff client projection.

## Non-negotiable boundaries

- Server diagnostics are per-server-instance and in-memory.
- Existing cross-server ClubMusic features remain separate. Diagnostics may report their local availability but do not aggregate peer-server health.
- No diagnostics DataStore, MemoryStore, MessagingService, RemoteEvent, or RemoteFunction was added.
- No client telemetry is sent to the server.
- No automatic playback repair, queue mutation, moderation, kick, ban, restart, or gameplay change.
- SecurityCore remains independent; diagnostics observe but do not alter authorization or enforcement.
- Existing Phase 14/16 services, public BindableFunction names, and detailed staff commands are preserved.
- No legacy diagnostics implementation is retired.

## Installation and release notes

This is a source-only development branch. It has not been installed into Roblox Studio or a live place. Runtime behavior, UI sizing across device classes, security authorization, performance overhead, and all regression cases above remain unverified. Do not publish or install this branch until the acceptance matrix passes and the live-place hierarchy is reconciled.
