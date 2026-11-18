# Phase 8 — Audio, Boombox & Animation Security

## Goal

Harden the audio asset ingress already present in ClubMusic without changing the modern AudioPlayer backend, playback transitions, queue ownership, global playback-only sync, or local per-server queue model.

## Repository audit

The audited branch contains a server-authoritative ClubMusic audio pipeline:
- `ReplicatedStorage.ClubMusicRemotes.RequestAction` is the client ingress.
- `RequestTrack` accepts only a server-owned catalog track ID; it does not accept a client-supplied SoundId.
- `RequestAudioAsset` and `CatalogAddAudio` are staff-only.
- Audio metadata is checked through `MusicValidationService`, including Roblox asset type.
- The controller preloads an `AudioPlayer` probe to verify the asset is actually usable by this experience and measures its real duration.
- Inspection has per-player cooldowns, a server-wide token bucket, a concurrency cap, and a timeout-safe slot lifecycle.
- Catalog persistence is server-owned; playback is owned by the controller and the modern AudioPlayer backend.
- Playback controls re-check server-side DJ permissions. Owner/Co-owner-only playlist/queue management remains distinct from DJ playback-control permissions.

The repository snapshot did not contain a boombox system, player animation remote, animation asset catalog, or animation playback handler. This phase does not invent one or create an unused remote/API. Those paths must be integrated when their actual scripts are identified.

## Implemented hardening

### Shared finite integer validation for audio asset IDs

`UI_Server_Controller_server (1).lua` now routes audio asset IDs and optional artwork IDs through `SanityValidation.IsInteger(value, 1, 9007199254740991)`.

This closes the NaN/infinity edge case in the former hand-written comparisons and keeps all asset ID ingress consistent with the shared server-side sanity standard.

A strict local fallback remains for staged installations where the shared module is unavailable. The fallback independently rejects non-numbers, NaN, infinities, non-integers, zero/negative values, and values above the safe integer range.

Applied to:
- Staff `RequestAudioAsset`.
- Staff `CatalogAddAudio`.
- Optional catalog artwork asset IDs.

## Existing audio safeguards preserved

- Client requests cannot supply arbitrary track metadata or directly set the active server SoundId/AudioPlayer asset.
- Normal player requests resolve through the server-owned `TRACK_BY_ID` catalog and reject placeholders.
- Staff audio asset inspection remains permission-gated.
- Optional allowlist enforcement remains configurable; this phase does not silently turn it on or change the current approved catalog policy.
- The server still verifies `Enum.AssetType.Audio`, experience preload/playability, and duration before catalog insertion.
- Concurrent inspection limits, timeout behavior, metadata cache bounds, catalog storage and request cooldowns remain unchanged.
- Playback controls remain server-authorized and do not grant control over another player's private output volume.
- No changes were made to crossfade, AudioPlayer source ownership, legacy audio recovery, global playback-only synchronization, or queue semantics.

## Boombox and animation scope

No boombox/animation implementation was present in the audited repository snapshot. Therefore, no claims are made that this phase protects arbitrary third-party boomboxes or animation remotes.

When those systems are added or their scripts are identified, each must:
1. Accept only bounded, finite, positive integer asset IDs where applicable.
2. Validate asset type and approved policy on the server.
3. Check actor permission and whether the target is allowed to be affected.
4. Enforce per-player and server-wide cooldown/rate budgets.
5. Reject duplicate/replayed or invalid state transitions.
6. Prevent one player from changing another player's private audio output or animation state without explicit server authorization.
7. Keep asset metadata caches bounded and avoid per-frame/per-request Marketplace lookup storms.
8. Record anomalies as evidence; asset lookup failures alone are not exploit evidence.

## Storage and performance

- No new DataStore or MemoryStore.
- No new MessagingService traffic.
- No new polling loops or background workers.
- No profile schema, receipt journal, catalog key, or queue storage changes.
- Existing bounded audio metadata cache and catalog storage behavior remain intact.
- No new client remote or client-side permission authority.

## Verification checklist

### Source-level
- [x] Audio asset IDs use the shared finite integer validator when available.
- [x] Local fallback rejects NaN, infinity, non-integers and out-of-range IDs.
- [x] Staff-only audio inspection and catalog insertion remain permission-gated.
- [x] Catalog playback still resolves server-owned track IDs.
- [x] Existing metadata and preload/playability checks retained.
- [x] Existing per-player/global rate limits and bounded concurrency retained.
- [x] Modern AudioPlayer and crossfade code untouched.
- [x] No boombox or animation remotes were found in the audited repository tree.

### Required Roblox Studio tests
1. Try staff audio inspection with a valid audio asset and confirm it still loads.
2. Try zero, negative, fractional, NaN, positive infinity, negative infinity, and values above the safe integer range; all must be rejected before Marketplace or preload work.
3. Try an image/decal asset ID in the audio path; it must fail the audio asset-type check.
4. Try a valid audio asset unavailable to this experience; it must not be inserted into the catalog.
5. Try an audio asset longer than the configured maximum; it must be rejected.
6. Verify non-staff cannot inspect or add arbitrary audio assets.
7. Verify normal users can still request approved catalog tracks and cannot submit arbitrary SoundIds.
8. Stress audio inspection concurrency and timeout behavior; verify the global slot remains held until timed-out preload work actually completes.
9. Test DJ playback controls with authorized and unauthorized accounts.
10. Verify modern AudioPlayer playback, crossfade, pause/resume, restart, local queues and optional playback-only sync remain unchanged.

## Verification status

- Repository source integration: completed.
- Roblox Studio tests: not performed.
- Published-server tests: not performed.
- Boombox and animation validation: pending identification/integration of the actual systems.

No live player profiles, receipt records, or persistent catalog records were read or modified by this phase.

## Phase 30 source audit update

This Phase 8 document remains the historical ingress/permission audit. Phase 30 is the current source of truth for the modern AudioPlayer lifecycle, media mutation entry points, playback-only global sync, canonical module bundles, installer manifests, and Sound fallback retirement.

- Current controller source is modern AudioPlayer-only. No active `Sound` instance fallback remains in startup, reload/recovery, pause/restart, crossfade, watchdog, or diagnostics.
- `MusicPlaybackManager` quality inspection was consolidated into controller-local diagnostics; the current controller no longer loads that facade and the current installer no longer provisions it.
- Normal catalog requests remain open to all players when DJ Control Mode is off. When enabled, only its current controller may submit normal requests (including the staff Creator Hub request path); Auto DJ refill remains active.
- All players retain Now Playing/local queue visibility, skip voting, and cooldown-limited self-service `ReloadSong`. DJ/staff controls, playlist/catalog mutation, and DJ session actions continue to use SecurityCore-backed authorization.
- Optional global playback sync is available but disabled by default. It shares Now Playing/playhead only; request queues, playlist cursors, Auto DJ refill, and request accounting remain per-server.
- The tracked source scan found no boombox remote, animation asset mutation endpoint, or server animation playback endpoint. The only animation-related server observation is `GetPlayingAnimationTracks()` for Dance Floor activity eligibility. The Creator Hub preview AudioPlayer is client-local and does not mutate server playback.
- See `CLUBMUSIC_PHASE30_AUDIO_ANIMATION_MEDIA_ABUSE.md` for the full source audit, module/bundle mapping, and runtime acceptance matrix. Phase 30 is not certified until Studio and published two-server tests pass.

