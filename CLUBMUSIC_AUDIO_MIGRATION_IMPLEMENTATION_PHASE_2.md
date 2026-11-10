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
