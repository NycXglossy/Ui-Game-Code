# ClubMusic Six-Module Source Integration Audit

Date: 2026-11-09

## Source set inspected

All six files were retrieved from the repository `main` branch at upload commit `43e0cebb3e2b134915cdfce4e3686e276ae92f4d`:

| File | Blob SHA |
|---|---|
| `MusicPlaybackManager.luau` | `bcb68aebb7f919c026a9cebc2382651b9ef8ff38` |
| `MusicPlaylistManager.luau` | `c7e745fab10a62854c41174c2634e53829c771e0` |
| `MusicQueueManager.luau` | `d531a534728f21df2a4aa8af048f93c5159300cb` |
| `MusicSkipVoteManager.luau` | `c8f4361451cbf55d8a94ed470f71f0b14a945741` |
| `MusicValidationService.luau` | `13c9c254607faf8802e6a55c3b164f75670e7f9c` |
| `ServerMusicAudioHandler.luau` | `dddb7674e92ef66f0ac206c0ec0fabda846d2634` |

## Existing controller contract

The current hardened controller on `audit/hardened-clubmusic-2026-11-08` is a self-contained system. It owns the authoritative `queue`, request counts and VIP/VVIP/Sultan priority ordering, `nowPlaying`, skip-vote state, player permissions, request validation, and the `ClubMusicRemotes` contract (`RequestAction`, `StateChanged`, `Notice`, `GetState`). Its audio path uses the controller's configured track SoundIds and client playback/synchronization.

The six uploaded modules come from a different legacy contract. They cannot safely be dropped into the controller unchanged.

## Compatibility findings and required treatment

1. **MusicPlaybackManager** — broadcasts through `MusicBroadcast` and `MusicUpdate`, neither of which belongs to the current remote contract. It also owns a second current-song state. Adapt its playback lifecycle and progress reporting to the existing controller state and remotes; do not let it become a competing authority.
2. **MusicPlaylistManager** — hard-requires `ReplicatedStorage.Modules.MusicModule`. The current controller already owns `TRACKS`, `TRACK_BY_ID`, and `ALL_TRACK_IDS`; the uploaded dependency is not part of this six-file set. Replace the hard dependency with an injected catalog provider backed by the controller's catalog.
3. **MusicQueueManager** — maintains a second queue and per-player counters. Using it as an independent queue would bypass current priority insertion, request-slot release, moderation purges, and queue snapshots. Convert it to operations over the controller-owned queue or a narrow adapter; retain the controller as the only queue owner.
4. **MusicSkipVoteManager** — depends on the legacy RoleSystem hierarchy and dispatcher API, unlike the controller's existing skip-vote state and all-player vote ratio. Its timeout guard compares `self.skipVote.startTime` to itself, so an old timer can end a newer vote. It also needs explicit voter eligibility and vote-value validation. Adapt it to the controller's permissions and vote policy, and use a captured vote-generation token for timeout safety.
5. **MusicValidationService** — dynamically requires a legacy `ServerStorage.Modules.RoleSystem` and duplicates the controller's existing cooldown, spam, and audio inspection protections. Integrate only reusable validation/cache helpers through injected dependencies; do not replace or weaken the controller's token buckets, audio load checks, allowlist, or fail-closed behavior. Bound cache size and validate configuration before use.
6. **ServerMusicAudioHandler** — creates a Sound named `ServerMusicSound` in `SoundService` and destroys it during cleanup. This can conflict with the existing audio path or another owner of that Sound. It must be adapted behind the controller's playback authority, with explicit ownership and cleanup rules, rather than creating a second independently managed sound.

## Integration order

- Keep `UI_Server_Controller` the single authority for queue, playback metadata, skip votes, permissions, moderation, and state snapshots.
- Adapt all six uploaded modules to injected interfaces that match the current controller; no hidden requires to absent legacy modules and no new parallel remotes.
- Preserve VIP/VVIP/Tiki Tide Sultan queue priority, title slots, profile persistence, catalog behavior, and the existing client UI contract.
- Integrate in small steps, with static checks after each change. Do not declare runtime verification complete until Roblox Studio multiplayer tests cover playback, pause/resume, track end, late join, queue priority, skip voting, player departure, and invalid/private audio.

## Integration progress (2026-11-09)

- **MusicQueueManager: integrated as a shared-state adapter.** The controller requires `ServerStorage.MusicQueueManager`, injects its existing `queue` table and `releaseSlot` callback, and routes local queue insertion, pop/advance, moderation removal, staff removal, clear, and automatic-queue cleanup through the adapter. The adapter does not allocate a queue or per-player count table, so controller priority ordering, request-count ownership, snapshots, and global-queue mirror remain authoritative.
- Controller commit: `7e705364c775070557aed8a98e2c291783046983`.
- Module commit: `b98c863a1b80430a28b0e8bf4d1d103be247946c`.
- **MusicValidationService: integrated as a metadata-only cache adapter.** The adapted module accepts an injected Marketplace metadata provider, validates finite positive integer asset IDs, caches only successful normalized metadata, expires entries after 300 seconds, and enforces a 128-entry LRU bound. It contains no RoleSystem dependency, player cooldowns, spam counters, permission decisions, or playback behavior.
- Controller commit: `24076590e9d4a6c59b84ce791791328b47d19054`.
- Module commit: `3b36d5366c52b2805e6579deeb558e5f8f829551`.
- The controller still checks the asset type and creates/preloads a fresh AudioProbe on every inspection. Cache hits therefore do not bypass audio-load/playability verification, allowlists, staff checks, per-player cooldowns, global token budgets, or concurrent inspection limits.
- **MusicPlaybackManager: reviewed and intentionally not activated.** It creates a `ServerMusicAudioHandler` instance, owns a separate current-song/play/pause clock, binds a Heartbeat progress broadcaster, connects a second `Sound.Ended` transition callback, and broadcasts through legacy `MusicBroadcast`/`MusicUpdate` remotes that are not part of the current `ClubMusicRemotes` contract. The current controller already owns `SoundService.ServerMusicSound`, `nowPlaying`, `playbackPaused`, the generation-checked `advance()` transition, elapsed-time/watchdog loop, and `StateChanged` snapshots. Activating this module would create competing playback authority, a second Sound path, and duplicate track-end/progress behavior. Keep it out of ServerStorage; no controller playback or admin command changes are needed.
- **MusicPlaylistManager: reviewed and intentionally not activated.** The legacy module hard-requires `ReplicatedStorage.Modules.MusicModule`, which is not part of the current controller contract, and maintains its own `playlistIndex`, `shuffleMode`, and `playedSongs` state. The hardened controller already uses the injected `MusicPlaylistService` for persistent playlist CRUD and owns `activePlaylistId`, a validated `activePlaylistTracks` list, and `activePlaylistCursor` for sequential playlist playback. Activating the legacy manager would introduce a second catalog/playlist selector and duplicate cursor state. Its only distinct behavior is optional shuffle selection; the current remote/UI contract exposes no shuffle action, so adding it would be a separate feature decision rather than required integration. Keep it out of ServerStorage and preserve existing playlist ordering and rotation.
- **Not yet integrated (compatibility review pending):** ServerMusicAudioHandler. It must be evaluated as a possible safe adapter only if it can reuse the controller-owned Sound without taking ownership.
- **MusicSkipVoteManager: reviewed and intentionally not activated.** The controller already owns the complete skip-vote policy and state (`skipVotes`, `SkipVoteRatio`, `SkipVoteMin`, `VoteSkip`, vote clearing on track advance, and voter cleanup on player departure). The legacy module depends on a separate RoleSystem hierarchy and dispatcher, has no safe compatibility advantage to justify a second vote manager, and contains a timeout-generation bug: its delayed callback compares `self.skipVote.startTime` to itself, allowing an older timer to end a newer vote. It also accepts arbitrary vote values and does not independently validate voter eligibility in `CastVote`. Keep this legacy module out of ServerStorage; do not alter controller voting or the `;cmskip` command.
- Static source checks confirmed the controller has no remaining direct player-request insertion call and that the manager references the injected controller queue. Roblox Studio runtime and multiplayer tests have not been run.

## Installation for this stage

Create ModuleScripts named `MusicQueueManager` and `MusicValidationService` directly under `ServerStorage`, using the matching repository files `MusicQueueManager.lua` and `MusicValidationService.lua`. Replace `ServerScriptService.UI_Server_Controller` with the updated `UI_Server_Controller_server (1).lua`. Do not place either ModuleScript under a nested folder unless its controller `WaitForChild` path is changed too.

## Current status

Source retrieval and compatibility audit are complete. Queue-manager shared-state adapter and validation metadata-cache adapter are committed. MusicSkipVoteManager has been reviewed and is intentionally excluded because the controller already owns this feature and the legacy module contains unsafe duplicate vote lifecycle logic. One module remains for compatibility review: ServerMusicAudioHandler. MusicPlaybackManager, MusicPlaylistManager, and MusicSkipVoteManager are intentionally excluded because their responsibilities are already owned by the controller or would introduce a separate feature/authority. Static source checks are complete for the validation adapter; Roblox Studio runtime and multiplayer tests have not been run.
