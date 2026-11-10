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


## Crossfade gain-contract hardening — phase 7

The crossfade manager now requires the controller context to provide `SetOutgoingGain` at construction. Previously this callback was optional, which meant the incoming deck could fade from zero to full gain while the outgoing deck remained at full gain. That would create overlapping full-volume playback rather than a controlled crossfade. The manager now refuses to initialize without an explicit outgoing-deck gain controller, and the gain helper fails closed if that callback is ever missing or errors. This is a fail-fast contract check; it does not construct decks, instantiate the manager in the live controller, or activate crossfade.

The standalone module and `ClubMusic_Audio_Server_Modules.rbxmx` package are synchronized. The legacy `ServerMusicSound` remains the only live main-playback output. Controller ownership, pause/seek/watchdog/reconciliation routing, atomic deck adoption, and Roblox Studio validation are still required before enabling crossfade.


## Dual-deck controller ownership audit — phase 8

The next cutover was deliberately held at the ownership boundary after inspecting the complete current controller source. The live controller still has 37 textual `musicSound` references spanning these responsibilities:

- Canonical instance creation, SoundGroup assignment, gain/speed defaults, managed attributes, and the active-sound counter.
- Track start/stop and SoundId replacement.
- Global playback reconciliation, elapsed-position correction, pause, resume, and stop.
- Local pause/resume position capture and restoration.
- Global pause/resume position restoration.
- Playback watchdog state/length inspection and error-report context.
- The existing `ServerMusicAudioHandler` and `MusicPlaybackManager` callbacks, which still expose the canonical Sound.

The backend module creates a global `AudioDeviceOutput` when no target Player is supplied. The current main output is also server-wide. Constructing a modern deck before controller ownership and every playback/inspection path are redirected would therefore create two audible sources. A crossfade manager alone cannot make this safe: its outgoing-gain callback and commit callback must operate on the exact active deck, while the controller's watchdog, reconciliation, pause/resume, seek, and playback snapshot must all follow that same deck after commit.

The current `ActiveMusicSoundCount` is also tied directly to the legacy Sound's `Playing` signal and assumes one controller-managed Sound. That diagnostic must be made backend-neutral before an AudioPlayer can become canonical; otherwise the published count becomes inaccurate during and after handoff.

**Phase 8 decision: no second deck is instantiated and no playback route is switched.** The legacy Sound remains the sole live main-playback source. The next implementation must introduce a controller-owned active-deck contract and migrate all listed operations to it as one coordinated change, including failure rollback and cleanup of the outgoing deck after a successful atomic commit. The transition must not be enabled until that migration is complete and validated in Roblox Studio with multiple clients.

Static audit only. No Roblox Studio runtime, audio-output, interruption, or multiplayer tests were run.


## Backend-neutral playback facade inspection — phase 9

The controller-owned `MusicPlaybackManager` now prefers the injected `GetAudioSnapshot` contract for both `IsPlaying()` and elapsed-position fallback. It uses the legacy `Sound` accessor only when a usable snapshot is unavailable. This removes two read-only facade dependencies on a concrete Sound instance and lets future controller injection expose an AudioPlayer-backed snapshot without changing callers of the facade.

The existing controller still injects its canonical `ServerMusicSound`, and the controller's own play/stop/pause/resume, seek, reconciliation, watchdog, and SoundGroup routing paths remain unchanged. This is a compatibility improvement, not a playback cutover: no AudioPlayer deck is constructed, no second output is started, and crossfade remains disabled.

Static source checks confirmed the snapshot-first paths and retained Sound fallback. Roblox Studio playback and multiplayer validation have not been run.

## Controller-owned active audio source facade — phase 10

The server controller now defines one source contract (`activeAudioSource`) and routes its core playback operations through controller-owned functions rather than hard-coding the legacy Sound in each operation. The migrated paths include:

- Start/stop and asset assignment.
- Global playback reconciliation and position correction.
- Local and global pause/resume and seek.
- Watchdog playing/readiness/length inspection.

The source contract currently points only to the existing marked `SoundService.ServerMusicSound`. It exposes backend-neutral snapshot fields (kind, readiness, playing, paused, position, length, asset) and operation seams for a future injected backend. The existing Sound setup, SoundGroup routing, and Playing-change counter signal remain in place; no AudioPlayer backend is instantiated, no source ownership switch is exposed, and crossfade remains inactive.

`ServerMusicAudioHandler:GetCurrentSoundId()` now reads the adapter snapshot's asset field rather than requiring a concrete Sound. This makes that facade query consistent with the new source snapshot.

**Safety boundary:** this is an adapter-routing phase, not the modern audio cutover. The backend branch is dormant and must not be enabled until an atomic source-adoption/rollback path is implemented and Studio multiplayer testing verifies there is never duplicate output. No Roblox Studio runtime or multiplayer tests were run.
## Guarded active-source adoption and backend-neutral diagnostics — phase 11

The controller now has an explicit, dormant `adoptAudioBackend(candidate)` handoff seam. It validates the candidate's required backend methods and AudioPlayer, assigns the current asset, waits up to eight seconds for that exact asset to become ready (aborting and cleaning up if the current track changes), transfers the playhead, starts the candidate at zero gain, preserves paused/playing state, then stops the outgoing source before restoring incoming gain. If the outgoing stop or incoming gain commit fails, it switches the controller reference back and attempts to restore the previous source/playhead. An outgoing modern backend is cleaned up only after a successful commit.

The controller's active-output count now follows the active source and rebinds its playing-change signal when the source changes. The legacy Sound listens to its `Playing` property; an AudioPlayer listens to `IsPlaying`. The `ServerMusicAudioHandler` and `MusicPlaybackManager` now receive a dynamic Sound accessor plus the controller snapshot, so their legacy fallback does not point at a retired Sound after a future cutover.

**No cutover is performed in this phase.** The controller does not construct `ClubMusicAudioBackend`, does not call `adoptAudioBackend`, and does not instantiate crossfade. `ServerMusicSound` remains the live source and the existing MusicGroup route remains intact. This handoff seam is source-integrated only; it still needs static review and Studio validation of asset readiness, paused transfer, failure rollback, event counts, output routing, and multi-client behavior before being called from production flow.

No Roblox Studio runtime or multiplayer tests were run.

## Handoff race and rollback hardening — phase 12

A focused review of the dormant handoff against the actual ClubMusicAudioBackend contract found several edge cases. The controller handoff now:

- Tracks an audio-source revision and invalidates a pending handoff when the controller changes the asset, stops, starts, pauses, resumes, plays, or seeks the outgoing source while the candidate is loading.
- Rechecks source identity, asset, revision, and paused state after the readiness wait and immediately before stopping the outgoing source. This prevents a same-asset restart or a playhead mutation from being mistaken for an unchanged playback session.
- Allows an already-paused current track to transfer; previously, the playing == false snapshot caused paused playback to be rejected.
- Restores the outgoing source at the captured playhead on rollback, including re-applying the paused state for both the legacy Sound and a modern backend.
- Cleans up the incoming candidate on failed preparation/commit, and rejects an attempt to adopt the already-active backend.

The backend contract confirms that Play(nil, position) is supported after SetAsset(asset), and that Pause() preserves its position in backend state before stopping the AudioPlayer. This phase therefore fixes controller-side contract and lifecycle handling without changing the backend module or its package.

**Safety boundary remains unchanged:** the backend is still not constructed by the controller, the adoption seam is still not called automatically, the legacy ServerMusicSound remains the only live main output, and crossfade remains disabled. These are static source changes only; asset readiness, actual audio output, rollback behavior, and multiplayer behavior still require Roblox Studio validation before cutover.

## Crossfade readiness gate — phase 13

The standalone crossfade coordinator and the server RBXMX package now require incoming decks to expose SetAsset and IsReady. A transition first mutes the incoming deck, assigns the requested asset, and waits up to eight seconds for readiness before starting playback and beginning the fade. If readiness times out or the operation is cancelled, the incoming deck is stopped and cleaned up while the outgoing controller-owned deck is restored to full gain. This prevents a buffering AudioPlayer from causing the currently audible track to fade prematurely.

The manager remains dormant: the server controller does not instantiate it, no crossfade is started, and the existing ServerMusicSound remains the live main output. No Roblox Studio playback or multiplayer tests were run; this change is source/package preparation only.


## Crossfade gain-profile preservation — phase 14

The crossfade coordinator now requires a controller-provided `GetOutgoingGain()` callback in addition to `SetOutgoingGain()`. It captures the outgoing deck's validated gain (finite, between 0 and 1) before starting, scales both decks against that baseline during the fade, restores that exact baseline on cancellation/failure, and leaves the incoming deck at the same baseline after commit. This avoids silently restoring full gain or overwriting a reduced gain profile when a transition is interrupted.

The standalone module and `ClubMusic_Audio_Server_Modules.rbxmx` embedded source are synchronized and were verified byte-for-byte after update. This remains preparation only: the controller does not instantiate crossfade, no dual-deck transition is active, and the legacy `ServerMusicSound` remains the live main output. The controller callback wiring and Studio validation are still required; no Roblox Studio runtime or multiplayer tests were run.


## Controller-owned gain interface — phase 15

The server controller now exposes backend-neutral `getAudioGain(sourceOverride?)` and `setAudioGain(value, sourceOverride?)` helpers. They validate the active source and constrain gain to a finite 0–1 range; the legacy Sound path reads/writes `Sound.Volume`, while the modern backend path uses its fader. The modern backend now exposes `GetGain()` for this contract.

The dormant backend-adoption path now captures the outgoing source gain before preparing the candidate and applies that same gain after the outgoing source is stopped, instead of forcing the incoming backend to gain 1. The server RBXMX package embeds the updated backend module and was verified byte-for-byte against its standalone source.

These interfaces prepare the controller callbacks required by crossfade (`GetOutgoingGain` / `SetOutgoingGain`), but the crossfade manager is still not instantiated or connected. The legacy `ServerMusicSound` remains the sole live main output. Source and package parity were verified in GitHub; no Roblox Studio runtime or multiplayer tests were run.


## Dormant controller-owned crossfade factory — phase 16

Added `ControllerFunctions.createAudioCrossfadeManager()` as an explicit, dormant factory. It validates the installed server audio module folder, requires the backend and crossfade ModuleScripts only when explicitly called, and constructs the manager with controller-owned callbacks. The deck factory creates isolated modern AudioPlayer decks under SoundService; outgoing gain reads/writes route through the controller's backend-neutral gain helpers.

Ownership and revision guards are captured when a transition begins (when the manager requests the outgoing gain), not when the factory is created. Every outgoing gain update is rejected if the active source or source revision changes. The commit callback revalidates ownership and pause state, validates the incoming AudioPlayer, transfers the controller's active source, increments its revision, rebinds the playing signal, and cleans up a previous backend only after ownership transfers. The factory itself is never called at startup, and no crossfade is started by this change.

This is controller wiring preparation, not activation. Existing `ServerMusicSound` remains the live source unless a future explicit, tested transition is invoked. GitHub source was fetched again after update and verified; no Roblox Studio runtime or multiplayer tests were run.


## Muted-at-construction crossfade decks — phase 17

Hardened the incoming-deck creation path against a brief audible startup window. `ClubMusicAudioBackend.new` now accepts an optional `InitialGain` setting, clamps it to 0–1, and applies it to the AudioFader before the graph is connected for playback. The controller's crossfade deck factory passes `InitialGain = 0`, so a newly created incoming deck is silent from construction rather than relying on a later `SetGain(0)` call to mute it.

The standalone backend and the embedded ModuleScript source in `ClubMusic_Audio_Server_Modules.rbxmx` were verified byte-for-byte after the update. The controller source was re-fetched and verified. This remains dormant preparation; no crossfade activation or Studio runtime test was performed.


## Crossfade commit cleanup and rollback — phase 18

The controller's crossfade commit callback now validates that the incoming AudioPlayer is actually playing before ownership transfer. It snapshots the outgoing playhead, stops the outgoing Sound or backend before switching the active-source reference, and refuses to commit if the outgoing source cannot be stopped. If rebinding the active playback signal fails, it restores the outgoing source reference and attempts to restart the previous source at its captured position; the transition manager can then cancel and restore the captured outgoing gain. After a successful bind, the controller increments the source revision and cleans up a retired backend. This prevents a successfully crossfaded legacy Sound from continuing to run silently at zero gain and reduces the chance of a failed commit leaving two live sources.

The change remains dormant: the crossfade manager is not constructed at startup and no transition is automatically started. Existing ServerMusicSound remains the live output until an explicitly invoked, Studio-validated cutover. GitHub source was re-fetched and compared after the update. No Roblox Studio runtime, playback, cancellation, or multiplayer tests were run.


## Optional crossfade manager teardown — phase 19

Added an explicit controller-owned `destroyAudioCrossfadeManager(reason)` lifecycle method. It safely no-ops when no manager exists, calls the manager's `Cleanup()` under protection, and removes the manager registry entry only after successful cleanup. Server shutdown now invokes this teardown method instead of cancellation alone. The manager cleanup invalidates any pending generation, stops and destroys an incoming deck, restores the outgoing gain while the controller still owns that source, and releases its context. The feature remains opt-in and dormant; no manager is constructed at startup and the legacy Sound remains the live output. Controller source was re-fetched and compared after the update. No Roblox Studio shutdown, playback, or multiplayer runtime tests were run.


## Guarded explicit crossfade entry point — phase 20

Added `ControllerFunctions.beginAudioCrossfade(asset, duration)` as a deliberately explicit entry point. It requires an already-constructed optional crossfade manager, active non-paused playback, a numeric Roblox asset URI, and a duration from 0.25 through 12 seconds. It invokes the manager under `pcall` and returns a clear rejection rather than changing queue state or falling back to a second playback path. No automatic call sites were added. This is an integration seam for future UI/controller use, not permission to enable crossfade in production before Studio and multiplayer validation. The existing Sound remains canonical unless a caller explicitly initializes the manager and requests a transition. Source was re-fetched and compared after the update; no Roblox runtime tests were run.


## Cancellation and teardown failure reporting — phase 21

The crossfade manager now reports failures from incoming-deck stopping/cleanup and outgoing-gain restoration instead of always reporting cancellation success. Its `Cleanup()` method returns the cancellation result while still invalidating the transition and releasing its context. The controller's explicit destroy method now checks and reports a false cleanup result as well as thrown errors. The server package `ClubMusic_Audio_Server_Modules.rbxmx` was updated, and the embedded `ClubMusicAudioCrossfadeManager` source was re-extracted and verified byte-for-byte against the standalone module. The crossfade remains opt-in and is not activated automatically. Static source/package verification only; no Roblox Studio runtime tests were performed.


## UI redesign foundation — phase 22

The client renderer now supports a responsive desktop side-rail navigation mode on sufficiently wide desktop viewports. In this mode, the existing destinations move from a horizontal tab strip into a vertically scrollable rail, while the content region shifts right and expands vertically. The selected destination is scrolled into view vertically. Mobile, tablet, console, VR, and narrower desktop layouts retain the existing horizontal navigation and content geometry. This is a layout-only migration: existing tab renderers, catalog/search, queue, playlists, staff tools, network actions, and player controls are preserved; no new remotes or duplicate services were introduced. The renderer source was re-fetched and compared after the update. No Roblox Studio viewport/device runtime tests were run.


## Desktop navigation hierarchy — phase 23

The wide-desktop rail now groups existing destinations under Listen, Festival, and Staff headings and adds a subtle divider between navigation and content. Group headings are shown only in side-rail mode; the compact horizontal navigation remains unchanged on smaller layouts. Existing permission visibility for Audio ID and Moderation is preserved, as are tab callbacks and scroll-to-selected behavior. No tab content or network contracts changed. Renderer source was re-fetched and compared after the update; no in-Studio layout validation was run.


## Active navigation state styling — phase 24

Added a narrow gold active-destination marker to the desktop side rail. It appears only for the selected tab in side-rail mode, while the existing selected background, icon, and label styling remains shared across layouts. The marker is hidden in compact horizontal navigation to avoid changing its geometry. This is presentation-only and preserves all existing tab routing and permission checks. Renderer source was re-fetched and compared after the update; no Studio visual test was run.


## Dedicated staff playlist destination — phase 25

Added a dedicated Playlists destination to the client navigation for authorized staff. It reuses the existing server-backed playlist manager UI and existing `GetMusicPlaylists`, create/play/delete/reorder/remove actions; it does not create another playlist store or remote. The All Tracks destination now focuses on the paginated catalog and retains the selected-playlist add-destination affordance, so staff can choose a playlist in Playlists and then add catalog tracks from All Tracks. The Playlists tab is hidden and guarded by the existing staff permission level. A native playlist-list icon was added to the navigation. Renderer source was re-fetched and compared after the update; no Studio permission/UI test was run.


## Dedicated live queue destination — phase 26

Added a Queue destination that displays the authoritative current-track snapshot and the complete upcoming queue, including requester/Auto DJ source, VIP priority, genre where known, and duration. Staff retain the existing move-up and remove actions on each queued item; listeners receive a read-only view. The Home page remains a compact now-playing/queue summary, while Queue provides the full queue workspace. The page reads the existing sanitized UI state and uses existing `DJMoveUp`/`DJRemove` actions; no new remote or queue implementation was added. Navigation grouping now places Queue with the listening destinations. Renderer source was re-fetched and compared after the update; no Studio or multiplayer UI test was run.


## Permission-aware navigation grouping — phase 27

The desktop rail now hides the Staff group heading for listeners without staff permissions, in addition to hiding the protected Playlists, Audio ID, and Moderation destinations. The heading reappears when the current state grants the existing staff permission level. No authorization logic moved client-side; server validation remains authoritative. Renderer source was re-fetched and compared after the update; no Studio permission transition test was run.


## Destroyed-manager registry recovery — phase 28

The controller now unregisters the optional crossfade manager after its `Cleanup()` call even when cleanup reports a resource failure. The manager's cleanup contract marks it destroyed and releases its context regardless of the cancellation result; leaving that dead object in `ChildManagers.Crossfade` would prevent a later safe reconstruction. Failures are still warned and returned to the caller, but the registry no longer retains an unusable manager. Controller source was re-fetched and compared after the update. No Roblox runtime test was run.


## Home-to-queue navigation — phase 29

The compact Home queue preview now includes a View All action that opens the dedicated Queue destination. It uses the existing local tab-render callback and does not send a network request or mutate queue state. This connects the dashboard summary to the full queue workspace without changing playback or staff permissions. Renderer source was re-fetched and compared after the update; no Studio interaction test was run.


## Playlist-to-catalog workflow shortcut — phase 30

When staff select a saved playlist in the dedicated Playlists destination, the page now shows the selected destination and an Add Tracks action. That action opens All Tracks, where the existing catalog cards use the selected playlist ID and existing `PlaylistAddTrack` network action. This reduces navigation friction while keeping playlist selection local and all edits server-authoritative. Renderer source was re-fetched and compared after the update; no Studio workflow test was run.


## Queue-to-catalog navigation — phase 31

The full Queue workspace now has a Browse shortcut in its section header, taking listeners and staff to the existing All Tracks catalog. This complements the Home-to-Queue shortcut and completes a simple dashboard → queue → catalog navigation loop without changing request validation or queue state. Renderer source was re-fetched and compared after the update; no Studio interaction test was run.

## Controller-owned crossfade coordinator initialization — phase 32

The server controller now initializes its optional crossfade coordinator after controller state and child-manager dependencies are ready. The startup path validates and requires the installed ClubMusicAudioBackend and ClubMusicAudioCrossfadeManager modules through the existing factory. Initialization failure is non-fatal and is reported clearly; the existing ServerMusicSound remains the active playback source.

Coordinator construction does not create an incoming deck, change volume, start playback, or alter queue progression. A transition still requires the explicit beginAudioCrossfade(asset, duration) controller entry point, with its existing playback, asset, duration, source-ownership, and rollback guards. The server RBXMX package was checked to contain both backend and crossfade ModuleScripts. GitHub source was re-fetched and verified; no Roblox Studio runtime, audio-output, cancellation, or multiplayer test was run.

## Home featured-genre discovery — phase 32

The Home dashboard now includes a horizontally scrollable set of featured genre shortcuts. Selecting a genre opens the existing All Tracks catalog with that genre filter applied and the search cleared. The shortcuts reuse the current catalog query and pagination flow; no new remote, catalog store, or playback path was introduced. Renderer source was re-fetched and verified; no Roblox Studio visual or interaction test was run.
