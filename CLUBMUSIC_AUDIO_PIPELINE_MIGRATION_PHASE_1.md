# ClubMusic Audio Pipeline Migration — Phase 1

## Purpose

Define a safe migration from the current controller-owned `Sound` / `SoundGroup` path to Roblox's modular audio graph. This phase is an architecture and retirement-gate document; it does not replace the active playback backend or delete existing audio instances.

## Current source-of-truth

- `UI_Server_Controller_server (1).lua` creates/reuses `SoundService.MusicGroup` and `SoundService.ServerMusicSound`.
- The controller owns playback state, queue transitions, pause/restart/skip, asset validation and the playback watchdog.
- `ServerMusicAudioHandler.luau` is a non-owning adapter around the canonical `Sound`.
- `MusicPlaybackManager.luau` is a controller facade and its quality inspection is observational.
- Creator Hub request validation currently creates a temporary `Sound` named `AudioProbe` for `ContentProvider:PreloadAsync`. This is a separate legacy dependency that must also be migrated before removing all Sound instances.
- Existing clients and UI state synchronization must continue to work during the migration.

## Target audio graphs

### Shared, non-positional club music

`AudioPlayer -> AudioFader -> AudioDeviceOutput`

Use one controller-authoritative track/transition state. The shared output is for all players; do not create an output per player unless the experience explicitly needs isolated player routing.

### Per-player preferences

`AudioPlayer -> per-player AudioFader -> AudioDeviceOutput(Player = player)`

The per-player fader/output path must be isolated so one player's volume or EQ choice cannot change another player's sound. Do not implement player preferences by mutating the shared server Sound/SoundGroup volume.

### Crossfade

Use two AudioPlayers (current and incoming) with independently controlled AudioFaders. The controller remains the sole transition authority. Every transition must have a generation/token so a skip, stop, restart, queue clear, or newer transition cancels stale fade work. Crossfade remains disabled until multi-client timing and cancellation tests pass.

### Optional venue spatialization

`AudioPlayer -> AudioEmitter -> AudioListener -> AudioDeviceOutput`

Only enable this graph for explicitly configured venue speakers/zones. Verify listener placement and attenuation with multiple players at different positions. Do not silently change the existing experience from 2D/global to positional audio.

## Seven recommendation integration plan

| Recommendation | Safe integration boundary | Activation gate |
|---|---|---|
| Playback quality monitor | Controller-scheduled observations; ErrorHandler metadata only | Existing watchdog remains sole recovery owner |
| Track metadata | Validation/catalog normalized metadata; stable track IDs unchanged | Asset permission and preload checks still run for every request |
| DJ sessions/handoffs | Session metadata and authorized owner handoff; queue/playback remain controller-owned | Staff permission, connected-player validation, audit event and global/local ownership rules |
| Crossfade | Dual AudioPlayer + two faders; controller transition generation | Studio and multi-client transition/cancellation tests |
| Audio quality profiles | Whitelisted, bounded per-player or venue profiles; optional EQ/effects | No shared-user preference leakage; defaults preserve current sound |
| Player preferences | Per-player fader and AudioDeviceOutput routing | Preferences survive respawn/reconnect as designed; cannot alter other listeners |
| Spatial audio | Configured emitter/listener routing only | Venue-specific positional tests and explicit opt-in |

## Migration phases

1. Keep the current Sound backend as the active, known-good rollback path.
2. Add the new audio graph behind an explicit disabled feature flag. Do not create both backends as audible sources simultaneously.
3. Migrate asset loading/preload validation away from temporary Sound probes.
4. Add controller-owned AudioPlayer lifecycle, AudioFader transitions and output routing.
5. Add per-player output/fader isolation and verify one player's settings do not affect others.
6. Add optional spatial venue routing separately from shared 2D music.
7. Run Studio tests, then at least two-client and multi-client tests. Test load failures, private/disallowed assets, pause/resume, restart, skip, queue clear, server shutdown, respawn, player leave, and rapid consecutive transitions.
8. Observe the new backend over a release period with the old backend still available for rollback.
9. Remove legacy Sound objects only after the retirement checklist below is satisfied.

## Legacy Sound retirement checklist

Do **not** delete `SoundService.ServerMusicSound`, `SoundService.MusicGroup`, temporary probe Sounds, or any model-contained Sound/SoundGroup assets until all items are true:

- No active controller, adapter, preload/validation path, client, UI, or model script references `Sound`, `SoundGroup`, `SoundEffect`, `ServerMusicSound`, or `MusicGroup` for ClubMusic playback.
- New AudioPlayer graph is the only audible ClubMusic path; no duplicate playback occurs.
- Shared playback and per-player output routing work in Studio and live multi-client tests.
- Pause, resume, restart, skip, queue clear, playlist rotation, asset validation, error reporting, and server shutdown are verified on the new path.
- Crossfade cancellation cannot resurrect an old track after skip/restart/clear.
- A rollback procedure exists and has been tested before the old instances are deleted.
- Any remaining Sound/SoundGroup instances are confirmed unrelated to ClubMusic and are not removed.

## Current status

- Passive playback quality inspection is connected to the existing watchdog; controller remains the recovery owner.
- Creator Hub audio metadata is normalized, while the controller still performs actual preload/playability checks.
- The active backend is still `Sound` / `SoundGroup`.
- Crossfade, DJ session ownership/handoff, per-player output routing, audio quality effects, and spatial routing are not yet active.
- No Roblox Studio or multiplayer runtime validation is claimed by this source-only phase.

## Official API reference

- Roblox modular audio objects: https://create.roblox.com/docs/audio/objects
- AudioPlayer: https://create.roblox.com/docs/reference/engine/classes/AudioPlayer
- Wire: https://create.roblox.com/docs/reference/engine/classes/Wire
- AudioDeviceOutput: https://create.roblox.com/docs/reference/engine/classes/AudioDeviceOutput
