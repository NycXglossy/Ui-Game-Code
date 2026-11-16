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

## Next implementation slice

Create a dedicated server-only `TeleportValidationService` and integrate it first with the Tiki Tide Settings `TeleportTo` action. Then adapt Kohl's `bring`/`tp`/`to` commands after confirming their actual target/destination semantics.

The service must:
- accept requests only from trusted server code;
- require a live actor and target, a finite destination, a bounded reason/origin, and a short-lived authorization record;
- validate destination bounds and safe character/root state;
- record origin, target, actor, source/destination, issue time, and expiry in a bounded per-server ledger;
- verify the resulting server-observed position against the authorized destination;
- expire and consume tickets, clean player state on departure, and emit bounded security signals;
- never punish from one unexplained displacement and never let the client create authorization;
- remain detection/validation-only until Studio tests demonstrate safe behavior.

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
- The existing installer file has not been updated in this branch yet. Do not run the old installer as a way to deploy this branch's movement API correction; its pinned release still points to the prior module snapshot.
