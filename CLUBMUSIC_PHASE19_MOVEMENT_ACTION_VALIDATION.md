# Phase 19 — Server-Authoritative Movement & Action Validation Audit

**Status:** Source audit and narrow ledger hardening committed. Studio and published-server acceptance remains open. This phase does not certify the experience against exploit movement.

## Scope and audit findings

The audit reviewed `CharacterPhysicsGuard`, `MovementAuthority`, `TeleportValidationService`, the Tiki Tide Settings server adapter, Utility Bar extended actions, and the SecurityCore installer/bootstrap.

### Existing movement authority

- `MovementAuthority` is a server-only, per-server authorization ledger exposed through `ServerStorage.TikiTideMovementAuthority`. It does not create DataStore or MemoryStore records.
- Confirmed current registrations:
  - Tiki Tide Settings registers its server-applied `WalkSpeed` and `JumpPower` values.
  - Tiki Tide Settings registers administrator-approved `WorldGravity` changes against target ID 0.
  - Utility Bar registers its self-only `BodyScale` changes.
- The ledger is an approval marker for the observer, not an independent permission system. The caller must perform entitlement/permission checks before changing the property. The BindableFunction is ServerStorage-only; no client remote is created for it.
- Phase 19 hardens `Check`: player-scoped entries are rejected and cleared if the target is no longer live, and the special `ANY` presence check is accepted only for the `Fling` property. Numeric checks continue to require a close match to the registered value.

### Existing physics observer

- `CharacterPhysicsGuard` observes Humanoid `WalkSpeed`, `JumpPower`, `JumpHeight`, R15 body scales, Workspace gravity, and very high root assembly linear/angular velocity.
- It uses property-change signals and short delayed coalescing rather than a permanent per-player polling loop.
- Phase 19 follow-up changes the one-shot 0.5-second Humanoid lookup to a bounded 10-second `WaitForChild`, and likewise waits up to 10 seconds for `HumanoidRootPart`. It rechecks player/character/service state after the yielding root lookup before attaching velocity observers, preventing late setup from binding to a departed or replaced character.
- It suppresses repeated identical signals for ten seconds per subject.
- It deliberately does not kick, ban, teleport, correct movement, anchor characters, or change character properties.
- It is detection-only. It does not prove that a client cannot locally alter movement, and it does not currently perform path/displacement validation or enforce a server movement envelope.
- Velocity thresholds are coarse anomaly indicators, not proof of fling. The observer skips velocity checks while seated, but legitimate knockback, launch pads, vehicles, custom mounts, network ownership transitions, and lag still need live testing before any enforcement could be considered.

### Existing teleport/action validation

- The audited Tiki Tide Settings `TeleportTo` action validates a finite positive target UserId, resolves a live target on the server, rejects self-targeting, checks live characters and Humanoids, checks recipient consent or the SecurityCore `GlobalModeration` exception, then rechecks identities/consent after permission checks.
- Actor and recipient cooldowns are reserved without yielding. The destination is derived from the server-observed target transform; a short-lived server-only ticket is consumed by `Complete` after the server applies the CFrame move.
- Ticket completion checks actor/target identity, expiry, character/root identity, finite world bounds, and destination tolerance. The action fails closed if the service is unavailable.
- `TeleportValidationService` itself trusts its server-script callers to complete their own authorization checks. Its origin allowlist includes `TikiTideSettings`, `KohlsAdmin`, `VIPZone`, `SpawnPad`, and `GameTeleport`; this repository audit confirms the Tiki Tide Settings call path but does not certify external or uninspected callers for every other origin.

### Other movement-related systems

- Utility Bar Size is a server-applied R15 scale change with a bounded factor of 0.5×–5× and a matching MovementAuthority registration.
- Utility Bar Mount equips an existing Tool; the actual physics behavior of any supplied mount Tool is outside this source snapshot and is not certified here.
- Companion cloning positions the clone near the character; it is not a player teleport.
- The supplied `RegularCommandsSecurityServer.lua` adapter maps Kohl's `gravity`, `starterspeed`, `speed`, `jumppower`, `jump`, `size`, `fly`, `unfly`, `freeze`, `thaw`, `bring`, `fling`, `tp`, and `to` aliases to SecurityCore permission checks and bounded argument/target validation before the command handler runs.
- Its handler wrapper records MovementAuthority markers after the native command handler returns. Those markers are observer metadata; they do not independently authorize or block the Kohl's action. The pre-handler SecurityCore command filter is the authorization gate.
- CharacterPhysicsGuard currently consumes markers for WalkSpeed, JumpPower, BodyScale, WorldGravity, and the special Fling presence check. It does not consume Flight, Frozen, Teleport, JumpImpulse, or StarterWalkSpeed markers. Flight/freeze/teleport command entries therefore must not be described as verified physics-observer coverage.
- This audit does not inspect Kohl's Admin's internal implementation of each movement handler, so it cannot certify exact flight, freeze, fling, teleport, or target replication behavior. It also does not establish complete validation for vehicles, custom knockback, or all third-party movement commands.

## Source changes in Phase 19

- [x] Keep the existing MovementAuthority and CharacterPhysicsGuard architecture; do not add a second physics authority.
- [x] In MovementAuthority.Check, reject and clear a player-target grant if its target is no longer an active Player.
- [x] Restrict the special `ANY` check to `Fling`; it cannot be used as a wildcard for WalkSpeed, gravity, scale, or other properties.
- [x] Preserve the existing BindableFunction contract, permission authority, movement settings, Utility Bar behavior, and teleport ticket API.
- [x] Document confirmed call paths separately from unverified integrations and detection-only coverage.

## Runtime acceptance matrix — still required

1. **Normal movement:** default walk/jump, repeated jumps, slopes, stairs, swimming, seats, respawn, and character replacement.
2. **Tiki Tide movement:** entitled player changes to WalkSpeed and JumpPower at minimum/maximum bounds; non-entitled and malformed requests are rejected by the settings service.
3. **Utility Bar Size:** R15 scale from 0.5× through 5×; R6 rejection; repeated changes; respawn; entitlement changes; baseline restoration.
4. **Gravity:** authorized GlobalConfig changes at bounds, unauthorized requests, simultaneous changes, and server startup ordering.
5. **Teleport:** consent on/off, staff exception, recipient departure, actor departure, respawn during action, cooldown races, expired/replayed tickets, destination mismatch, and service unavailable.
6. **Physics/network:** latency, packet jitter, client network ownership, high-speed legitimate launch/knockback, angular impulses, collision impacts, and seated/vehicle states.
7. **Special movement:** the supplied Kohl's adapter must be tested alias-by-alias for gravity, starter speed, speed, jump power, jump, size, fly/unfly, freeze/thaw, bring, fling, tp, and to. Confirm the SecurityCore filter denies before native handlers execute. The current wrapper records a marker after the native handler returns but does not inspect the handler's result tuple, so a failed native command may still leave a short-lived observational marker; verify this behavior and treat the marker as non-authoritative. Inspect each actual mount/vehicle, staff teleport, freeze/unfreeze, and knockback implementation individually. Add explicit registration origins only after the real server-side caller and its authorization checks are verified.
8. **Delayed character assembly:** test a custom rig where Humanoid and HumanoidRootPart appear after CharacterAdded; confirm both observers attach within the bounded wait, and confirm respawn/player departure/service shutdown during either wait leaves no stale connections.
9. **Compatibility:** PC, mobile, and console; no UI changes are part of this phase.
10. **Regression:** ClubMusic playback/crossfade, local queues, playback-only global sync, purchases/receipts, moderation, Settings, Utility Bar, mounts, spectator, diagnostics, and installer rollback.
8. **Adversarial cases:** attempt client-side WalkSpeed/jump changes, remote payload tampering, forged teleport requests, replayed requests, and extreme physics. Confirm the server-side action checks remain authoritative and telemetry alone never changes gameplay.
9. **Compatibility:** PC, mobile, and console; no UI changes are part of this phase.
10. **Regression:** ClubMusic playback/crossfade, local queues, playback-only global sync, purchases/receipts, moderation, Settings, Utility Bar, mounts, spectator, diagnostics, and installer rollback.

## Release boundary

- No automatic kick, ban, movement correction, teleport, freeze, or gameplay restriction is introduced.
- A physics signal is an investigative clue, not proof and not a punishment trigger.
- Do not add velocity-based punishment or rollback until legitimate launch, knockback, vehicle, network-ownership, and lag behavior has measured false-positive rates and a server-authoritative movement envelope has been designed.
- No Studio runtime, published-server, adversarial exploit, device, or performance tests are claimed by this source commit.
- No audio, queue, receipt, entitlement, UI, or mobile behavior was intentionally changed.

**Exit criteria:** each real movement/action path has a named server owner, explicit SecurityCore/entitlement checks, bounded validation, and a verified MovementAuthority registration where appropriate; legitimate physics is covered by the test matrix; detection remains non-enforcing until evidence supports a safe policy.
