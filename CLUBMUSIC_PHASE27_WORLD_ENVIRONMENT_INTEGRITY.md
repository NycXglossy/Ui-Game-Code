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
