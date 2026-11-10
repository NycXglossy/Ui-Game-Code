# ClubMusic Audio Migration — Phase 1 Inventory and Safe Cutover Plan

Date: 2026-11-10
Branch: `audit/hardened-clubmusic-2026-11-08`

## Status

This phase records the verified source dependencies and defines the safe migration boundary. It does **not** switch production playback to the modern audio graph and does **not** delete legacy audio instances. The existing Sound/SoundGroup path remains the active fallback until the replacement is integrated and validated in Roblox Studio.

## Current legacy dependencies verified in source

| Area | Current dependency | Required migration |
|---|---|---|
| Canonical playback | `SoundService.ServerMusicSound` | Replace with controller-owned `AudioPlayer`; preserve one authoritative playback state |
| Shared mix | `SoundService.MusicGroup` | Replace with an `AudioFader` in the audio graph |
| Server adapter | `ServerMusicAudioHandler` requires a canonical `Sound` and reads Sound properties | Generalize the adapter to an audio-backend contract without creating a second playback owner |
| Playback facade | `MusicPlaybackManager` returns/inspects a `Sound` | Change quality inspection to use backend-neutral state |
| Controller transitions | Start, stop, pause, resume, seek, state reconciliation, watchdog, and restart paths directly access `musicSound` | Route all operations through one controller-owned backend; do not leave mixed Sound/AudioPlayer control paths |
| Asset validation | `inspectAudioAsset` creates a temporary `Sound` named `AudioProbe` and calls `ContentProvider:PreloadAsync` | Replace with a bounded AudioPlayer readiness/permission validation path and preserve timeout/concurrency cleanup |
| Client volume | `UI_Renderer (2).lua` applies volume through `Network.SetVolume` or local `SoundService.MusicGroup.Volume` | Move to the local audio graph/fader; never change a shared server gain to implement one player's preference |
| Staff preview | `UI_Renderer (2).lua` creates `AudioPreview` as a temporary `Sound` | Migrate preview separately to a local AudioPlayer graph and preserve cleanup/cancellation behavior |
| Legacy group cleanup | Controller migrates ClubMusic-routed Sounds to MusicGroup, then destroys the old group | Remove only after all old SoundGroup routing has been migrated and verified |

## Target graph

For shared 2D music, the target graph is:

`AudioPlayer -> AudioFader -> AudioDeviceOutput`

A `Wire` connects each adjacent pair. The server remains the single authority for track selection, queue state, transitions, and playback commands. The new audio graph is not a second queue or playback controller.

For per-player volume, the client must own a local gain stage/output path. A shared server-side gain cannot represent different volume preferences for different players.

For crossfade, two AudioPlayers and two independently controlled gain stages are required. The controller must own the transition token/cancellation and must ensure only one transition can commit the next track. A one-player swap or an independent module heartbeat is not a safe crossfade.

For spatial audio, the graph must be intentionally routed through AudioEmitter/AudioListener objects. This is a separate venue-mode feature and must remain optional; it is not a drop-in replacement for shared 2D music.

## Roblox API notes used for the design

- Use `AudioPlayer.Asset`; `AssetId` is deprecated.
- `AudioPlayer.IsReady` is the readiness signal; `IsPlaying`, `TimePosition`, and `TimeLength` support passive state inspection.
- `AudioPlayer.Play()` and `Stop()` are documented playback controls. The current AudioPlayer API does not expose Sound-style `Pause()`/`Resume()`; pause behavior must be explicitly implemented and tested by preserving the playhead and stopping/restarting, or by another verified design.
- `AudioFader` supplies a gain stage; `Wire` connects audio graph nodes.
- `AudioDeviceOutput.Player` can target an individual player; leaving it unset outputs to everyone. Per-player preference routing therefore needs a client-aware design rather than a shared global volume mutation.

## Cutover gates — all required before deleting legacy models

1. Backend adapter covers play, stop, pause/resume semantics, seek, current position, duration, playing/ready state, volume, and cleanup.
2. Controller has exactly one active backend and one transition authority; all direct legacy Sound references are removed or intentionally isolated to fallback code.
3. The temporary AudioProbe path is migrated; asset validation still checks readiness, experience permissions, timeouts, and bounded concurrency.
4. UI volume and staff preview work on the new graph; preview instances and wires are always cleaned up.
5. Queue advance, skip, clear, restart, pause, server reconciliation, watchdog recovery, and error reporting work with the new backend.
6. Cross-server synchronization and multiple-player listening are verified in Studio with at least two clients.
7. Audio permissions, device output routing, late joins, asset load failures, and fallback behavior are tested.
8. The feature flag is enabled only after those tests pass; legacy Sound/SoundGroup objects are removed in a later cleanup commit after a stable test window.

## Current decision

Keep `ServerMusicSound`, `MusicGroup`, `AudioProbe`, and `AudioPreview` for now. The controller and renderer still directly depend on them. Removing them now would break core playback, validation, volume, or preview behavior. This phase is an inventory and migration contract, not a claim that the modern backend is already active.
