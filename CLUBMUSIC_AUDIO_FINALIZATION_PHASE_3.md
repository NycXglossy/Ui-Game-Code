# ClubMusic Audio Finalization — Six-Update Workstream

Branch: `feature/sultan-settings-2026-11-10`

## Update 1 — Guarded modern main-playback migration

Implemented:
- `CONFIG.UseModernAudioBackend = true`; the user-confirmed Studio log records successful controller ownership handoff to the modern AudioPlayer.
- Added a one-time, deferred migration attempt after the first valid track starts when the flag is explicitly enabled.
- The controller constructs the optional AudioPlayer backend and uses the existing guarded `adoptAudioBackend` handoff.
- Candidate preparation, asset readiness, playhead transfer, source revision checks, gain preservation, rollback, and cleanup remain inside the controller handoff.
- Missing modules, failed readiness, or failed handoff leave the legacy Sound as the active source.

Not yet release-enabled:
- The modern source handoff has been confirmed in Studio. Keep the legacy Sound only as a temporary startup/emergency compatibility source until the modern-only route and recovery have passed multiplayer testing.
- Do not delete `ServerMusicSound` or `MusicGroup` until the remaining compatibility paths and rollout are validated.

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
- MusicGroup is adjusted only on the local client as a temporary legacy Sound fallback, never as the modern volume path.
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

1. With the default flag off, verify legacy Sound playback is unchanged.
2. Enable `UseModernAudioBackend` only in a test place; verify first-track handoff, asset readiness, position continuity, pause preservation, and that only one main output is audible.
3. Force missing-module, invalid-asset, timeout, and candidate-start failures; verify the legacy bootstrap remains safe. Then force a modern decoder reload failure and verify the controller rebuilds a replacement AudioPlayer without changing queue ownership or track position.
4. Test crossfade cancellation for skip, clear, pause, restart, source reconciliation, and server shutdown; verify outgoing gain restoration and no duplicate outputs.
5. With two clients, independently change volume and mute; verify each listener hears only their own local gain while the server-controlled crossfade affects both equally.
6. Apply all four EQ profiles on the modern backend and verify band changes and profile rollback on failure.
7. Test spatial route creation/removal in a dedicated venue test with the intended listener placement.
8. Inspect client and server Output during player join/leave, track changes, queue clear, pause/resume, and server shutdown.

## Current release decision

- Source changes committed: guarded modern migration, EQ graph/profile support, spatial graph hardening, and local profile validation.
- Modern recovery now rebuilds a replacement AudioPlayer after an in-place decoder reload failure; client volume now routes through per-player AudioFaders and outputs.
- Not claimed complete: automated failure-injection validation, multi-client volume independence, client audio routing on all devices, and spatial venue behavior.
- Keep the legacy Sound and MusicGroup only as temporary compatibility objects until the modern routing and recovery gates pass.
