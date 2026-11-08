# ClubMusic Architecture Integration (2026-11-08)

This branch adapts the supplied music-system behavior to the existing secured ClubMusic UI architecture.

## Runtime architecture

- `ReplicatedStorage/UI_Network`: client transport; only the existing `ClubMusicRemotes` contract is used.
- `ReplicatedStorage/UI_Renderer`: existing UI and DJ booth, now exposing staff pause/restart controls.
- `ServerScriptService/UI_Server_Controller`: authoritative queue, request validation, permissions, voting, playback clock, and replicated audio.
- `ServerStorage/ClubMusic_ReceiptHash` and `ClubMusic_Global_Service`: existing receipt and cross-server security infrastructure; unchanged by the music transport integration.

No `MusicRemotes`, `DispatchAction`, `DispatchEvent`, `MusicBroadcast`, `MusicUpdate`, or `RequestSync` runtime remotes are created. The uploaded RemoteEvent models are reference assets only and should not be installed as a second transport layer.

## Adapted behavior

- Server-owned non-positional Sound in `SoundService`, assigned to a `ClubMusic` SoundGroup, replicates the active track to players.
- Queue advancement starts the next track and resets playback position.
- Staff can skip, pause/resume, and restart the current track from the existing DJ booth. Pause/resume and restart use the existing global DJ MessagingService topic for best-effort cross-server synchronization; commands are not durably queued when MessagingService is unavailable.
- Playback elapsed time stops advancing while paused.
- Existing controller permissions, token buckets, action cooldowns, VIP/VVIP/Sultan request limits and priority, request lock/block moderation, auto DJ, queue management, and skip voting remain authoritative.
- Originating-server echoes of global DJ messages are ignored, preventing a local skip/clear/pause/restart from being applied a second time.
- Audio asset ID requests remain staff-only and continue through the existing inspection/validation path.
- Per-client volume continues to use the local replicated `ClubMusic` SoundGroup; it does not grant the client server playback control.

## Required configuration

In `UI_Server_Controller`, populate `CONFIG.SoundIds` with approved track IDs, keyed by the existing track IDs, for example:

```lua
SoundIds = {
    ["edm-0"] = "rbxassetid://YOUR_APPROVED_AUDIO_ID",
    ["pop-0"] = "rbxassetid://YOUR_APPROVED_AUDIO_ID",
},
```

The checked-in map is empty by default. A track without a configured sound ID remains visible in the UI and advances on the controller's configured duration, but it has no audible source. Ensure each audio asset is permitted for this experience.

## Source limitations / intentionally excluded assets

The supplied `Music Module` has an empty `MusicList`; its example song entries are commented out. The supplied `Music System` requires five child manager modules (`MusicQueueManager`, `MusicPlaybackManager`, `MusicValidationService`, `MusicSkipVoteManager`, and `MusicPlaylistManager`) that were not present in the repository tree. Consequently, the exact internals of those managers could not be ported or verified. Equivalent core responsibilities are retained in the existing secured controller rather than inventing missing module behavior or copying the source system's separate role authority.

The supplied `Audio Sound Count 1.rbxm` is now included in the integration as the playback Sound asset `ServerMusicSound`; despite its filename, the decoded Roblox model contains a Sound instance, not a counter script or counter module. Import it into Studio and parent it directly under `SoundService` (name must remain `ServerMusicSound`). The controller will use it and assign it to the `ClubMusic` SoundGroup. If omitted, the controller creates a fallback Sound with that name. The supplied `Music Group.rbxm` and five RemoteEvent models are not required at runtime; the controller creates/owns its own SoundGroup and uses its existing remotes.

## Installation

Use the existing branch's script placement:

1. Replace the existing `UI_Server_Controller` Script in `ServerScriptService` with `UI_Server_Controller_server (1).lua`.
2. Replace the existing `UI_Network` ModuleScript in `ReplicatedStorage` with `UI_Network.lua`.
3. Replace the existing `UI_Renderer` ModuleScript in `ReplicatedStorage` with `UI_Renderer (2).lua`.
4. Keep `ClubMusicBootstrap.client.lua` in `StarterPlayer/StarterPlayerScripts`.
5. Keep the existing `ClubMusic_Global_Service` and `ClubMusic_ReceiptHash` placements/configuration. No duplicate music remotes or role-system modules are needed.
6. Configure approved `SoundIds` and your existing pass/group/staff IDs before publishing.

Test in a private Roblox Studio multiplayer session first. Validate sound permissions, pause/resume, restart, automatic advancement, request priority, voting, moderation, and server shutdown behavior. This repository integration has been source-reviewed only; it has not been run in Roblox Studio or against live Roblox services.
