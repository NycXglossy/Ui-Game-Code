# ClubMusic Audio Migration — Implementation Modules (Four-Update Workstream)

Date: 2026-11-10
Branch: `audit/hardened-clubmusic-2026-11-08`

## Delivered source modules

The following opt-in modules were added as the implementation layer for the four-update audio workstream:

1. `ClubMusicAudioBackend.luau` — modern `AudioPlayer -> AudioFader -> AudioDeviceOutput` graph, with asset assignment, play/stop, seek, gain, playback speed, and explicit pause/resume emulation by saving the playhead and stopping/restarting.
2. `ClubMusicAudioCrossfadeManager.luau` — controller-invoked dual-deck crossfade coordinator. It does not own the queue or choose the next track. The controller supplies deck creation, outgoing gain, and the commit callback.
3. `ClubMusicAudioQualityProfiles.luau` — bounded named profiles applied through injected controller callbacks.
4. `ClubMusicDJSessionManager.luau` — DJ start/end/handoff state with an injected authorization check and controller handoff callback; history is bounded to 50 entries.
5. `ClubMusicPlayerPreferences.luau` — client-local gain/mute/profile adapter. It deliberately never changes the server-wide SoundGroup or shared server playback gain.
6. `ClubMusicSpatialAudioGraph.luau` — opt-in emitter/listener route builder with explicit route cleanup.

## Four implementation updates represented by the commits

| Update | Source changes | Commit |
|---|---|---|
| 1 — Modern backend foundation | AudioPlayer graph and playback adapter | `8198d36` |
| 2 — Transition and audio profiles | Crossfade coordinator and quality profile adapter | `652c5b3`, `9334b4a` |
| 3 — DJ and local preferences | DJ session manager and player-local preference adapter | `e6286dc`, `353f021` |
| 4 — Spatial routing and migration safeguards | Spatial graph builder; emitter-to-listener wire correction; phase 1 inventory and cutover gates | `5572b38`, `1fc0871`, `68f8e5d` |

## Important integration status

These modules are committed building blocks, **not yet a completed production cutover**. The current controller still has direct `Sound` dependencies in its main play/stop/pause/resume, state reconciliation, watchdog, restart, and asset inspection paths. The renderer still uses `MusicGroup` for local volume fallback and a temporary `Sound` for staff preview.

The modules must be connected to the controller/client as one coordinated change before the modern backend can be enabled. In particular:

- Replace every controller read/write of the canonical `musicSound` with a backend-neutral adapter contract, including global resync and watchdog inspection.
- Migrate `AudioProbe` to bounded `AudioPlayer.IsReady` inspection while retaining Marketplace audio-type validation, timeout behavior, inspection concurrency accounting, and permission-failure handling.
- Replace the client shared-`SoundGroup` fallback with a local graph that consumes the replicated server audio stream and routes to the local player's device output. Do not enable this while the server still emits the same stream to everyone, or clients may hear duplicate audio.
- Move staff preview to a separate client-local AudioPlayer graph and ensure cancellation/timeout cleanup.
- Wire DJ session authorization to the existing server permission functions and expose handoff through a controller-owned operation; do not let the module grant roles or mutate queue state.
- Supply the crossfade manager with two actual AudioPlayer decks, one controller-owned transition token, and a commit callback. It must be cancelled on skip, clear, restart, pause, server reconciliation, and shutdown.
- Supply spatial routes only for a deliberate venue mode with verified emitter/listener placement. The spatial module is not enabled by default.
- Add actual effect nodes/configuration for EQ profiles; the current profile adapter only applies the gain/speed values supplied through callbacks.

## Safety decision

The modern backend, crossfade, spatial routing, and local output graph remain opt-in/unconnected. The existing `ServerMusicSound`, `MusicGroup`, `AudioProbe`, and `AudioPreview` are retained. Do not remove legacy instances or enable the modern backend until the controller/client integration is complete and tested in Roblox Studio with multiple clients.

## Verification

Static source inspection confirmed the controller currently accesses `musicSound` directly in playback start/stop, global synchronization, pause/resume, and watchdog paths. This confirms why switching the backend or deleting the legacy Sound objects at this stage would be unsafe.

No Roblox Studio runtime, audio permission, device output, or multiplayer tests have been run as part of these commits.


## Follow-up integration update — backend-neutral inspection

Three existing playback integration files were updated after the initial module commits:

- `ServerMusicAudioHandler.luau` now exposes a read-only `GetPlaybackSnapshot()` contract. It supports the existing marked canonical Sound and an injected AudioPlayer backend without taking ownership of either.
- `MusicPlaybackManager.luau` now accepts the optional snapshot provider and classifies modern backend readiness, playback, pause, and stopped/buffering states. The legacy Sound inspection remains the fallback.
- `UI_Server_Controller_server (1).lua` now supplies the existing audio adapter's snapshot to the playback manager. The active controller still supplies the legacy Sound, so runtime behavior remains on the existing fallback.

Follow-up commits:
- `a8cc90b` — backend-neutral audio adapter snapshot.
- `6c12c5c` — backend-neutral playback quality inspection.
- `f2c0fec` — controller diagnostic snapshot bridge.
- `62c31c7` — guard optional legacy Sound accessor.

This is a compatibility seam only. It does **not** activate AudioPlayer playback, migrate AudioProbe, replace client volume routing, enable crossfade, or remove Sound/SoundGroup.

### Audio routing constraint confirmed against current Roblox documentation

A server-created AudioDeviceOutput with no Player assigned is heard by everyone. A Player-targeted AudioDeviceOutput can target one player. Therefore a true individual-volume design must provide separate per-player output/fader routes (or a verified client-local route) and must not leave a global output active alongside those routes, or listeners can receive duplicate audio. The existing renderer's local SoundGroup fallback is retained until that routing is implemented. See the Roblox Creator Hub AudioDeviceOutput and Audio objects documentation.


## Follow-up integration update — modern probes and staff preview

The next independent legacy dependencies have now been migrated:

- Controller `AudioProbe` now uses an `AudioPlayer` with `AutoLoad`, `Asset`, `IsReady`, and `TimeLength`. The existing metadata validation, `PreloadAsync`, timeout, in-flight inspection slot, late completion cleanup, and permission-failure response are retained.
- Renderer staff preview now creates a client-local graph: `AudioPlayer -> AudioFader -> AudioDeviceOutput`, with the output targeted to the mounting player. Volume changes update the preview fader. Ended, timeout, replacement, renderer destruction, and GUI destruction clean up the graph.
- Main shared playback still uses the legacy canonical Sound. This was intentional: migrating probes and preview does not prove that the shared server output, client-local volume, or full controller transition lifecycle is ready.

Follow-up commits:
- `e690f7e` — staff preview migrated to a local AudioPlayer graph.
- `00dc20e` — controller asset inspection migrated to AudioPlayer readiness.

The local preview output is targeted to the mounting player because Roblox documents `AudioDeviceOutput.Player` as the intended listener; an unset Player routes the stream to everyone. The probe uses AudioPlayer.Asset and IsReady, with ContentProvider.PreloadAsync retained for the existing asynchronous inspection contract.

These changes are source-integrated but still require Studio validation of private/restricted assets, output routing, preview cancellation, and concurrent timeout cleanup.


## DJ session controller integration — phase 3

The optional `ClubMusicDJSessionManager` is now connected to the server controller when installed at `ServerStorage/ClubMusicAudioModules/ClubMusicDJSessionManager`. It is a session-ownership facade only: it does not grant staff rank, change queue ownership, or control playback.

Kohl's Admin exposes these commands:
- `;cmdjsession` — show the active local-server DJ session.
- `;cmdjstart` — start a session for the caller.
- `;cmdjhandoff <UserId>` — hand off to a connected player who already has ClubMusic staff permission.
- `;cmdjend` — end the caller's active session.

The controller independently verifies the caller's ClubMusic staff rank. Handoff verifies the target is connected and is already ClubMusic staff. The manager records a bounded 50-entry in-memory history and automatically ends the active session if its owner disconnects. Sessions are local to each game server and are not cross-server DJ leases.

The server package must be dragged into Studio so the module is present. If the optional module is absent or fails to load, the rest of ClubMusic continues to start and the DJ session commands report that the module is unavailable.

## Remaining audio integration gates

- Player-local volume/preferences are still not connected to the live shared music stream. The current canonical output is the server-owned `ServerMusicSound` routed through `MusicGroup`; attaching a local fader only to the staff preview would not provide per-player control of the main music and would be misleading.
- Crossfade is not enabled. The current controller still owns playback transitions; crossfade needs two real decks and one cancellation token covering skip, clear, restart, pause, reconciliation, and shutdown.
- Spatial audio remains opt-in. A real venue emitter/listener placement and routing policy must be supplied before creating any route.
- Audio quality profiles remain gain/speed presets, not EQ or effects processing.

No Roblox Studio runtime or multiplayer tests have been run for this phase. Verify the module folder, start/handoff/end flows with two authorized staff accounts, and player departure cleanup in Studio before relying on it in a live server.


## Player-local volume preference integration — phase 4

The renderer now loads `ClubMusicPlayerPreferences` from `ReplicatedStorage/ClubMusicClientAudioModules` when the optional client module is installed. The existing volume slider and mute button route their gain through that preference manager. Its injected local-gain callback adjusts the client-side instance of the canonical `SoundService.MusicGroup` and the local staff-preview fader; it does not send a volume mutation to the server or alter the controller's `ServerMusicSound.Volume` / server-owned `MusicGroup.Volume`.

This preserves one shared playback source while allowing each client to apply its own local gain. If the module is absent, the renderer uses the same local SoundGroup fallback. Preference state remains session-local and resets when the UI is remounted or the player rejoins; persistence and additional sound-profile controls are not part of this integration. The profile field in the preference module does not currently add EQ/effects.

The renderer cleans up the preference manager on both explicit UI destruction and GUI destruction. Staff preview gain follows the same local volume setting.

**Validation boundary:** source changes and package contents can be checked in GitHub, but client-local SoundGroup behavior, device output, mute/restore behavior, and two-client volume independence still require Roblox Studio testing with two clients. Do not remove the legacy `ServerMusicSound` or `MusicGroup`.


## Crossfade coordinator hardening — phase 5

The standalone `ClubMusicAudioCrossfadeManager` now invalidates its generation before cancellation, stops and cleans the incoming deck defensively, restores outgoing gain after an interrupted or failed fade, validates the incoming deck contract, and protects deck calls and transition callbacks with `pcall`. It also checks that the same incoming deck still owns the active transition before committing.

The controller must provide an atomic `OnCommit` callback: it must transfer playback ownership completely or return false without partially changing ownership. This manager update does **not** connect crossfade to the live controller, create a second active output, or change the legacy `ServerMusicSound` path. Crossfade remains opt-in and inactive until a coordinated dual-deck controller cutover covers skip, clear, pause, restart, reconciliation, watchdog, and shutdown.

The server RBXMX package is refreshed with this exact manager source. Reinstall it by dragging the updated `ClubMusic_Audio_Server_Modules.rbxmx` into Studio and replacing the existing module folder contents as appropriate; do not import the standalone manager into a second active copy.

Static checks cover cancellation invalidation, gain restoration, protected deck calls, incoming-deck ownership checks, and package/source parity. Roblox Studio playback and interruption tests have not been run.


## Controller transition-cancellation seam — phase 6

The server controller now exposes one optional `cancelAudioTransition(reason)` hook. It safely calls `ChildManagers.Crossfade:Cancel()` only when a crossfade manager is present; otherwise it is a no-op and does not change legacy playback.

Cancellation is requested before controller-owned track advances, track replacement, local/global pause or resume, local/global restart, queue clear, global restart reconciliation, and server shutdown. The existing generation/transition locks and `ServerMusicSound` playback path remain authoritative. This creates the interruption boundary needed by a later dual-deck cutover without constructing or enabling a second audio output now.

This phase does not instantiate the crossfade manager and does not enable crossfade. Queue-clear cancellation intentionally affects only an in-progress transition; it does not stop the currently playing track. The cancellation hook logs a warning if an installed manager reports a failure, but the legacy playback path continues.

Static source checks were performed after commit. Roblox Studio playback, crossfade interruption, and multiplayer tests remain outstanding.
