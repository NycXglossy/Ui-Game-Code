# ClubMusic Automatic Crossfade — Implementation Phase 2

Branch: `audit/hardened-clubmusic-2026-11-08`

## Implemented

### Local and global queue crossfade
- Automatic crossfade preparation now runs for both local queue mode and authoritative global queue mode.
- Each server prepares the same current global queue-head entry using the same validated asset ID.
- Global preparation captures the authoritative track revision and a frozen absolute end-time derived from the global playback anchor. Servers use `Workspace:GetServerTimeNow()` against that deadline so their fade windows are aligned instead of depending only on each server's one-second local elapsed counter.
- The global queue transition calls the existing `AdvanceGlobalQueue` transaction with the captured track revision and the exact prepared queue-entry ID.
- `MusicGlobalQueueService:Advance` now validates that the expected entry is still the authoritative queue head inside the same DataStore `UpdateAsync` transaction that advances the track. A queue reorder/removal cannot cause a server to commit a different track using the prepared deck.
- The first server to win the track-revision CAS advances the shared queue. Other servers accept the transition only when the returned/reconciled authoritative current entry has the exact same entry ID and a newer track revision. They do not pop the local mirror or issue a second advance.
- Global snapshot reconciliation preserves an in-flight prepared deck when it sees that exact prepared entry become the authoritative current track. It avoids restarting/seeking the outgoing legacy source during the local fade handoff.
- After the fade, each server transfers its local controller audio ownership to its incoming AudioPlayer deck and updates now-playing state without restarting the incoming track.
- Local queue mode retains its exact-entry local pop behavior.

### Safety and fallback
- A second normal track advance is held while the crossfade manager is completing its commit, avoiding a race between the fade and the playback clock.
- A global queue-head change, stale track revision, failed CAS, unavailable global service, or unconfirmed authoritative entry causes the fade to cancel and restores the outgoing gain; normal global queue advancement remains the fallback.
- If the global CAS has committed but a local source stop/bind operation fails, the controller resumes the committed track on its existing active source, restores its captured gain, and cleans the prepared incoming deck rather than leaving that server on the previous song.
- Pause and restart reconciliation cancel prepared transitions rather than allowing a fade to continue across a changed playback state.
- Existing request queue, playlist rotation, skip, admin, and playback control ownership remain in the controller/global queue service. The crossfade manager does not own queue policy.

## Updated source files
- `UI_Server_Controller_server (1).lua`
- `MusicGlobalQueueService.lua`
- `ClubMusic_Global_Service_server_1.lua`

The standalone crossfade manager and its embedded server-package copy remain unchanged and were rechecked byte-for-byte.

## Runtime validation still required

Repository source checks passed for:
- Shared global playback deadline capture and use.
- Global CAS invocation with exact prepared entry identity.
- Atomic expected-next-entry validation in the global queue service.
- Bridge argument pass-through.
- Peer recognition of the already-committed exact entry.
- Snapshot preservation during an active handoff.
- Pause/restart cancellation and prevention of a competing normal advance.
- Local queue mode retaining its original queue-pop path.
- Standalone and packaged crossfade manager source equality.

Not performed by this repository update:
- Roblox Studio runtime playback test.
- Two-server / two-client synchronized global crossfade test.
- Asset permission, buffering, or late-readiness test.
- Manual skip, pause, queue reorder, queue clear, restart, and shutdown interruption tests during an active fade.

The existing audio system remains the playback baseline. This phase does not remove `ServerMusicSound` or `MusicGroup`, and it does not change `UseModernAudioBackend = false`. The old Sound source can still play normally and can be used as the outgoing source for a successful transition. Do not remove legacy audio objects or treat the crossfade as runtime-validated until the Studio and multi-server checks above pass.

## Studio source replacement
Update these existing source objects from the branch:
1. `ServerScriptService/UI_Server_Controller` from `UI_Server_Controller_server (1).lua`.
2. `ServerStorage/MusicGlobalQueueService` ModuleScript from `MusicGlobalQueueService.lua`.
3. `ServerScriptService/ClubMusic_Global_Service` Script from `ClubMusic_Global_Service_server_1.lua`.

Keep the existing audio modules in `ServerStorage/ClubMusicAudioModules` and keep the existing `ServerMusicSound` and `MusicGroup` objects. This phase requires replacing the three source scripts above; it does not require reinstalling the audio module package.
