# ClubMusic Audio Finalization — Six-Update Workstream

Branch: `feature/sultan-settings-2026-11-10`

## Update 1 — Guarded modern main-playback migration

Implemented:
- `CONFIG.UseModernAudioBackend = true`; the user-confirmed Studio log records successful controller ownership handoff to the modern AudioPlayer.
- Track startup now constructs and prepares the modern AudioPlayer first; it waits for matching asset readiness, starts at the initial playhead, verifies `IsPlaying`, then commits source ownership and binds the source signal.
- A per-start token and source-revision guard prevent a late decoder completion from replacing a newer track or control action.
- The controller now starts modern AudioPlayer only. If construction, readiness, playback verification, or commit preparation fails, the source remains unavailable and no legacy Sound is started.
- Reload retries the current track through the same verified modern-only startup path when no AudioPlayer is active; active-backend reload can rebuild a replacement AudioPlayer.

Not yet release-enabled:
- The user has confirmed the modern-only playback revision works in Studio.
- The controller no longer creates, reads, writes, or plays `ServerMusicSound` or `MusicGroup`; it also no longer migrates the old `ClubMusic` SoundGroup.
- Existing place instances and the standalone legacy `Music Group.rbxm` asset are not automatically removed by a repository source change. Before deleting those place instances, confirm no unrelated scripts or sounds still reference the old group.

## Update 2 — Crossfade transition integration

Existing source foundation:
- Controller-owned crossfade manager factory and startup coordinator.
- Dual-deck readiness checks, gain capture/restoration, cancellation generation, ownership checks, atomic commit callback, rollback, cleanup, and cancellation hooks around skip/clear/restart/pause/shutdown.
- Explicit `beginAudioCrossfade(asset, duration)` entry point.

Remaining:
- Automatic queue-boundary crossfade is not enabled. The current local/global queue transition uses generation checks and, in global mode, authoritative cross-server compare-and-swap state. Automatically advancing the queue before the fade and publishing the new track snapshot must be coordinated with that authority; invoking the existing manual entry point alone is insufficient.
- Keep crossfade dormant until queue-transition semantics, failure recovery, and Studio interruption tests are completed. No second output is started by default.

## Update 3 — Independent player volume

Implemented:
- Renderer local preference integration now applies gain to a private client AudioFader and AudioDeviceOutput for each replicated main/crossfade deck, plus the local staff-preview fader.
- The server backend no longer creates a shared AudioDeviceOutput; its replicated MusicFader remains the shared transition-gain stage.
- The renderer's legacy MusicGroup lookup and volume fallback have been removed. Modern volume uses private client AudioFader and AudioDeviceOutput routes.
- Client preference profile names are restricted to Standard, Soft, Bass, and Night; failed profile application restores the previous selection.

Validation still required:
- Run two clients and confirm changing/muting one client's volume does not affect the other.
- Confirm mute/restore, slider drag, UI remount, player respawn, and staff preview cleanup.

## Update 4 — Real equalizer profiles

Implemented:
- Modern server graph now routes AudioPlayer → AudioEqualizer → MusicFader. Each client adds its own PlayerMusicGain AudioFader → AudioDeviceOutput route.
- Backend exposes bounded low/mid/high equalizer controls.
- Quality profiles now define actual EQ bands for Standard, Soft, Bass, and Night and call the injected SetEqualizer callback when provided.
- Server RBXMX package embeds the same backend and profile sources as the standalone files.

Boundary:
- The legacy Sound path does not gain this AudioEqualizer processing.
- EQ becomes audible only when the modern AudioPlayer graph is used and the profile adapter is connected to its SetEqualizer method. No global profile has been forced onto the live legacy source.

## Update 5 — Spatial audio safety

Implemented:
- Spatial graph builder validates AudioPlayer and AudioDeviceOutput endpoints; the shared modern 2D playback graph deliberately leaves the device output to each client.
- Route keys and world-space emitter/listener parents are validated.
- Route construction is protected and cleans partial objects on failure.
- Route removal and cleanup are idempotent.

Boundary:
- No spatial route is automatically created. A venue emitter location, listener policy, and output routing design must be explicitly supplied before enabling it.
- Spatial output must not be layered on top of the existing global output, or users could hear duplicate music.

## Update 6 — Studio and multiplayer validation

Not executed from the repository connection. Required release checklist:

1. In a test place, verify `UseModernAudioBackend` is enabled and the first track starts directly on AudioPlayer with matching asset readiness, playback verification, pause preservation, and only one audible main output.
2. Force missing-module, invalid-asset, timeout, and candidate-start failures; verify the source remains unavailable and no legacy Sound starts. Then use Reload Song and verify it retries modern startup without changing track identity or the saved playhead.
3. With an active AudioPlayer, force a decoder reload failure and verify the controller rebuilds a replacement AudioPlayer without changing queue ownership or track position.
4. Test crossfade cancellation for skip, clear, pause, restart, source reconciliation, and server shutdown; verify outgoing gain restoration and no duplicate outputs.
5. With two clients, independently change volume and mute; verify each listener hears only their own local gain while the server-controlled crossfade affects both equally.
6. Apply all four EQ profiles on the modern backend and verify band changes and profile rollback on failure.
7. Test spatial route creation/removal in a dedicated venue test with the intended listener placement.
8. Inspect client and server Output during player join/leave, track changes, queue clear, pause/resume, and server shutdown.

## Current release decision

- Source changes committed: guarded modern migration, EQ graph/profile support, spatial graph hardening, local profile validation, replacement AudioPlayer recovery, and per-player output routing.
- Studio validation: the user confirmed the modern recovery and independent client-volume updates are functional.
- The controller publishes `SoundService.ClubMusicAudioSourceKind` as `AudioPlayer` or `Unavailable`; it never selects `Sound` as an active source.
- The controller and renderer no longer contain legacy Sound playback or MusicGroup volume paths. Existing legacy instances in a place are now unused by these scripts, but must be checked for unrelated consumers before manual deletion.
- The user reports that the modern-only playback path works. Repository static checks confirm the legacy adapter references are absent; Studio execution was not performed by this repository workflow.
