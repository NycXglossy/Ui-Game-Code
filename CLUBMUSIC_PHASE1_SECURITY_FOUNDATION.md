# Phase 1 — Security Foundation Work Log

## Scope

This branch is based on the repository commit supplied with the Security Core installer. It is intentionally isolated from the default branch. No Roblox installer has been run and no live game changes have been made.

## Completed: movement-authority API contract correction

The public server-side BindableFunction contract is now explicit:

- `Invoke("Register", actorId, targetId, property, value, origin, ttl)`
- `Invoke("Check", targetId, property, value)`
- `Invoke("Status")`

The previous dispatcher accepted seven positional parameters for every operation. The CharacterPhysicsGuard caller supplies only the three arguments required by Check after the operation name, so the old dispatcher shifted the values and passed the wrong target/property/value to the ledger. The corrected dispatcher routes Check's first three arguments directly to `MovementAuthority.Check`.

Existing Register callers retain their current argument order:
- Kohl's regular-command adapter
- Utility Bar size action
- Tiki Tide settings movement registration

The ledger remains server-local, bounded, expiring, and independent of DataStore/MemoryStore.

## Teleport entry points found in the inspected repository snapshot

1. `TikiTideSettings/TikiTideSettingsService.server.lua`
   - Action: `TeleportTo`
   - Validates target player, target consent, Tiki Tide entitlement, and moderator override.
   - Directly assigns the requesting player's HumanoidRootPart CFrame near the target.
   - This is the first direct player teleport to route through TeleportValidationService.

2. `RegularCommandsSecurityServer.lua`
   - Kohl's command policy includes `bring`, `tp`, and `to`.
   - The adapter currently registers a generic `Teleport` movement authorization after the wrapped command handler executes.
   - It does not yet capture and validate the expected destination before the character moves.
   - The command implementation itself is supplied by Kohl's Admin and is not contained in this repository snapshot, so its handler semantics must be verified before changing execution order.

3. `UtilityBar/UtilityBarExtendedActions.server.lua`
   - Uses `Model:PivotTo` for the temporary visual companion clone.
   - This moves the clone, not the player's character; it is not a player teleport entry point.

The inspected main controller did not expose another direct player CFrame/PivotTo teleport in the searched movement-related paths. This is not a claim that every external Kohl's Admin or third-party script has been audited.

## Completed: initial TeleportValidationService integration

Added `ClubMusicSecurityCore/TeleportValidationService.lua` and routed the Tiki Tide Settings `TeleportTo` action through it.

The service:
- is a server-only ModuleScript; no RemoteEvent or client ticket API is exposed;
- accepts only live Player instances and server-derived finite Vector3 destinations;
- restricts trusted origin labels to a small allowlist;
- issues short-lived (1–15 second), single-use tickets bound to actor, moved player, destination, source position, character/root instance and origin;
- rejects coordinates outside a broad configured world envelope (±100,000 studs per axis);
- verifies the current server-owned character/root is still the same instance captured at authorization time, then checks its server-observed position within 8 studs of the ticket destination;
- expires tickets, consumes them on verification, cleans actor/target tickets on PlayerRemoving, and caps outstanding tickets at 128;
- emits bounded signals for expired, mismatched, invalid and replayed tickets;
- does not kick, ban, snap back or otherwise punish a player.

The Tiki Tide Settings action retains its existing entitlement, consent, moderator-override, participant and character checks. It now requests a ticket before the CFrame mutation, verifies the resulting position, and fails closed if the validation service is unavailable. A failed post-move verification is reported but does not trigger an automatic snapback.

The installer now includes `TeleportValidationService` and pins the module bundle to the corrected release commit. It has not been executed.

## Next implementation slice

Integrate Kohl's Admin `bring`, `tp` and `to` commands with the same ticket API. The command implementation is supplied by Kohl's Admin and is not contained in this repository snapshot, so its handler semantics must be confirmed before changing execution order. Then add explicit teleport diagnostics and complete the Studio test matrix before enabling any automated response.

## Required Studio test matrix before enabling

- Authorized self teleport to a consenting player succeeds.
- Teleport without target consent is rejected.
- Non-entitled user teleport is rejected.
- Staff override succeeds only for an authorized staff member.
- Missing character/root and stale target are rejected safely.
- A destination outside configured world bounds is rejected.
- An expired, replayed, wrong-target, or wrong-destination ticket is rejected.
- Kohl's bring/tp/to commands register the correct target and destination.
- Normal walking, jumping, respawn, knockback, vehicles, and Utility Bar size changes do not create teleport incidents.
- No automatic kick/ban or forced snapback occurs during this initial phase.

## Safety status

- No live Roblox place was modified.
- No Studio or published-server runtime test has been performed.
- The installer is updated to include the new module and pins its source bundle to the corrected security release. It has not been run in Studio.
