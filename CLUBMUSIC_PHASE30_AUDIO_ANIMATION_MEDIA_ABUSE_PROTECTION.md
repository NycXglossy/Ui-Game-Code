# Phase 30 — Audio, Animation & Media Abuse Protection

**Branch:** `fix/security-core-release-and-queue-loop`  
**Source audit baseline:** `83f6cf36a55ee09f9447686fdae0c005bda4d856`  
**Status:** Tracked-source modern-only audio, media ingress hardening, and bounded detection-only animation inventory are implemented. Runtime certification and live-place consumer reconciliation remain open.  
**Do not certify Phase 30** until the Studio and published two-server acceptance matrix at the end of this document passes.

## Scope and non-negotiable invariants

- The server controller owns the sole modern `AudioPlayer` playback source, track selection, playback clock, queue, request accounting, Auto DJ refill, transition invocation, and authoritative state replication.
- Per-server request queues, playlist cursors, Auto DJ state, request accounting, and skip votes remain independent.
- Cross-server playback synchronization is retired. Each server independently owns Now Playing, the playback clock, queue, playlist cursor, Auto DJ refill, request accounting, skip votes, and crossfade lifecycle.
- SecurityCore Authorization remains the sole role/permission authority.
- Client preferences and per-listener output routing remain client-local.
- Do not install the standalone legacy Music System, add another playback controller, delete rollback sources, or remove live-place objects without a complete consumer audit.

## Active source inventory and media ingress

### Controller and client network contract

The active UI uses the controller-owned `ReplicatedStorage.ClubMusicRemotes` contract:

- `RequestAction`: client-to-server action requests; controller validates the live caller, applies per-player/server ingress budgets, validates the bounded payload, allowlists action names, and applies action cooldowns before dispatch.
- `GetState`, `GetMusicCatalog`, and `GetMusicPlaylists`: read-only server queries with bounded invocation work/cooldowns.
- `StateChanged` and `Notice`: server-to-client state/notification channels.
- `PurchaseDiagnostic`: bounded, explicitly unverified client prompt telemetry; it is not a media, purchase, or entitlement grant path.

The active `UI_Network.lua` wraps `RequestAction`; it does not create a second audio remote or playback owner. No active controller/UI_Network boombox-specific endpoint was found in the audited source set.

### Audio and catalog mutation paths

| Entry point | Server-side policy / boundary |
|---|---|
| `RequestTrack` | Resolves only an existing server catalog track; rejects placeholders, blocked tracks, duplicate/current tracks, full queue, exhausted request slots, and cooldowns. Enforces DJ Control Mode ownership before queue insertion. Queue and priority mutation stay server-side. |
| `RequestAudioAsset` | Staff-only Creator Hub asset request. Validates numeric asset ID, optional allowlist, per-player cooldown, server-wide audio token budget, bounded concurrent inspection, audio type/experience access/playability and duration. Rechecks caller presence, staff permission, and DJ Control Mode after yielding before queue insertion. |
| `CatalogAddAudio` | Staff-only persistent catalog mutation. Validates asset ID and genre; optional artwork ID must resolve to an accessible Roblox Image or Decal asset; audio is independently inspected and duration-bounded before the catalog service writes it. Uses existing catalog storage and invalidation. |
| `CatalogRemoveTrack` | Staff-only; only custom catalog entries can be removed. Rejects current or queued tracks and updates active playlist rotation safely. |
| `PlaylistCreate/Delete/AddTrack/RemoveTrack/MoveTrack` | Staff-only, storage-ready and DataStore-budget gated. Track IDs must resolve in the current server catalog; persistent playlist service owns storage only, not playback or queue state. |
| `DJPlayPlaylist/DJStopPlaylist` | Elevated DJ Booth controller check; playlist rotation remains server-owned and uses the server's own queue. |
| `VoteSkip` | Available to any connected player; server records one vote per player and evaluates the configured vote threshold. No DJ permission is required. |
| `ReloadSong` | Explicit self-service recovery for any connected player. No DJ/staff permission check. Existing three-second per-player cooldown and the common action ingress budget remain in force. It cannot select a new asset or mutate the catalog/queue. |
| `DJPause/DJRestart/DJSkip` | Require the SecurityCore-backed `GlobalDJ` authorization callback; the action affects only the current server's playback. |
| DJ queue-management / emergency actions | Use the existing elevated DJ Booth or staff/admin authorization path; no client role attribute is accepted as authority. |

The controller's `canUseDJBooth` calls the shared SecurityCore Authorization service with `GlobalDJ`; it does not maintain a role table. Elevated booth management uses the existing SecurityCore-derived level. The DJ session manager remains server-only and receives authorization/handoff callbacks from the controller, which rechecks connected players and staff ranks.

### Animation, image/artwork, and boombox audit

- No active `AnimationId` assignment, animation-load remote, or animation mutation endpoint was found in the controller, `UI_Network.lua`, renderer, or client audio-preferences module inspected for this pass. Dance Floor activity inspection reads playing animation tracks only; it does not grant or change animations.
- The renderer displays artwork from server-published catalog metadata. Client image rendering is presentation, not authority. Catalog artwork mutation is limited to the staff-only `CatalogAddAudio` path described above.
- No active boombox-specific remote was found in the current controller/UI network path.
- The repository still contains the historical plain-text `Music System` and `Music Storage Handle` artifacts. The old Music System creates its own `DispatchAction`, `DispatchEvent`, `MusicBroadcast`, `MusicUpdate`, and `RequestSync` remotes and calls the legacy Sound storage handler. The old storage handler creates and caches Roblox `Sound` instances. These are not loaded by the current controller or current audio installer; do not install them.
- The historical `Music Role System` is a separate legacy role/pass helper. It is not part of the current SecurityCore permission path and must not be used as a second authority.
- Small binary `.rbxm` assets named for old Music Remotes / Music Group were not parsed by the text-only repository reader. Their contents and any live-place descendants remain unverified. Do not delete them by filename or assume they are harmless.

### Catalog artwork inspection hardening — implemented

The active controller's staff-only `CatalogAddAudio` path now applies additional safeguards before accepting optional artwork metadata:

- Artwork IDs continue to use the shared strict positive finite-integer validation.
- Marketplace metadata inspection is bounded to four concurrent server-wide artwork lookups, with one pending artwork inspection per caller. This is separate from the AudioPlayer preload inspection budget.
- The lookup must return an Image or Decal asset type. An exact normalized `[ Content Deleted ]` metadata name is rejected as an additional conservative signal; it is not treated as a complete moderation verdict.
- The caller must still be connected and pass the existing staff authorization check after the yielding lookup, before the action proceeds to the audio inspection and persistent catalog write.
- Existing action cooldowns, per-player/server action token buckets, audio inspection budgets, catalog storage readiness checks, and the later staff recheck remain in force.

The controller source change is committed on the feature branch. It has not been run in Roblox Studio; Marketplace lookup behavior, concurrency under load, staff-rank changes during inspection, and catalog persistence still require runtime acceptance testing.

### Proposed club-screen image RemoteEvent review

A supplied example proposes a new `ReplicatedStorage.UpdateScreenEvent` that accepts a client image ID, checks `player:GetAttribute("IsDJ")`, calls `MarketplaceService:GetProductInfo`, then writes to `Workspace.ClubScreen.SurfaceGui.ImageLabel.Image`.

- This endpoint is not part of the audited active `ClubMusicRemotes` contract. No `UpdateScreenEvent`, `ClubScreen`, or `IsDJ` authorization path was found in the inspected controller/UI network source. Do not add this standalone remote or treat the sample as an existing feature.
- `IsDJ` is a client-visible attribute, not an authorization authority. Any future screen mutation must call the existing server-side SecurityCore Authorization path and use the intended DJ/staff permission; VIP ownership or a client-set role attribute is not sufficient.
- The existing `CatalogAddAudio` artwork path is staff-only and checks that the supplied asset resolves as a Roblox Image or Decal before storing it as catalog metadata. That does not authorize arbitrary players to replace a shared in-world display.
- `GetProductInfo` asset type metadata and a name comparison against `[ Content Deleted ]` are not a complete moderation or experience-renderability guarantee. Asset metadata may be unavailable or stale, and a name string is not a reliable moderation signal.
- The sample floors fractional values instead of rejecting them, does not bound the ID to a safe positive integer, has no per-player/global mutation budget, and does not recheck permission after any yielding validation call.
- `Workspace:FindFirstChild("ClubScreen")` is an unscoped name lookup. A future implementation would need a server-owned, explicit allowlist of display instances and their permitted surfaces, bounded validation/preload work, rate limits, and a defined policy for concurrent updates and restoring the approved/default image.
- No display mutation feature, new remote, image allowlist, or runtime screen change was implemented in this review. The live map/display hierarchy and any third-party screen controllers remain unverified.

**Live-place limitation:** a repository audit cannot prove which old Scripts, Models, remotes, plugins, package descendants, or runtime-inserted assets exist in the published place. Before removing historical objects, inspect the actual live hierarchy and all consumers, including third-party packages and scripts that may reference those remote names.

## Server-core conversion and canonical source ownership

### Runtime ownership

- `UI_Server_Controller_server (1).lua` owns the only active `AudioPlayer` source through `activeAudioSource`. It does not reference `ServerMusicSound` or `MusicGroup`, create legacy `Sound` objects, or select a legacy Sound fallback.
- `ClubMusicAudioBackend.luau` owns construction/teardown of the modern managed AudioPlayer graph under server `SoundService`.
- `ClubMusicAudioCrossfadeManager.luau` remains a separate transition coordinator. It handles generation fencing, cancellation, fade, commit settlement, failed-deck retention, and cleanup. The controller owns transition invocation and queue/source ownership transfer.
- The controller's local playback-quality inspection replaces the old `MusicPlaybackManager` facade. Watchdog decisions use the normalized modern backend snapshot; manual reload/recovery, pause/resume, restart, and crossfade are modern-only.
- `ClubMusicPlayerPreferences.luau` remains client-only. Each listener creates its own `AudioFader` → `AudioDeviceOutput` route; it does not change server gain or another player's volume.
- `ClubMusicDJSessionManager.luau` remains a server-only session lifecycle helper with injected controller authorization; it does not own playback, queues, or roles.
- `ClubMusicSpatialAudioGraph.luau` remains optional and separate because spatial graph resource ownership/teardown is distinct from playback state.

### Canonical queue, catalog, validation, and playlist sources

- Canonical queue path: `MusicQueueManager.lua` adapter + `MusicQueueManagerService.lua` operating on the controller-injected queue and request-slot release callback.
- Canonical validation path: `MusicValidationService.lua`, including the controller-required bounded metadata normalization API. Preload/playability checks remain in the controller.
- `MusicCatalogService.lua` owns catalog lookup and persistent custom-track overlay.
- `MusicPlaylistService.lua` owns persistent playlist storage only. Playlist rotation cursor remains controller-local.
- Skip-vote state remains controller-local; no skip-vote manager is loaded.
- The historical `.luau` duplicate implementations `MusicQueueManager.luau` and `MusicValidationService.luau`, plus the unused `MusicPlaybackManager.luau`, `MusicPlaylistManager.luau`, and `MusicSkipVoteManager.luau`, remain in the repository as rollback/reference artifacts. The current controller and installer do not load/install these duplicates. Do not delete them until the actual live-place ServerStorage hierarchy and all package/installer consumers are reconciled.
- `ServerMusicAudioHandler` is absent from the current tracked tree and is not loaded by the current controller.

### Standalone / RBXMX parity

Static source extraction compared embedded ModuleScript CDATA with the standalone source. The following were byte-identical at the audit baseline:

- Five audio server modules: Backend, Crossfade Manager, Quality Profiles, DJ Session Manager, Spatial Audio Graph.
- Six ServerStorage core modules: Catalog Service, Playlist Service, Receipt Hash, Queue Manager adapter, Queue Manager Service, Validation Service.
- Client Player Preferences module.
- Global Optional Services bundle's `MusicGlobalPlaybackAuthority` and standalone source.

No source drift was found in those comparisons. The standalone files are canonical; embedded bundles are generated snapshots. Regenerate a bundle from canonical standalone source after any future module edit and repeat byte-for-byte comparison.

### Installer manifest reconciliation

- `ClubMusic_Studio_CommandBar_Installer.lua` previously pinned the audio sources to commit `f47410ac9a9674d3df0b24eb1714b31d1a4ef816` and the six ServerStorage modules to `4857fd9c5b763a2a685b37bccf812a6f85425524`.
- All twelve installer source files were compared against the current branch copies; each old pin was byte-identical to its current standalone file.
- The installer was updated in commit `fedcd345b6e8d1e7809857611c29d3964242570c` so all twelve module URLs point to the single audited source snapshot `83f6cf36a55ee09f9447686fdae0c005bda4d856`.
- The installer does not install the standalone legacy Music System, the old role helper, or duplicate `.luau` queue/validation/playback facades. It leaves pre-existing legacy objects untouched pending live-place consumer reconciliation.
- The Global Optional Services bundle and its installer/deployment path are separate from the audio ModuleScript installer; preserve its existing SecurityCore authorization and playback-only authority contract.

## DJ Control Mode permission acceptance rule — source result

The tracked controller currently implements the requested rule:

1. With DJ Control Mode off, all players can submit valid normal catalog requests subject to ordinary moderation, cooldown, per-player request count, queue capacity, duplicate, and catalog-playability checks.
2. When a player with the existing SecurityCore `GlobalDJ` permission enables DJ Control Mode, that player remains allowed to request; every other player is rejected from normal request submission.
3. Only the current controller can disable the mode. If that controller leaves, `Players.PlayerRemoving` clears the mode and controller UserId, broadcasts that normal requests are open, and publishes state.
4. Auto DJ refill is not gated by DJ Control Mode; the separate emergency request lock remains a distinct staff incident control.
5. Every connected player can vote to skip and read the replicated Now Playing/queue state.
6. Every connected player can invoke `ReloadSong` under the three-second cooldown and common action ingress limits. It does not require DJ permission.
7. Pause, restart, DJ skip, playlist/catalog mutation, and DJ session/handoff operations retain their respective SecurityCore-backed DJ/staff/elevated authorization.

This is a source inspection result, not runtime permission certification.

## Runtime acceptance matrix — mandatory before certification

### Modern playback and recovery (single server)

- Start a catalog track; verify server-owned AudioPlayer graph, correct playhead/length, and private client output on PC/mobile/console.
- Pause/resume, restart, seek, track advance, manual ReloadSong while playing and paused; confirm pause state/playhead are preserved as designed.
- Force decoder readiness failure, asset failure, backend construction failure, and replacement candidate failure. The controller must remain modern-only/unavailable on failure; no legacy Sound fallback is created or selected.
- Watchdog detects stalled/degraded playback, performs bounded modern recovery, and reports active AudioPlayer context.
- Crossfade success, cancellation before readiness, cancellation during fade, rapid repeated Begin, queue-head change, failed bind/pop rollback, gain restoration, failed cleanup retry, server shutdown during transition; verify no orphaned backend/deck graph.
- Confirm player departure does not tear down server-wide playback.

### DJ permissions and queue behavior

- With DJ Control Mode off, a normal player submits a valid catalog track.
- Enable DJ Control Mode as the current permitted controller. Confirm controller can submit a valid catalog track; a different normal player is rejected; Auto DJ still refills.
- Confirm the emergency request lock is independent and does not silently become DJ Control Mode.
- Any player can vote to skip and view Now Playing/queue. Duplicate votes are rejected.
- Any player can use ReloadSong, including while DJ Control Mode is enabled, subject to cooldown and common action budget.
- Unauthorized players cannot pause, restart, DJ-skip, clear/reorder/remove queue entries, manage playlists/catalog, or start/handoff/end privileged DJ sessions.
- Only current controller can turn DJ Control Mode off. On controller departure, verify state clears and normal requests reopen.
- Exercise the same checks through the UI remotes and Kohl's Admin command bridge; verify no client-side UI visibility decision is treated as authorization.

### Media and mutation abuse

- Forge invalid/oversized/non-finite action payloads, unsupported action names, arbitrary asset IDs, blocked IDs, non-audio IDs, too-long audio, inaccessible assets, invalid artwork IDs, and non-image/decal artwork.
- Concurrent Creator Hub audio inspections, per-player cooldown, global audio budget, and caller departure during inspection.
- Attempt catalog and playlist mutations from non-staff players; verify no DataStore write.
- Verify artwork can only be introduced through the staff-authorized server catalog path and client renderers cannot write authoritative metadata.
- Inventory all deployed remotes and scripts for boombox, animation, image/decal, Sound, and AudioPlayer mutations. Test or retire each live consumer only after provenance and authorization are understood.
- Verify the standalone legacy Music System and its five remotes are absent/disabled in the live place; do not install it.

### Two-server local-isolation regression

- Start two servers with different local queues and verify each retains its own Now Playing, playback clock, playlist cursor, Auto DJ refill, request accounting, skip votes, and crossfade state.
- Verify skip, pause, restart, reload, and queue-management actions affect only the server receiving the action.
- Verify no playback leader lease, playback snapshot store, playback topic, or playback message handler is active.
- Verify catalog invalidation and explicitly global moderation/announcement/XP coordination continue through their separate approved paths.

### Compatibility and operational bounds

- PC, mobile, console; R6/R15/custom avatars; repeated join/leave; full server; long session; low-memory and network-latency conditions.
- Confirm bounded queue, inspection concurrency, token buckets, diagnostics, transition generation state, and cleanup registries.
- Verify Studio isolation remains disabled by default. Use a disposable multi-server Studio copy for global-service tests.
- Inspect the actual published place hierarchy, including binary RBXM assets, installed packages, plugins, runtime-created scripts/remotes, and all consumers before deleting rollback artifacts.

## Certification status

- Static source audit and manifest update only.
- No Luau parser/compiler, Roblox Studio runtime, live DataStore, live Marketplace asset check, or published two-server test was available during this pass.
- User previously reported modern-only playback working; this does not replace the full Phase 30 matrix above.
- Feature branch remains unmerged/unpublished. No live Roblox place or production data was changed.

## Follow-up review: standalone PlayAudioEvent example

The supplied `PlayAudioEvent` / `DJSpeaker.ClubSound` script was reviewed against the active controller. It is **not installed** and should not be added as a parallel playback path.

Reasons:

- It creates a separate client-to-server `PlayAudioEvent` ingress and directly assigns `Sound.SoundId` / calls `Sound:Play()`. That would create a second playback authority and reintroduce legacy Sound playback beside the modern controller-owned AudioPlayer.
- The sample's `ApprovedSongs` table is not enforced (the whitelist check is commented out), so any numeric ID reaches the metadata lookup. `math.floor` silently accepts fractional IDs instead of rejecting them; explicit finite positive integer validation is required.
- `GetProductInfo` and `AssetTypeId == 3` alone do not prove that the asset is loadable by this experience, permitted for playback, or decodable. The sample does not preload an AudioPlayer probe, measure real duration, or apply the existing max-duration policy.
- The sample has only a per-player cooldown, no pending-inspection/reentrancy guard, no server-wide token budget/concurrency cap, and no PlayerRemoving cleanup for its cooldown table.
- It has no SecurityCore staff authorization, no DJ Control Mode controller recheck after the yielding Marketplace lookup, no queue/request-limit/moderation checks, and no state recheck before playback.
- Clamping the pre-existing Sound volume does not validate an input gain value; resetting PlaybackSpeed can also overwrite intentional server-owned track speed settings.
- `DJSpeaker` / `ClubSound` existence checks do not establish a reviewed asset owner, safe speaker lifecycle, or valid modern audio graph.

The existing `RequestAudioAsset` action is the approved equivalent for direct Creator Hub asset IDs: it is staff-only, validates a finite positive integer ID, optionally enforces the configured allowlist, applies per-player cooldown and pending-request protection, consumes a server-wide inspection token, caps concurrent inspections, validates the actual Audio asset type, creates/preloads a temporary modern `AudioPlayer` probe to verify experience playability and real duration, and rechecks staff status, DJ Control Mode ownership, and queue/request constraints after yielding before inserting the request into the server-owned queue. The normal catalog `RequestTrack` path remains open to all players while DJ Control Mode is off.

The allowlist remains an explicit configuration option (`RestrictAudioToAllowlist`); it is not enabled with an empty list. Enabling it safely requires populating a reviewed approved-ID catalog first. Do not enable an empty allowlist or treat the sample's two IDs as approved without an explicit content-policy decision.

**Disposition:** no new RemoteEvent, Sound object, DJSpeaker controller, cooldown table, or playback handler was added. Reuse the existing server action and modern AudioPlayer path.

## Follow-up review: standalone AnimationPlayed allowlist example

The supplied `Animator.AnimationPlayed` script was reviewed against the active Tiki Tide controller and existing dance-floor reward logic. It is **not installed** and its stop/destroy policy is not safe to adopt as written.

### Findings

- The seven hardcoded IDs are not a complete animation policy for this experience. They cannot cover all default R6 and R15 Animate tracks, custom avatar rigs, game-owned dances, emotes, tool animations, layered/priority animations, and future content.
- The script stops and destroys every track whose AnimationId is not in that small table. That would interrupt legitimate custom dances/emotes and potentially default movement/idle/jump/tool animations. A legitimate track is not unauthorized merely because its ID is not on this list.
- `AnimationPlayed` identifies that a track began; it does not establish whether the player, Roblox Animate, a server script, a game emote system, a tool, or another legitimate system initiated it. An ID-only allowlist is not a grant/provenance authority.
- Animation IDs may be represented in equivalent asset URI forms; string-key matching without canonicalization can reject equivalent valid IDs.
- The example only connects `CharacterAdded` for future PlayerAdded events, so it can miss players already present when the script starts. It also does not explicitly disconnect character/player observers on teardown, bound warning volume, or aggregate repeated events.
- Immediate `Stop(0)` plus `Destroy()` is enforcement, not passive evidence. A false positive can break movement, emotes, or gameplay; repeated client-triggered tracks could also produce log spam.

### Existing game behavior that must be preserved

The main controller's profile-backed Dance Floor reward service samples each player's current character every ten seconds. It treats observed root displacement, Humanoid MoveDirection, or a currently playing track with Movement-or-higher priority as activity. It checks presence inside the server-tagged `TikiTideDanceFloorZone`, applies a 180-second inactivity cutoff, resolves VIP through SecurityCore entitlement, and records the reward timestamp in the existing profile.

This activity observer deliberately does not require a particular animation ID. Replacing it with the supplied allowlist, or stopping unknown tracks, would risk breaking legitimate dance-floor activity and rewards. It is not an animation authorization service.

### Implemented: bounded detection-only animation inventory

A new `ClubMusicSecurityCore/AnimationIntegrityService.lua` is now wired into the main controller and included in the Security Core installer release.

- The server observes `Animator.AnimationPlayed` for live player characters and inspects a bounded snapshot of already-playing tracks when an Animator is attached.
- Each distinct canonical `rbxassetid://` animation ID is recorded once per character, with only the numeric asset ID, animation priority, and R6/R15 rig type. Animation names, keyframes, chat, and client-supplied metadata are not retained.
- Per character, observation is bounded to 128 track starts, 32 distinct asset IDs, 64 initial tracks, four Humanoids, and four Animators. The observer records cap events and reports aggregate status.
- Player, character, Humanoid, and Animator connections are disconnected on `CharacterRemoving`, replacement, ancestry removal, player departure, or controller shutdown. PlayerAdded and already-connected players are both covered.
- Events flow only to the existing server-local `TikiTideSecurityReplay` timeline as `Info` observations (or `Warning` when an observation cap is reached). They are deliberately not forwarded to the global threat-signal path, which treats incoming signals as warnings. A server-only `GetTikiTideAnimationIntegrityStatus` BindableFunction exposes observer health/counters.
- No animation is stopped, destroyed, rewritten, or blocked. The observer does not grant animations, create a permission system, or kick/ban/punish players.

**Interpretation limit:** this is an observed asset inventory, not an approved-animation allowlist or provenance verdict. An ID not yet seen is not automatically suspicious. The observer currently accepts canonical `rbxassetid://` strings for its inventory; other URI forms are counted as unreadable and ignored rather than blocked. Before any allowlist or enforcement is considered, inventory the live Animate scripts, HumanoidDescription animation/emote configuration, game dance/emote grant paths, tool animations, server-created Animator instances, third-party packages, and production asset IDs.

**Static integration status:** the controller starts/stops the service; the Security Core installer includes `AnimationIntegrityService` and pins its source release at `67bfde5823d81d2b4d55ca372127b026403e1f5a`. The module was source-hardened for bounded counters, per-character caps, and lifecycle cleanup. This was a source-level change only. Roblox Studio tests are still required for R6, R15, custom rigs, default locomotion, emotes, tools, dance systems, rapid track starts, respawns, Animator replacement, player departure, and observer cleanup. No Luau parser or Studio runtime was available here.
