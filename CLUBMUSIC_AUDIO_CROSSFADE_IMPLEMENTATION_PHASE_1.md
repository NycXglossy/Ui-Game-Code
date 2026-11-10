# ClubMusic Automatic Crossfade — Implementation Phase 1

Branch: `audit/hardened-clubmusic-2026-11-08`

## Implemented

### Automatic local queue transition
- The controller checks the next local queue entry during its existing one-second playback clock.
- When a valid next-track asset is queued and the current track enters the 14-second preparation window, the crossfade manager creates a muted incoming AudioPlayer deck and assigns the next asset.
- The manager waits for incoming asset readiness (maximum 8 seconds) before changing either deck's gain.
- It waits until the current track has 4 seconds remaining before starting the 4-second linear fade.
- The controller commits only if the prepared entry is still exactly the first queue item and the current track token/source are unchanged.
- Successful commit pops that exact entry through MusicQueueManager, preserving normal request-slot release, transfers active audio ownership to the incoming backend, updates now-playing metadata without restarting the incoming deck, and schedules queue refill/state publication.
- The existing ordinary advance remains the fallback if preparation fails, the queue changes, the fade is cancelled, or the boundary grace period expires.

### Safety and cancellation
- Existing skip, pause/resume, restart, queue clear, track replacement, source adoption, global reconciliation, and shutdown cancellation hooks remain in place.
- The incoming deck starts muted.
- Outgoing gain is captured and restored on cancellation/failure.
- A 2-second boundary grace period allows a fade that has reached the end to finish its ownership commit but prevents a stuck transition from blocking normal advance.
- Tracks without valid audio assets, silent catalog entries, and tracks too short for the configured fade are not crossfaded.
- Failed queue-pop or source-binding commits restore the outgoing source before the manager's cancellation restores its gain.

### Timing
- Preparation lead: 14 seconds.
- Fade duration: 4 seconds.
- Incoming asset readiness timeout: 8 seconds.
- Boundary commit grace: 2 seconds.

## Deliberate scope boundary

Automatic crossfade currently runs only in local queue mode. It is deliberately skipped when the cross-server global queue is authoritative. That mode needs a distributed reservation/commit protocol so every server can fade to the same authoritative next track without competing to advance the global queue or reverting to the legacy source during reconciliation.

## Files changed
- `UI_Server_Controller_server (1).lua`
- `ClubMusicAudioCrossfadeManager.luau`
- `ClubMusic_Audio_Server_Modules.rbxmx` (embedded manager source refreshed)

The server RBXMX package's embedded crossfade module was checked against the standalone module and is byte-for-byte identical.

## Validation status

Repository source checks passed:
- Single forward declarations for queue, queue manager, global mode, now-playing state, and state publisher.
- Automatic transition is restricted to local queue mode.
- Exact prepared queue entry is checked again at commit.
- Incoming ownership is transferred without restarting the prepared deck.
- Cancellation and bounded fallback paths remain present.
- Packaged and standalone crossfade module sources match.

Not yet performed:
- Roblox Studio runtime playback test.
- Two-client audible crossfade test.
- Asset permission/buffering test.
- Manual skip, pause, clear, and shutdown interruption tests during an active fade.

Do not treat this as runtime-validated or enable modern backend migration solely because this crossfade source work is committed. Existing legacy playback remains the default source outside a successful crossfade transition.
