# Phase 27 — World & Environment Integrity

**Status:** Initial tracked-source audit committed. No environment drift enforcement, automatic restoration, terrain blocking, or entitlement-policy changes are enabled. Live place/package inventory and runtime acceptance remain open.

**Branch:** `fix/security-core-release-and-queue-loop`

## Safety boundary

Phase 27 is audit-first and detection-only. Do not automatically reset Lighting, Workspace.Gravity, Terrain, atmosphere, tagged stage fixtures, or player entitlements in response to a mismatch. A property change, missing marker, stale attribute, or unexpected instance is not by itself proof of exploitation.

Do not remove or rewrite terrain, disable scripts, revoke passes, change VIP tiers, kick, ban, or otherwise punish a player based on environment telemetry. Any future corrective action requires a separate design review, a verified authoritative writer inventory, safe rollback semantics, and Studio plus published-server acceptance.

## Existing architecture to preserve

- `ClubMusicSecurityCore/Authorization.lua` is the single staff permission authority. `GlobalConfig` requires SecurityCore level 3 (Co-owner/Owner); do not add a second role or permission resolver.
- `ClubMusicSecurityCore/EntitlementAuthority.lua` resolves membership tiers using the existing Authorization group cache and bounded session-only game-pass cache. It does not use DataStore or MemoryStore.
- `ClubMusicSecurityCore/CharacterPhysicsGuard.lua` already observes `Workspace.Gravity`, checks finite/range bounds, and delegates authorization markers to the existing `TikiTideMovementAuthority` BindableFunction. It never changes gameplay state.
- `ClubMusicSecurityCore/MovementAuthority.lua` is a movement approval ledger, not a general environment permission system. Do not overload it with arbitrary Lighting/Terrain bypasses.
- `UtilityBar/UtilityBarExtendedActions.server.lua` owns the pass-gated Stage & Club Lighting action. It only affects Light/Beam descendants of instances tagged `StageClubLight`; it deliberately does not change the global `Lighting` service or unrelated island fixtures.
- `RegularCommandsSecurityServer.lua` is the server-side Kohl's Admin policy adapter. Its existing `GlobalConfig` authorization and bounded World budget must remain the gate for world-changing aliases.
- `UI_Server_Controller_server (1).lua` owns verified game-pass lookups and publishes server-computed feature attributes. Clients do not supply pass IDs or ownership claims.

## Tracked-source audit — confirmed findings

### World physics and gravity

- `CharacterPhysicsGuard` captures the startup gravity baseline and observes `Workspace.Gravity` changes.
- It currently treats values outside 0–500 as a fixed-range signal and otherwise asks MovementAuthority whether the exact new value has a live `WorldGravity` approval.
- The tracked Kohl's adapter maps `gravity` to `GlobalConfig`, validates the numeric range, and registers a world-scoped approval after its wrapped native handler runs.
- Phase 26's source inventory records Tiki Tide Settings as another gravity writer, with a supported range of 20–192.62 and GlobalConfig authorization. The exact live hierarchy/call path still needs verification against the published place.
- No gravity correction or reset is performed by the observer.

### Lighting and stage/club fixtures

- The Utility Bar lighting action requires the server-populated `HasStageClubLightingPass` attribute and a valid server-side action envelope/cooldown.
- The action discovers only CollectionService-tagged `StageClubLight` roots and their descendants. Supported fixtures are PointLight, SpotLight, SurfaceLight, and Beam.
- Presets are fixed (`Ocean`, `Sunset`, `Royal`, `Tiki`, plus `Off` restore). Original per-instance light state is retained in server memory for restoration. The current state table is keyed by Instance and is not persistent.
- The tracked Kohl's policy adapter protects the `time`, `brightness`, `colorshift`, `latitude`, `diffusescale`, `exposure`, and `disco` aliases with `GlobalConfig` authorization and a separate bounded World budget.
- The tracked controller source does not itself write global Lighting properties. The exact native Kohl's handlers and any other live-place lighting scripts are outside the inspected text-source boundary.
- No Lighting drift monitor or automatic restore was added in this phase's initial audit.

### Terrain and protected environment

- The tracked Kohl's adapter maps `clearterrain` to `GlobalConfig`, marks it as a global world operation, and records an administrative audit event after the wrapped handler.
- This adapter-level policy does not prove that every Terrain writer, building tool, inserted asset, plugin, or server script is covered.
- The actual Terrain hierarchy, protected regions, map-specific destruction/building systems, and external packages must be inventoried in the live place before a protected-environment boundary can be defined.
- No Terrain mutation guard or restoration behavior was added. A blanket Terrain watcher would risk treating legitimate map/build operations as tampering.

### VIP, membership, and feature entitlements

- Staff permissions remain separate from membership tiers. Authorization uses group-rank thresholds and the existing cached rank resolver; membership uses EntitlementAuthority.
- EntitlementAuthority combines group membership, verified VIP/VVIP/Tiki Tide game-pass ownership, and the existing server-owned rewarded tier. Owner tier is derived from SecurityCore rank. It uses no persistent entitlement ledger.
- The main controller derives VIP attributes and pass tier from server-side services. Client attributes are not accepted as entitlement evidence.
- Feature passes (Island Mount, Island Companion, Stage & Club Lighting, and personal XP passes) are checked by the controller using MarketplaceService and exposed as server-set Player attributes. The Utility Bar checks those attributes before executing the matching action.
- Failed feature-pass lookups currently produce false for the affected lookup; membership EntitlementAuthority retains a previously verified positive result across a transient lookup failure for a short retry window. These are distinct behaviors and should not be silently unified.
- Purchase completion triggers feature-pass refresh or membership refresh as appropriate; the controller also periodically refreshes group rank and membership. Live testing is still needed for purchase completion, transient Marketplace failures, rejoin, cache expiry, and stale attribute handling.
- No new pass IDs, entitlement source, client-trusted flag, or permission tier was introduced.

## Phase 27 gaps — do not infer coverage

1. **Live writer inventory:** identify every script/package that writes Lighting properties, Workspace.Gravity, Terrain, Atmosphere, Clouds, post-processing effects, tagged fixture properties, and protected map state. Include runtime-created scripts and native Kohl's Admin handler implementations.
2. **Tiki Tide Settings path:** verify the actual server script, authorization call, supported values, reset/default path, and MovementAuthority registration against the live place.
3. **Lighting ownership:** inspect all tagged `StageClubLight` instances, confirm tag scope is intentional, find every non-UtilityBar writer, and test how the `Off` restore behaves if another authorized controller changes a fixture after the original snapshot.
4. **Kohl's native handlers:** verify whether the wrapped `time`, `brightness`, `colorshift`, `latitude`, `diffusescale`, `exposure`, `disco`, `gravity`, and `clearterrain` handlers actually succeed/fail as expected and whether aliases bypass the adapter.
5. **Terrain boundaries:** define protected and intentionally editable regions/objects from the real map; inventory legitimate build, cleanup, reset, and map-transition operations before considering any guard.
6. **Entitlement lifecycle:** test pass purchase, failed ownership lookup, cache expiry, leave/rejoin, entitlement refresh, group promotion/demotion, rewarded-tier changes, and feature attribute refresh. Confirm stale positive feature attributes cannot persist beyond the intended lifecycle.
7. **Runtime baseline:** record expected environment values at startup and after each authorized control, including simultaneous writes, server startup ordering, late-loaded packages, and server shutdown/restart.
8. **Bounded monitoring design:** only after writer inventory, choose a small fixed set of properties/signals, fixed-cardinality counters, bounded cooldowns, and deterministic cleanup. Keep diagnostics server-local and avoid logging arbitrary instance paths or raw payloads.

## Implementation decisions in this source pass

- Reused the existing SecurityCore.Authorization and EntitlementAuthority architecture; no parallel role, permission, or entitlement service was created.
- Preserved the existing MovementAuthority contract for gravity/movement only; no generic environment bypass or new authority marker was added.
- Preserved the StageClubLight tag boundary and the Utility Bar's existing feature-pass check.
- Preserved the Kohl's adapter's GlobalConfig policy and World budget; no command policy was weakened or broadened.
- Did not add a global Lighting watcher, Terrain mutation hook, auto-reset, or automatic enforcement because the complete live writer inventory is not yet established.
- Did not change game behavior or player entitlements in this audit pass.

## Phase 27 follow-up source trace — tracked writers and ownership (2026-11-17)

### Confirmed tracked mutation paths

| Area | Tracked writer / path | Existing gate and scope | Remaining concern |
|---|---|---|---|
| Global gravity | TikiTideSettings/TikiTideSettingsService.server.lua → SetGravity | Requires Tiki Tide access and SecurityCore GlobalConfig; finite numeric validation; clamps to 20–192.62; registers exact resulting value as WorldGravity with MovementAuthority | Verify installed hierarchy, reset/default path, and command alias interactions in Studio |
| Teleport CFrame | Tiki Tide Settings TeleportTo | Validates live actor/target, recipient consent or GlobalModeration, actor/recipient cooldowns, uses server-observed target CFrame, reserves and completes a server ticket, rechecks characters around the mutation | Verify the new one-use movement-observer marker in Studio; audit other teleport writers |
| Stage/club lights | UtilityBar/UtilityBarExtendedActions.server.lua | Only tagged StageClubLight roots and supported Light/Beam descendants; pass-gated server action; fixed preset allowlist; bounded request token bucket and cooldown | Original-state restore can conflict with another authorized writer changing a fixture after the first snapshot; runtime writer inventory still required |
| Utility avatar clone | Utility Bar extended actions | Server creates clone from caller's current character and uses server-observed root CFrame; clone is temporary and cleaned up | Confirm intended collision/query/touch settings and cleanup under character churn |
| Kohl's global environment aliases | RegularCommandsSecurityServer.lua | time, brightness, colorshift, latitude, diffusescale, exposure, disco, gravity, and clearterrain map to SecurityCore permissions and bounded World budget | Wrapped native handler success/failure and aliases outside adapter still require testing |
| Terrain clear | Kohl's clearterrain policy | Requires GlobalConfig, global World budget, fixed-code audit | Adapter records command intent after the wrapped handler; it does not inventory or intercept every Terrain writer |

### Collision-group and protected-geometry status

- The repository files reviewed in this follow-up do not establish a complete collision-group matrix or a server-owned ClubPlayers collision assignment service. The sample collision-group script supplied in chat is a design reference, not a committed game script.
- No blanket collision-group registration or matrix mutation was added. Changing a group pair globally without inventory could break map walls, stage barriers, mounts, vehicles, doors, or other intended interactions.
- Noclip and wall-clip detection remain blocked on a live map inventory: protected geometry, collision groups, CanCollide/CanQuery policies, streaming behavior, doors, moving/temporary geometry, and legitimate pass-through mechanics must be identified first.
- The Tiki Tide Settings teleport path is now ticket-validated and movement-observer-aware, but this does not cover native Kohl's teleport, respawn/spawn placement, mount/vehicle movement, or other external CFrame/PivotTo/MoveTo writers.

### Entitlement and policy boundary reaffirmed

- Utility Bar Stage & Club Lighting checks the server-populated HasStageClubLightingPass attribute; clients do not provide a pass ID or ownership claim.
- Tiki Tide Settings privileged gravity and moderation/configuration paths use SecurityCore Authorization. The membership access attribute is populated by the main controller's verified server-side pass/rank flow; verify that flow and refresh lifecycle in the live place.
- Do not replace these with a client-owned HasVIP attribute check or a parallel role resolver.

### Backdoor / environment writer boundary

This source pass is not a full backdoor audit. It has not inspected native Kohl's Admin package internals, third-party package descendants, live-place scripts, runtime-inserted models, plugin-installed assets, or every dynamically created Instance. A full Phase 27 audit must trace script provenance and all writers to Lighting, Gravity, Terrain, Atmosphere, Clouds, post-processing, collision groups, and protected map state. Keyword matches alone are not proof of a backdoor and must not trigger automatic deletion or punishment.

### Follow-up decision

No global Lighting/Terrain watcher, collision-matrix rewrite, automatic environment restoration, or player enforcement was added. The current tracked writers have meaningful local authorization boundaries, but the missing live-place/package writer inventory prevents a safe authoritative baseline and rollback design. Continue with inventory and Studio acceptance before adding drift enforcement.

## Runtime acceptance matrix — outstanding

- [ ] Confirm the installed SecurityCore release and installer pin match the reviewed branch release.
- [ ] Test gravity defaults, supported Tiki Tide settings, Kohl's gravity command, simultaneous authorized writes, reset/default, and unauthorized attempts.
- [ ] Test each Kohl's Lighting alias and verify authorization, bounds, audit records, and failure behavior.
- [ ] Test Stage & Club Lighting with all four presets and Off; include newly tagged/removed fixtures and concurrent authorized changes.
- [ ] Verify untagged island/environment lights and global Lighting remain unchanged by the Utility Bar control.
- [ ] Test clearterrain and every legitimate map/build/cleanup operation in a disposable Studio copy; verify protected map content remains intact.
- [ ] Test VIP/VVIP/Tiki Tide membership, group member, owner, rewarded tier, and each feature pass across purchase, failed lookup, refresh, leave/rejoin, and cache expiry.
- [ ] Verify unauthorized clients cannot set feature attributes, invoke server-only controls, or bypass the SecurityCore permission path.
- [ ] Measure observer CPU/memory and ensure telemetry does not alter world state or starve essential authorization/purchase/moderation work.

## Exit criteria

Phase 27 is not complete until the live place and external package writers are inventoried, every legitimate world/environment mutation path is mapped to its existing server authorization owner, entitlement lifecycle tests pass, and Studio plus published-server tests demonstrate no false-positive enforcement or unintended environment changes. Any future drift monitor must remain detection-only until separately reviewed.

**Current Phase 27 status:** initial tracked-source audit complete; implementation of drift monitoring intentionally deferred pending live writer inventory and runtime acceptance. Phase 26 remains separately open for its own runtime movement validation. Phases 28–39 and Phase 40 cleanup are not changed by this document.

## Follow-up review — collision groups, shared physics props, lighting requests, and VIP zone example (2026-11-17)

### Collision-group assignment

- The supplied Players collision-group example is not present as a tracked implementation. The reviewed source paths do not establish a complete collision-group matrix or a first-party server-owned character collision assignment service.
- No new group registration, collision matrix mutation, or blanket assignment of character descendants was added. A global player/player collision change could affect intended interactions with map barriers, stage fixtures, accessories, tools, mounts, and vehicles.
- Before implementation, inventory all groups and pairwise collidability from the live place, all scripts assigning BasePart.CollisionGroup, and the intended behavior of character body parts, accessories, tools, mounts, vehicles, doors, and protected map geometry. Then define one server-owned assignment owner with existing-group-safe initialization, existing-player handling, respawn handling, and connection cleanup.
- Collision groups are not a substitute for protected-geometry auditing or noclip detection. CanCollide/CanQuery, spatial query filters, streaming, moving barriers, and legitimate pass-through mechanics must also be mapped.

### Shared unanchored physics props

- The supplied InteractiveProps / SetNetworkOwner(nil) example is not present as a tracked policy. CharacterPhysicsGuard observes the character root's network owner; that does not establish ownership policy for world props.
- Do not force server ownership on all unanchored objects. Inventory actual shared props and their scripts first; keep characters, mounts, and vehicles on separately reviewed ownership policies. Server ownership can increase physics workload or reduce responsiveness.
- Any future prop policy must be scoped to a verified folder/tag and eligible assemblies, handle late descendants and reparenting, record bounded failures, and be tested under server load.

### Stage lighting request boundary

- The supplied arbitrary color-name RemoteEvent and direct StageLights.NeonPart.Color mutation are not adopted. The existing Utility Bar lighting service remains the only reviewed first-party Stage & Club Lighting owner: it requires the server-populated feature-pass attribute, validates a bounded request, enforces a server-wide budget and per-player cooldown, and applies fixed presets only to Light/Beam descendants under StageClubLight tagged roots.
- Do not add a second pass lookup, arbitrary color remote, or direct fixture writer. Continue auditing for non-UtilityBar writers and test concurrent preset/restore operations, including a fixture changed by another authorized writer after the original snapshot.

### Physical VIP zone boundary

- Phase 6's tracked-source audit found no dedicated physical VIP/VVIP/Tiki Tide zone detector or touch-handler implementation. The current branch's TeleportValidationService includes VIPZone in its accepted origin-name allowlist, but no corresponding first-party caller was established by the tracked source review. An allowed origin string is not proof that a VIP zone exists or that a caller is authorized.
- Membership remains centralized in EntitlementAuthority; do not add a separate UserOwnsGamePassAsync loop, client-owned VIP flag, or duplicate pass resolver.
- If a physical protected zone exists in the live place, inventory its actual geometry, query/collision settings, all entrances and alternate routes, and the intended membership tiers. Each server entry path must use the existing entitlement authority and staff authorization policy, validate a live character/root and the actual boundary, and fail safely on unknown entitlement results without treating a Marketplace outage as exploit evidence.
- Any corrective movement must use the existing server-owned TeleportValidationService ticket flow after authorization, with a validated public destination and character identity checks. Do not directly assign a root CFrame from a zone scan. Do not eject, kick, or ban based on a single overlap or failed lookup.
- Runtime tests must cover group VIP, paid VIP/VVIP/Tiki Tide, owner-awarded tiers, owner access, non-members, first-time lookup failure, transient failure after verified ownership, respawn, boundary edges, overlapping body parts, multiple zone parts, and bypass routes.

### Implementation decision

No collision matrix, server-owned prop policy, arbitrary lighting remote, VIP-zone detector, separate entitlement checker, or direct-CFrame ejection was added. The live map and packaged scripts are still required to establish whether these systems exist and what safe boundaries they should enforce.

 
## Follow-up implementation — conflict-aware Stage & Club Lighting restoration (2026-11-17)

Updated `UtilityBar/UtilityBarExtendedActions.server.lua` so the existing scoped preset system no longer blindly restores stale snapshots over a fixture another authorized system changed while a preset was active.

- Each affected Light retains its original state and the last values applied by the preset controller.
- Each affected Beam retains its original ColorSequence and the last ColorSequence applied by the preset controller.
- When another preset is applied, a fixture that diverged from the controller's last-applied state gets a refreshed restore baseline before the new preset is applied.
- When Off is requested, only fixtures that still match the controller's last-applied state are restored. Diverged fixtures are preserved, and the response reports how many were restored versus preserved.
- Snapshot entries are cleared after Off processing so a later preset captures a fresh baseline.
- The existing StageClubLight tag scope, fixed preset allowlist, pass gate, ingress budget, and cooldown remain unchanged. No new RemoteEvent or entitlement checker was added.

Static source verification is required after this update; Roblox Studio tests remain outstanding for repeated preset changes, external fixture mutation between presets, Off after external mutation, newly tagged fixtures, and concurrent requests. This is not a substitute for auditing all other fixture writers.
