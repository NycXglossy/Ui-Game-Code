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
- **Not yet integrated:** MusicPlaybackManager, MusicPlaylistManager, MusicSkipVoteManager, MusicValidationService, and ServerMusicAudioHandler. They require compatibility refactors before activation; in particular, the playback and audio modules must not create a second Sound or playback clock, and the skip-vote module must not override the existing server vote policy.
- Static source checks confirmed the controller has no remaining direct player-request insertion call and that the manager references the injected controller queue. Roblox Studio runtime and multiplayer tests have not been run.

## Installation for this stage

Create a ModuleScript named `MusicQueueManager` directly under `ServerStorage` and paste the contents of repository file `MusicQueueManager.lua`. Replace `ServerScriptService.UI_Server_Controller` with the updated `UI_Server_Controller_server (1).lua`. Do not place the ModuleScript under a nested folder unless the controller's `WaitForChild` path is changed too.

## Current status

Source retrieval and compatibility audit are complete. Queue-manager adapter integration is committed. The remaining five modules are deliberately not activated until their duplicate state ownership and legacy dependencies are removed.
