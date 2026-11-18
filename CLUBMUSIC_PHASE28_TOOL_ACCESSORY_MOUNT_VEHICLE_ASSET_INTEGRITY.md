# Phase 28 — Tool, Accessory, Mount, Vehicle & Asset Integrity

**Status:** Tracked first-party source investigation recorded. Existing detection-only Tool/Accessory observation is implemented. Remote spawn/despawn, mount/vehicle ownership, seat policy, collision-group policy, approved grant provenance, third-party package provenance, and runtime certification remain open. No live-place or Studio runtime result is claimed.

**Phase relationship:** Phase 28 is cumulative and independent on top of Phases 25, 26, and 27. It does not replace those phases. Phase 26 remains the authority for character movement measurement and teleport context; Phase 27 remains the authority for world/environment integrity; Phase 25 remains the authority for remote ingress and exploit prevention. Phase 39 certification/controlled retirement and Phase 40 cleanup/consolidation remain separate.

**Audit baseline:** `fix/security-core-release-and-queue-loop`, commit `ffd483159c34d4bfa3389d3830bc832e29bfaa2b` (2026-11-18). All changes from this investigation are to remain on the feature branch until separately approved. Git commits do not update the live Roblox place.

## Goals

- Inventory mount and vehicle models, scripts, seats, constraints, network ownership, grant paths, and cleanup.
- Replace the current Mount Tool equip/unequip interaction with one server-authoritative Spawn/Despawn lifecycle when the actual approved mount model and hierarchy are identified.
- Reuse the existing Security Core authorization, existing server-verified Island Mount pass state, existing remote validation/budgets, and existing movement authorities.
- Record server-visible Tool/Accessory changes and mount/vehicle anomalies as bounded evidence without automatically stripping legitimate assets or punishing a player from one signal.
- Inspect companion clones, avatar refresh, Tool Shop, Kohl's Admin, F3X/Building Tools, and asset insertion/provenance paths.
- Validate R6, R15, custom rigs, avatar scaling, respawn, network ownership, seat transitions, and cleanup.

## Existing architecture and source findings

### Mount feature and UI contract

- The existing Utility Bar uses `UtilityBarRemotes.ExecuteUtility` (a RemoteFunction) and the allowlisted action name `Mount`.
- The server action in `UtilityBar/UtilityBarExtendedActions.server.lua` checks the server-populated `HasIslandMountPass` attribute, then searches the invoking player's Character and Backpack for an existing Tool marked `UtilityMount=true` or named `Mount` / `MountTool`. It equips or unequips that Tool through the server Humanoid.
- This action does not grant or clone a mount, verify its asset provenance, or establish an approved mount catalog. The README explicitly assigns actual mount behavior/assets to the Tool.
- The client UI defines a Mount button and pass prompt. The existing UI is not yet a Spawn/Despawn toggle, and the current action does not send a spawn/despawn operation.
- The current server pass source is `UI_Server_Controller_server (1).lua`: `refreshPersonalPasses` calls `MarketplaceService:UserOwnsGamePassAsync` through the controller's server-owned helper for pass ID `2087955619`, then sets `HasIslandMountPass`. The client cannot supply the pass ID or set the server attribute through this path.
- Important authority distinction: SecurityCore `EntitlementAuthority` currently resolves the VIP, VVIP, and Tiki Tide membership tiers; it is not configured with the Island Mount feature pass. Do not document or implement Island Mount as though that membership resolver already checks it. Reuse the controller's existing server-verified feature-pass path unless a deliberate, reviewed consolidation changes that authority.
- The controller's `AvatarAccessoryValidationService` is initialized and stopped by the main controller. The service is detection-only and never strips or rewrites assets.

### Recommended Spawn/Despawn design

One server-side mount service should own the complete lifecycle. The client asks for an operation; it never chooses an arbitrary asset ID, Instance, or unapproved template name.

- Keep one canonical server handler and one server-side active-mount record per player. The record—not a replicated `OwnerId` attribute—is the ownership authority.
- Use a fixed server-owned allowlist/catalog of approved mount templates stored in a server-only container after the actual model and scripts have been reviewed. The client should request a logical mount key only if multiple approved mounts are intentionally offered; otherwise the server chooses the one configured mount.
- Gate Spawn using the existing server-verified `HasIslandMountPass` state. Do not use the generic `IsVIP` attribute as a substitute for the Island Mount pass.
- Make Spawn idempotent: if the player already has a live mount, return its current state rather than cloning another. Make Despawn idempotent: if no mount exists, return an already-despawned result.
- Serialize per-player spawn/despawn transitions so concurrent requests cannot create duplicate mounts or race cleanup. Retain bounded request budgets/cooldowns and clean per-player state on departure.
- Validate the current character, Humanoid, root, health, template class, expected assembly root, required seats, and model descendants before cloning. Recheck the same character and its root after any yield and before parenting.
- Place the model at a tested safe offset and validate that the target location is usable. Do not assume a fixed five-stud offset is collision-safe for every model.
- Keep a server-side mount-to-owner map and explicit lifecycle connections. A replicated OwnerId attribute may be added as display/debug metadata, but it must never be the sole permission check.
- Despawn on explicit owner request, owner departure, owner character lifecycle according to the chosen gameplay policy, replacement, mount destruction, and server shutdown. Disconnect all seat/property/ancestry connections and clear tables.
- Use a single service integrated with the current Utility Bar action. Do not add a second mount RemoteEvent/service while leaving the old equip/unequip authority active. Preserve the existing remote name and UI contract where feasible; a contract migration must update server, client, README, and tests together.
- Decide whether mounts are single-driver only or support passengers. If passengers are supported, define their authorization separately from owner-only driver permission. Check every relevant Seat/VehicleSeat, not just the first descendant.

### Supplied RemoteEvent mount-spawner example — review

The example has useful ingredients: server-side lookup, request type validation, cooldown, one active mount table, server positioning, and PlayerRemoving cleanup. It is not ready to install:

- A template found by arbitrary client string is not an approved asset catalog. Validate the exact model type, descendants, scripts, assembly, seats, and source before use; prefer server-only template storage.
- Its `VIPOnly` + `IsVIP` check is not the Island Mount feature-pass gate. Use the existing server-verified `HasIslandMountPass`.
- The active table and cooldown table need bounded lifecycle cleanup, reentrancy protection, and a shared server ingress budget.
- It does not guard against a character changing while a request is being processed, malformed/incomplete models, unsafe spawn positions, or duplicate concurrent requests.
- It checks only the first Seat/VehicleSeat and only ejects a non-owner when a Player is resolved. It does not define passenger policy or handle all seat changes.
- It does not configure or audit network ownership, vehicle movement, assembly integrity, or all cleanup paths.
- Use the example as a design reference, not as a second implementation.

### Supplied vehicle seat/network-ownership/anti-speed example — review

Useful concepts:
- Validate the assigned driver when the seat occupant changes.
- Give a valid driver appropriate network ownership for responsive physics.
- Return ownership to the server when the vehicle is empty, if the complete assembly and game design support that policy.
- Observe server-side vehicle motion and record abnormal movement.

Required corrections before implementation:
- A model attribute such as `OwnerId` is metadata, not the authoritative owner record. Resolve the seat, mount, and driver through the server-owned active-mount registry.
- If the occupant is not associated with a live Player character, the example does not eject them. Define explicit behavior for NPCs, stale Humanoids, owner changes, passengers, and owner departure.
- Revalidate when owner/mount state changes, not only when Occupant changes.
- Inspect the actual connected assembly and its root before calling `CanSetNetworkOwnership` / `SetNetworkOwner`. Assign ownership at the appropriate assembly level and handle API failure; do not assume the Seat alone represents the whole model.
- Network ownership improves responsiveness but gives the owning client influence over physics simulation. It is not proof of trustworthy movement. Keep server-observed validation and a conservative recovery policy separate.
- A fixed 150 studs/second threshold is unsupported until the actual mount model, speed capabilities, impulses, terrain, latency, and baseline traces are measured.
- A single Heartbeat displacement sample is not an exploit verdict. Guard zero/invalid time steps, sample gaps, latency, collisions, slopes, launch/knockback, and ownership handoffs; require sustained multi-sample evidence.
- Resetting every descendant's assembly velocities can redundantly affect one assembly and abruptly destroy legitimate motion. `CFrame.new(lastPosition)` also discards the prior orientation. Do not use this recovery method.
- Any future correction must be a separate, approved rollout gate with a validated safe transform, preserved orientation and legitimate momentum where possible, bounded correction rate, and jitter/false-positive tests. Detection remains the default.

### Existing movement authority and observation

- `CharacterPhysicsGuard` is server-local and detection-only. It samples the player's HumanoidRootPart position at approximately 0.5-second intervals, stores only the immediately previous sample for the active character, and aggregates total/horizontal/vertical displacement-speed bands, grounded/airborne/seated context, root network-owner buckets, and server-observed latency buckets.
- It consumes the existing one-use verified teleport marker from `TeleportValidationService` and resets the character displacement baseline after a validated teleport.
- It observes the character root, not the mount/vehicle assembly. It does not establish mount/vehicle network ownership or a vehicle movement envelope.
- Its velocity-change observer uses coarse 300 linear / 120 angular thresholds and excludes seated characters. These are detection-only signals, not a vehicle anti-speed policy.
- `MovementAuthority` is a bounded, server-local ledger for known character movement changes. It is not currently a generic vehicle grant system. Do not add a broad bypass or reuse character property grants to authorize arbitrary vehicle speed.
- Phase 26 already requires actual mount/vehicle/knockback/launch source inventory and runtime baselines before movement thresholds, noclip/fly decisions, or correction can be enabled.
- Do not create a second Heartbeat character correction loop. If vehicle monitoring is eventually needed, keep it in the one mount/vehicle lifecycle owner and expose bounded evidence to the existing security recording path.

### Collision groups and oversized-part example — review

- The supplied `PhysicsService` example's intent—assign a dedicated character group and disable player-to-player collision—is reasonable only after the full collision matrix is inventoried.
- Calling `RegisterCollisionGroup` without checking whether the group already exists can fail. The example also only hooks future PlayerAdded/CharacterAdded events and does not process players already present when the Script starts.
- Assigning every character BasePart, including accessory and Tool parts, can change intended gameplay collision behavior. The complete matrix must include characters, mounts, vehicles, accessories, tools, stage props, moving platforms, doors, and protected world geometry.
- No complete first-party collision-group matrix or live assignment policy is established by this source review. Absence from the reviewed tracked files is not proof that the live place or packages have no collision configuration.
- The proposed `Size.Magnitude > 20` destruction rule is rejected. Size alone is not evidence of an exploit; legitimate mounts, tools, accessories, or map objects may be large. Record bounded observations for review instead of destroying parts.
- Do not blanket-assign collision groups or rewrite the matrix until the actual place hierarchy, existing group registrations, collision pairs, and intended pass-through rules are captured.

### Protected Tool example — review

- `OwnerId` is useful metadata but does not prove that a Tool was granted by an authorized server path.
- `CanBeDropped=false` prevents ordinary Tool dropping behavior; it is not an ownership or anti-exploit boundary.
- `AncestryChanged` fires during legitimate parent transitions. Backpack ↔ Character equip/unequip and StarterGear persistence must not be treated as theft.
- The example's `GetPlayerFromCharacter(newParent)` only resolves a character model passed as the new parent; a Player is not an ancestor of its Character in the DataModel hierarchy. The fallback `FindFirstAncestorWhichIsA("Player")` is not a reliable way to recover an owner from a Tool's parent.
- Destroying a Tool when it is briefly in Workspace or held by a different player can delete a legitimate item during an authorized transfer or other server operation. Automatic destruction is not adopted.
- Use a server-owned grant/provenance record tied to a specific approved grant operation, target player, Tool instance/asset key, and permitted containers. Inventory observation remains evidence only until a grant-path registry exists.

### Existing Tool, Accessory, companion, and avatar paths

- `AvatarAccessoryValidationService` observes Tools in Backpack, Character, and StarterGear; signals additions after appearance initialization and removals after a deferred parent-transition check; and bounds tracked Tools per player at 100.
- It observes Accessory additions/removals and Handle Size/CanCollide changes, retains existing description asset-ID/count/duplicate/handle checks, and caps accessory observers at 50 per character.
- It never strips, destroys, disables, or re-equips a Tool or Accessory. A newly observed Tool is not conclusively classified as unauthorized because legitimate server grants can also occur after appearance initialization.
- The main controller starts the observer and calls Stop during script destruction; PlayerRemoving and character teardown clean its per-player/per-character connections.
- Companion Clone is server-created from the caller's current Character, removes Script/LocalScript descendants, disables collision/touch/query on BaseParts, makes them massless, anchors the clone root, follows the owner for 12 seconds, and destroys it on expiry or PlayerRemoving. Test equipped Tool/accessory visuals, respawn, replacement, and server shutdown.
- Tool Shop is currently an empty placeholder: its server RemoteFunction supports only `GetShop` and returns an empty item list. It does not purchase, clone, grant, or equip Tools.
- Avatar refresh fetches the caller's own HumanoidDescription on the server, rechecks character identity after the asynchronous lookup, and applies it to that character. No client target or arbitrary description is accepted.
- Utility Bar scale is server-side, self-only, R15-only, and accepts 0.5×–5×. It registers BodyScale with the existing MovementAuthority. CharacterPhysicsGuard observes the four R15 scale values against a baseline with broad 0.1×–10× sanity bounds and records signals only. Do not add a conflicting fixed 0.85×–1.15× clamp or duplicate Changed handler. R6/custom rigs need separate tests.

### Kohl's Admin, F3X, and asset provenance

- The tracked Kohl's policy adapter maps `give`, `startergive`, `starterremove`, `copytools`, `gear`, `btools`, and `insert` to existing SecurityCore `GlobalConfig` authorization and a bounded Asset budget. It validates live Player targets and caps target count.
- The adapter wraps native handlers and records invocations; it does not verify the native handler's success or inspect the exact Tool/asset instances created. It does not provide an approved asset-ID catalog or grant provenance registry.
- `GlobalConfig` is the existing high-privilege owner/co-owner boundary, not a general player grant permission.
- The tracked hardening patch disables selected external InsertService/auto-update paths and validates selected building-tool paste operations, but the repository file does not prove that the patch has been applied to the live package.
- The tracked Kohl's Admin model export is approximately 7.4 MB and was not fully inspected by the available repository reader. Native command implementations, descendants, and the actual live installation remain unaudited.
- The tracked Building Tools client source uses SyncAPI; the matching server-side SyncAPI implementation and live package provenance were not established in this pass.
- A complete package audit must inspect all Script/LocalScript/ModuleScript descendants, numeric `require(assetId)` calls, asset insertion/loading paths, runtime-created remotes, and server-side privilege/state mutation paths. Do not execute unknown assets or automatically delete/disable code based only on keyword matches.

## Decisions from this investigation

1. Adopt Spawn/Despawn as the intended Island Mount interaction; retire the Tool equip/unequip action only as part of a single coordinated server/client migration.
2. Do not implement the mount spawner until the actual approved mount model, scripts, assembly, seats, and source location are supplied or verified in the live place.
3. Do not use `IsVIP` for Island Mount authorization. Reuse the existing server-verified `HasIslandMountPass` path.
4. Do not add a second entitlement resolver, role resolver, remote gateway, generic limiter, movement bypass, or parallel vehicle service.
5. Keep mount ownership in a server-owned registry. Attributes are metadata only.
6. Define driver and passenger policy explicitly; validate all seats and all ownership transitions.
7. Treat network ownership as a physics responsiveness decision, not an authorization mechanism. No blanket `SetNetworkOwner(nil)`.
8. Do not add the fixed 150 studs/sec limit, one-frame Heartbeat rollback, velocity-zeroing, or orientation-losing CFrame reset.
9. Keep Tool/Accessory/oversized-part detection evidence-only. No automatic asset deletion or punishment from one signal.
10. No collision matrix rewrite until actual collision groups and live map geometry are inventoried.
11. Keep third-party package findings open until the full installed package and live descendants are inspected.
12. Map-dependent geometry, protected-zone, collision, and wall-clip tests remain deferred until the actual map is supplied. Map-independent source and package investigation continues.

## Acceptance matrix

### Spawn/Despawn and entitlement
- [ ] Existing pass owner can Spawn; non-owner cannot; Marketplace lookup failure behavior is fail-closed.
- [ ] Client cannot choose arbitrary asset IDs, Instances, or unapproved templates.
- [ ] Repeated/concurrent Spawn creates at most one mount; repeated Despawn is harmless.
- [ ] Despawn is owner-only; forged OwnerId attributes do not transfer authority.
- [ ] Character replacement during spawn, missing root, dead Humanoid, invalid template, and unsafe spawn position fail safely.
- [ ] Owner respawn, departure, mount destruction/replacement, and server shutdown clean up all instances, records, and connections.

### Seats and network ownership
- [ ] Unauthorized driver is rejected; passenger policy is tested separately.
- [ ] Every Seat/VehicleSeat is covered; stale Humanoids, NPC occupants, owner changes, and simultaneous seat changes are handled.
- [ ] Ownership assignment targets the intended assembly, checks CanSetNetworkOwnership, handles failure, and returns to server policy when empty.
- [ ] Test ownership handoffs, driver departure, seat destruction, unanchored/anchored/ineligible assemblies, and multiple simultaneous vehicles.

### Vehicle movement
- [ ] Measure legitimate top speed, acceleration, braking, slopes, collisions, knockback, launch impulses, and latency across every approved vehicle.
- [ ] Compare server-observed assembly displacement and velocity over sustained windows; one sample never triggers punishment or rollback.
- [ ] Include network ownership transitions, respawn, teleport, moving platforms, and vehicle exit/entry as explicit contexts.
- [ ] If a later recovery proposal is approved, test orientation preservation, safe destination validation, legitimate momentum, correction rate, jitter, and false positives. Keep correction disabled until separately approved.

### Tools, accessories, avatars, and packages
- [ ] Correlate every approved grant path with the observed Tool instance, actor, target, asset key, and allowed containers.
- [ ] Test authorized and denied Kohl's grant aliases and malformed/multiple targets.
- [ ] Confirm Backpack ↔ Character equip/unequip is not a false removal; test StarterGear, Backpack replacement, death, respawn, and PlayerRemoving.
- [ ] Test avatar refresh and accessory additions/removals on R6, R15, and custom rigs; no automatic stripping.
- [ ] Test Handle Size/CanCollide mutation, oversized accessory/tool parts, and diagnostic caps.
- [ ] Test companion clone with equipped Tools/accessories, respawn, replacement, expiry, PlayerRemoving, and shutdown.
- [ ] Inspect full Kohl's Admin and F3X package descendants, SyncAPI server handlers, external module/asset dependencies, and whether hardening patches are applied to the live model.

### Collision and world geometry
- [ ] Inventory existing PhysicsService groups and the complete collidability matrix before any change.
- [ ] Test player/player, player/accessory, player/tool, player/mount, mount/world, vehicle/world, props, doors, moving platforms, and intended pass-through areas.
- [ ] Confirm no size-only destructive rule is active.
- [ ] After the actual map is supplied, test protected geometry, collision boundaries, streaming, doors, moving barriers, and legitimate teleport/pass-through routes.

### Lifecycle, load, and compatibility
- [ ] Test R6, R15, custom rigs, avatar scale 0.5× / 1× / intermediate / 5×, and unsupported R6 scale behavior.
- [ ] Test repeated respawns, player churn, Backpack replacement, many simultaneous mounts, and long-running servers.
- [ ] Verify bounded tables, event connections, observer counts, CPU cost, and deterministic cleanup.
- [ ] Run Studio and published-server tests on PC, mobile, and console with representative latency and server load.

## Map-independent implementation updates applied (2026-11-17)

The user confirmed that the map is unfinished but map-independent updates may proceed. The following scoped code changes were applied on this feature branch:

### Companion clone lifecycle

- `UtilityBar/UtilityBarExtendedActions.server.lua` now keeps an explicit server-side `companionByPlayer` registry instead of finding a prior clone by a Workspace name.
- Replacing a companion destroys the previously tracked clone; the follow loop verifies that its clone is still the active registry entry before moving it.
- CharacterAdded and CharacterRemoving both clean up the owner's companion immediately.
- PlayerRemoving destroys the tracked clone and disconnects that player's lifecycle connections.
- Script Destroying disconnects PlayerAdded/PlayerRemoving and per-player lifecycle connections, then destroys all tracked companions.
- Aura cleanup now shares the same tracked CharacterRemoving connection instead of creating an untracked per-player connection.
- The 12-second companion lifetime, visual-only clone behavior, and pass gate are unchanged.

### Inventory observer connection lifecycle

- `ClubMusicSecurityCore/AvatarAccessoryValidationService.lua` now stores inventory-container connections per Backpack, StarterGear, and Character rather than appending all container connections to a player/character lifetime array.
- When a container is detached or replaced, its listeners are disconnected and its container entry is removed.
- Tools left in a detached container are reconciled through the existing deferred removal check. A Tool already transferred to the current Character or replacement Backpack is retained and does not create a false removal signal.
- Character replacement detaches the previous Character inventory observer.
- PlayerRemoving and service Stop disconnect all remaining container listeners and clear the maps.
- Detection-only behavior is preserved; no Tool or Accessory is destroyed, stripped, disabled, or re-equipped.

**Code commits:**
- Companion lifecycle: `2c33e76651cf7afd9a64ebf751309a1f7166925c`, with connection teardown refinements in `a45b95d5be0ea195171ce40581fbaf3b2e9b3a23` and `e7493d988a17b64fc81a7264add600983bde62d2`.
- Inventory observer replacement cleanup: `677f19bf198dad22aabe6ec32d221dd964b81624` and detached-container Tool reconciliation `1601754bae5629a25070c9ffea8894eb9e0ef7b4`.

These are static source changes only. They still require Luau/Studio runtime tests for respawn, replacement, concurrent grants, player churn, and teardown.

## Verification boundary and current status

This is a tracked-source investigation and design decision record, not a runtime certification. The repository contains no separately named first-party vehicle/mount controller in the inspected tree; no approved mount model or vehicle assembly was available in the reviewed source files. No complete collision-group policy was established. Third-party Kohl's/F3X internals and live-place descendants remain unaudited. No Luau parser or Roblox Studio runtime was available during this repository pass, so no runtime test is claimed as passed.

**Completed:** companion clone lifecycle cleanup hardened; inventory observer connection cleanup across Backpack/Character replacement hardened; existing Utility Bar mount behavior traced; server-side feature-pass source distinguished from membership EntitlementAuthority; current movement and avatar observers reviewed; supplied collision, Tool ownership, mount spawning, and vehicle anti-speed examples assessed; existing companion, Tool Shop, avatar refresh, Kohl's/F3X boundaries documented.

**Not implemented yet:** Spawn/Despawn service (the actual approved mount model and hierarchy are not in the tracked source tree, so the old Tool action remains until a coordinated model-backed migration can be built), approved mount catalog, seat/driver/passenger policy, mount/vehicle network ownership, vehicle movement monitor, collision matrix changes, Tool grant provenance registry, package/live-place audit, and runtime certification. These require the actual mount/vehicle model and live hierarchy to avoid inventing assets, scripts, or physics assumptions.
