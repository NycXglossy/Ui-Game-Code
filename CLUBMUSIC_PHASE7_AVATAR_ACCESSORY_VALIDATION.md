# Phase 7 — Avatar & Accessory Validation

## Goal

Add bounded, server-observed avatar/accessory anomaly monitoring while preserving normal Roblox avatar loading and player customization. This phase is detection-only: it does not remove accessories, rewrite HumanoidDescriptions, kick, ban, or restrict players.

## Added component

`ClubMusicSecurityCore/AvatarAccessoryValidationService.lua`

The service is loaded and started by `UI_Server_Controller_server (1).lua`. The Security Core installer now includes the module.

### Observations collected

- Reads the server-applied HumanoidDescription after `CharacterAppearanceLoaded`.
- Checks accessory description entries for positive, finite, safe-integer asset IDs.
- Detects duplicate accessory asset IDs and unusually large accessory-description counts.
- Observes accessories added to the live character.
- Checks for missing Accessory.Handle parts, unusually large/non-finite handle dimensions, collidable handles, and unusually complex accessory descendants.
- Tracks bursts of runtime accessory insertions over a short rolling window.
- Reattaches monitoring after character respawns and cleans up connections/state on departure.

The service uses Roblox server-observed character instances and applied descriptions. It does not trust client-reported asset IDs or client telemetry.

## Evidence and false-positive safeguards

- These signals are anomalies, not proof of an exploit.
- A collidable handle, unusual accessory geometry, duplicate catalog item, or late accessory insertion can have legitimate explanations.
- No single signal triggers moderation or automatic correction.
- Signals are rate-limited per player and signal type; repeated signals within the suppression window are counted but not forwarded repeatedly.
- Callback errors are caught and retained as bounded diagnostic text.
- The service never calls `GetProductInfo` for every accessory, avoiding a new Marketplace request storm and avoiding catalog availability as a security dependency.
- It does not claim to prove asset ownership, moderation status, or whether an asset is malicious. Those checks require a trusted, curated policy/catalog source and separate bounded validation.
- No avatar asset IDs, appearance descriptions, or accessory names are persisted to DataStores by this component.

## Performance and storage

- Event-driven monitoring; no periodic polling loop.
- Per-player state is bounded by live Player lifecycle.
- Accessory inspection is performed on appearance completion and accessory insertion, not every frame.
- Accessory descendant traversal is bounded by a 32-part signal threshold.
- No DataStore, MemoryStore, MessagingService, or new background worker was introduced.
- No profile fields, profile save formats, receipt journals, pass entitlements, or Utility Bar systems were changed.
- Monitoring is separate from ClubMusic audio and queue services.

## Integration and reporting

The main controller forwards anomaly identifiers and the server-observed UserId to the existing `ClubMusicGlobalAPI.RecordGlobalSecuritySignal` BindableFunction when available. If that API is unavailable, a bounded warning is emitted. The descriptive detail remains local to the callback and is truncated before logging.

The service exposes `GetStatus()` for in-process diagnostics, including tracked players, signal totals, suppressed signals, and mode `DetectionOnly`. No new public/client remote or client authority was added.

## Explicit scope limits

This phase does not:
- validate every shirt, pants, face, body-part, layered-clothing, or bundle asset against an allowlist;
- prove that an asset is moderated or safe from its numeric ID alone;
- prevent Roblox's own avatar loader from applying an appearance;
- intercept every possible third-party avatar/appearance script in the experience;
- enforce removal or punishment;
- change legitimate avatar customization, Utility Bar aura rendering, or companion visuals.

A future policy-backed asset allowlist can be added only after the experience defines approved asset sources and an exception/update process. Runtime asset ownership/moderation checks should use a bounded cache and should not be called for every descendant or frame.

## Verification checklist

### Source-level
- [x] Server-only module; no client remote or client-provided authorization.
- [x] Detection-only behavior; no accessory removal, character rewrite, kick, or ban.
- [x] CharacterAdded and CharacterAppearanceLoaded lifecycle handling.
- [x] Respawn and PlayerRemoving connection cleanup.
- [x] Bounded per-player evidence rate and bounded detail strings.
- [x] No Marketplace catalog lookups, DataStore, MemoryStore, or polling loop.
- [x] Installer includes the module and pins its source commit.
- [x] Main server controller starts the service when the module is installed.

### Required Roblox Studio tests
1. Join with a normal R6 avatar and confirm no repeated anomaly spam.
2. Join with a normal R15 avatar containing layered clothing and multiple accessories.
3. Respawn several times and confirm monitoring remains active after every respawn.
4. Add/remove a legitimate accessory through the game's approved customization path and inspect signals.
5. Test an accessory with a collidable Handle in a controlled test place; confirm detection only and no removal.
6. Test oversized or malformed accessory fixtures using test-only assets; confirm signal recording and no punishment.
7. Simulate delayed appearance loading and Roblox avatar-service failure; confirm players are not kicked or blocked.
8. Test high accessory counts and rapid accessory insertion; confirm bounded reporting.
9. Confirm Utility Bar Aura, companion clone, avatar refresh, and normal character appearance continue to work.
10. Inspect server memory and script performance with representative player counts.

## Verification status

- Repository source integration: completed.
- Installer execution: not performed.
- Roblox Studio tests: not performed.
- Published-server tests: not performed.
- Asset allowlist and moderation-policy validation: intentionally not implemented; requires a curated policy source.

No live player profiles or persistent storage were read or modified by this phase.
