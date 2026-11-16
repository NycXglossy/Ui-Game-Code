# Phase 4 — Tiki Tide Settings & Utility Bar Remote Hardening

## Scope

Apply the shared server-authority sanity-validation standard to the two additional exposed server request boundaries without coupling Utility Bar to ClubMusic playback or changing client contracts.

## Tiki Tide Settings

- Validates the live server Player before processing a request.
- Adds a server-local token bucket (48-request burst, 24 requests/second refill) before traversing client payloads.
- Retains the existing per-player 0.25-second request cooldown and action-specific authorization/entitlement checks.
- Uses `SanityValidation.ValidateDataTree` when the Security Core installer has deployed it, with depth 3, 24 entries and 180-character string ceilings.
- Keeps a shallow, bounded scalar-only fallback for staged rollout when the shared module is not installed.
- Existing TextService filtering, reauthorization after yielding, consent checks, movement authority registration and single-use teleport ticket flow remain unchanged.

## Utility Bar

- Validates the live server Player and action name before dispatch.
- Adds a server-local token bucket (36-request burst, 18 requests/second refill) before payload inspection.
- Retains the existing per-player 1.25-second cooldown and server-verified feature pass attributes.
- Uses the shared data-tree validator for table values with depth 2, 8 entries and 64-character string ceilings; scalar inputs are checked for finite numeric values and bounded strings.
- Keeps a shallow, bounded fallback when the shared module is not installed.
- Utility Bar remains an independent system; no ClubMusic audio, queue, or global playback code is changed.

## CPU and memory characteristics

- Both token buckets are constant-size scalar state: no per-request records, new background loops, DataStore/MemoryStore calls or cross-server messages.
- Structural validation is bounded by explicit depth, entry and string limits.
- Existing per-player cooldown maps are cleared on PlayerRemoving.
- The new work is event-driven and local to each server. It does not claim fixed CPU percentages or a precise Roblox per-script memory quota.
- These limits bound ingress validation overhead; the downstream game operation (for example, cloning a character or scanning tagged stage lights) still needs representative Studio profiling.

## Required Studio checks

1. Install the Security Core so `ServerStorage.ClubMusicSecurityCore.SanityValidation` is present; confirm the fallback warnings are absent.
2. Test all Tiki Tide Settings actions: snapshot, movement, AFK, teleport consent, teleport, gravity (authorized and unauthorized), bubble broadcast and announcement.
3. Test all Utility Bar actions: Mount, Size boundaries, Clone, Aura targets/styles, ClearAura and Lighting presets.
4. Confirm existing pass gates and SecurityCore permission checks still reject unauthorized users.
5. In a controlled test harness, send malformed/cyclic/deep/oversized payloads and NaN/infinite numbers; verify requests are rejected without state mutation.
6. Burst requests across several clients; confirm the local token buckets reject excess work and normal requests recover as tokens refill.
7. Profile server script activity and memory before/after at expected player counts, including representative avatars and tagged lighting fixtures.
8. Re-test teleport validation, movement-authority correlation and all PC/mobile/console UI actions.

No Roblox Studio or published-server runtime tests have been performed for this phase.
