# Phase 26 — Server-Authoritative Movement Envelope

**Status:** Source inventory, bounded passive displacement measurement, and one-use verified-teleport sampling integration committed. No anomaly thresholds, path enforcement, correction, or punishment is enabled. Live movement-source inventory, representative runtime measurements, and acceptance remain open.

**Branch:** `fix/security-core-release-and-queue-loop`

## Safety boundary

Phase 26 is measurement-first. The current observer is detection-only and remains so. A client-reported physics value, a single velocity spike, a property-change signal, or a missing authorization marker is not proof of exploitation. Do not kick, ban, freeze, anchor, teleport, correct, or otherwise restrict a player based on movement telemetry.

Do not add displacement/path thresholds until legitimate movement sources have been measured in the actual experience under representative latency, device, character, and network-ownership conditions.

## Existing architecture to preserve

- `ClubMusicSecurityCore/MovementAuthority.lua` is the existing server-local approval ledger. It is not a permission system; each caller must complete SecurityCore authorization and any entitlement/consent checks before applying a change.
- `ClubMusicSecurityCore/CharacterPhysicsGuard.lua` is the existing detection-only observer. It watches Humanoid WalkSpeed, JumpPower, JumpHeight, R15 body scale, Workspace.Gravity, and coarse extreme root assembly linear/angular velocity. It coalesces property changes, waits a bounded interval for character parts, rate-suppresses repeated signals, and never changes gameplay state.
- `ClubMusicSecurityCore/TeleportValidationService.lua` issues short-lived server-only tickets and verifies the server-observed destination. The service trusts its server-script callers to authorize before Begin.
- `ClubMusic_Security_Core_Installer.lua` installs/starts the existing modules and exposes local status through ServerStorage. Keep the installer and standalone module sources aligned when implementation changes are later justified.
- Do not create another movement authority, permission system, remote, profile store, or persistent movement ledger.

## Source inventory — confirmed in the tracked branch

| Movement source | Current server owner / behavior | Current authorization or observation | Phase 26 gap |
|---|---|---|---|
| Default walking/jumping | Roblox Humanoid / character physics | CharacterPhysicsGuard observes property changes and coarse extreme velocity | Need baseline movement measurements under normal play and latency |
| Tiki Tide speed/jump settings | `TikiTideSettingsService.server.lua` | Tiki Tide entitlement check; server applies WalkSpeed 20–100 and JumpPower 80–300; registers MovementAuthority values | Verify UseJumpPower, JumpHeight interaction, respawn, entitlement revoke, and live character defaults |
| Utility Bar Size | `UtilityBar/UtilityBarExtendedActions.server.lua` | Server validates 0.5×–5× R15 scale and applies scale values; registers BodyScale | Measure movement/rig effects at endpoints and intermediate factors; R6 is unsupported |
| World gravity | Tiki Tide Settings and Kohl's adapter | GlobalConfig authorization; Tiki Tide setting clamps 20–192.62; CharacterPhysicsGuard observes Workspace.Gravity; MovementAuthority marker | Audit every real writer and test simultaneous changes, startup, reset, and third-party scripts |
| Kohl's speed/jump/size | `RegularCommandsSecurityServer.lua` adapter wraps native command handlers | SecurityCore permission filter; MovementAuthority markers are registered after native handler return | Native handler internals are not in this repository snapshot; marker may be recorded even when native handler fails; verify alias-by-alias |
| Kohl's flight/freeze/fling | Same adapter; native Kohl's handlers | SecurityCore permission filter; Flight/Frozen/Fling markers exist, but CharacterPhysicsGuard does not consume Flight/Frozen markers; Fling has a short marker | Inspect native physics implementation and success/failure return behavior; do not infer observer coverage from marker presence |
| Tiki Tide player teleport | Tiki Tide Settings server action | Server-derived target transform, consent/SecurityCore exception, cooldowns, Begin/Complete ticket | Existing ticket is for this call path; test respawn/departure/races and movement observer interaction |
| Other teleport origins | TeleportValidationService allowlist includes Kohl's Admin, VIPZone, SpawnPad, GameTeleport | Service checks origin string and ticket; caller is responsible for authorization | No matching caller implementation was found in tracked text-source inventory; inspect live place and external packages before trusting these origins |
| Utility Bar Mount | Utility Bar server action equips/unequips an existing mount Tool | Pass entitlement is server-verified by controller attributes | Tool's physics/controller source is not present in this repository snapshot; mount movement is unmeasured |
| Vehicles | No first-party vehicle controller found in tracked movement-related text paths | Unknown | Identify actual live vehicle models/scripts, ownership changes, seats, constraints, and server controls |
| Knockback / launch pads | No first-party knockback or launch-pad implementation found in tracked movement-related text paths | Unknown | Inspect live place, packages, and map scripts; identify impulse writers and their legitimate force/time envelopes |
| Respawn / character replacement | Roblox character lifecycle; CharacterPhysicsGuard attaches per CharacterAdded | Bounded Humanoid and HumanoidRootPart waits, lifecycle rechecks, connection cleanup | Measure spawn protection, assembly delay, reset, death, custom rigs, and stale character transitions |
| Network ownership / latency | Roblox physics replication | No dedicated ownership/latency envelope in CharacterPhysicsGuard | Measure server-observed ownership changes, ping/jitter buckets, packet delay, and client/server transform divergence without trusting client reports |

## What Phase 26 must measure before thresholds are considered

1. **Movement profiles:** default and Tiki Tide speed/jump settings, including minimum/maximum values, UseJumpPower, JumpHeight, and all supported rig types.
2. **Scale:** R15 0.5×, 1×, 5× and representative intermediate sizes; record changes to acceleration, collision, floor contact, jump arc, and assembly stability.
3. **World settings:** gravity values at supported limits, change timing, simultaneous updates, and restoration.
4. **Mounts and vehicles:** each actual approved tool/model, seat/constraint behavior, server/client network ownership, speed/acceleration/turning envelope, dismount, destruction, and respawn.
5. **Impulses:** every approved knockback, launch pad, fling-like staff action, collision impulse, and scripted force; record magnitude, duration, direction, and affected assembly.
6. **Teleport and respawn:** ticketed teleports, spawn/respawn transitions, map transitions, authorized admin movement, and any server-side CFrame/PivotTo/MoveTo writers.
7. **Network conditions:** representative ping and jitter bands, ownership handoffs, seated states, packet delay, and server frame/heartbeat load.
8. **Normal movement:** walking, sprinting if present, jumping, falling, slopes, stairs, swimming, collisions, ragdolls if present, and moving platforms.

## Expanded movement-protection scope — required, not yet implemented

The Phase 26 target includes the following distinct detection and prevention capabilities. Listing them here does not mean they are implemented or certified. The current CharacterPhysicsGuard remains a passive measurement/observation component; automatic correction and enforcement remain disabled.

| Capability | Required server-observed approach | Preconditions and safety limits |
|---|---|---|
| Noclip detection | Detect sustained traversal through collidable geometry using bounded swept-character-volume or equivalent server-side spatial checks, with continuity across samples. | Must account for doors, moving/temporary geometry, collision groups, legitimate teleports, spawn transitions, seats, vehicles, and map-specific pass-through mechanics. A ray through one wall is not proof. |
| Wall-clip detection | Detect unauthorized penetration/crossing of protected walls, barriers, and map boundaries; distinguish transient collision resolution from sustained traversal. | Requires an audited protected-geometry/map policy and live collision-group inventory. Do not assume every visible wall is intended to block every character or vehicle. |
| Vertical anomaly detection | Track vertical displacement/velocity and sustained upward/downward movement over a time window, with grounded/airborne state and authorized impulse/gravity context. | Must model jumps, falls, swimming, slopes, launch pads, knockback, seats, mounts, vehicles, elevators, moving platforms, and teleport/respawn transitions. |
| Fly detection | Identify sustained unsupported airborne movement or hovering patterns across multiple valid samples, rather than a single airborne or velocity sample. | Must distinguish normal jump arcs, falling, swimming, ragdolls, flight/freeze staff tools, vehicles, moving platforms, network ownership handoffs, and latency. |
| Horizontal speed detection | Measure horizontal displacement separately from vertical displacement over bounded, continuous server-observed sample windows. | Thresholds require measured envelopes for default/Tiki Tide WalkSpeed, size scaling, mounts/vehicles, impulses, collisions, slopes, latency, and server load. |
| Horizontal speed clamping | If later approved, constrain only validated unauthorized horizontal excess through a narrowly scoped server-owned correction path. | Disabled until detection has demonstrated acceptable false-positive rates and recovery has been tested. Never clamp from client-reported WalkSpeed/velocity or one sample; preserve vertical velocity and legitimate impulses where appropriate. |
| Safe correction/recovery | After a separately reviewed approval, restore a player to a verified safe state or limit only the unauthorized component of motion. | No anchoring, freezing, teleport-back, or punishment based solely on one signal. Respect existing SecurityCore authority and do not create a second permission system. |

### Measurement requirements for these capabilities

- Extend the existing aggregate measurement design only after its CPU/memory cost and sampling accuracy are verified. Record separate coarse horizontal and vertical displacement/speed bands; do not retain raw position paths or unbounded per-player histories.
- Any future collision/path observer must use bounded spatial queries and bounded per-sample work. It must verify character identity continuity and handle missing parts, large sample gaps, streaming/collision changes, and moving geometry as unknown rather than exploit evidence.
- Build a server-owned inventory of protected geometry, collision groups, legitimate pass-through regions, and authorized movement sources before treating wall intersections as violations.
- Evaluate fly behavior over multiple consecutive valid samples and movement context. Airborne state alone is never a fly verdict.
- Treat detection, correction, clamping, and punishment as separate rollout gates. Phase 26's current implementation has not passed any of these new capability gates.

## Bounded observation design constraints

- Prefer server-observed samples and server-owned action markers. Client telemetry may be contextual only and must never establish authorization or proof.
- Any future sampler must have fixed per-player sample frequency, bounded active-player state, bounded history/ring buffers, bounded signal cardinality, and deterministic cleanup on PlayerRemoving/CharacterRemoving.
- Use short-lived, explicit server-side movement grants for known impulses/teleports only after their real caller and authorization path are verified. Grants must be target-scoped, origin-scoped, property/action-scoped, expiring, single-purpose where feasible, and consumed/cleared safely.
- Separate expected movement context (mount/seat/vehicle, knockback, launch, teleport, respawn, ownership handoff) from anomaly scoring. Missing context is “unknown,” not proof.
- Do not use one velocity sample as a verdict. If displacement/path observation is later added, require a time window, server-observed positions, bounded sample gaps, character identity continuity, movement context, and latency-aware uncertainty.
- Record fixed signal codes and coarse numeric bands only. Do not log raw client payloads, arbitrary instance paths, chat, secrets, or unbounded position histories.
- Keep diagnostics server-local. Do not create a cross-server movement history or durable per-frame telemetry.

## Implementation decisions from this source pass

- No new displacement/path sampler was added: the tracked source inventory does not yet establish reliable legitimate movement envelopes for mounts, vehicles, knockback, launch pads, network ownership, or latency.
- Noclip, wall-clip, vertical/fly, and horizontal-speed detectors/clamping were not added in this pass. The tracked inventory and runtime measurements are insufficient to set safe spatial or movement thresholds; the expanded scope above is a requirement, not an implementation claim.
- No velocity threshold was tightened. Existing 300 linear / 120 angular thresholds remain coarse, detection-only indicators; seated characters are currently excluded from that check.
- No new MovementAuthority property or generic “movement allowed” bypass was added.
- Existing movement settings, Utility Bar Size, teleport ticket contract, Kohl's adapter, SecurityCore permissions, and installer architecture remain unchanged.
- The live Roblox place, packaged binary assets, and external Kohl's Admin internals are not represented completely by this text-source audit. Their absence from the repository tree is not proof that the corresponding gameplay systems do not exist.

## Bounded passive measurement now implemented

- CharacterPhysicsGuard samples the server-observed HumanoidRootPart position every 0.5 seconds while the same player/character/root remain live.
- Samples are accepted only when the elapsed interval is 0.2–1.5 seconds; invalid coordinates and timing gaps are counted separately.
- The observer computes displacement divided by elapsed time and increments fixed aggregate speed bands. It also records fixed context buckets (grounded/airborne/seated/other), network-owner buckets (server/client/unknown), and server-observed latency buckets.
- The observer now bins total displacement speed, horizontal X/Z speed, and absolute vertical Y speed separately. All are coarse aggregate counters; they are not thresholds, exploit verdicts, or clamp inputs.
- Only the immediately previous position/time is retained per active character. No position history, path, per-player movement record, persistent storage, cross-server telemetry, or client-supplied physics value is retained.
- These bands are measurement bins, not movement limits or exploit verdicts. They do not emit anomaly signals and cannot change gameplay. The existing coarse velocity observer remains detection-only and unchanged.
- The installer release pin now points to the commit containing the updated CharacterPhysicsGuard source. The module remains server-only.

## Verified teleport integration — passive only

- `TeleportValidationService.Complete` now records a short-lived (2.5-second), target-character-scoped marker only after the existing ticket has been consumed and the server-observed destination has passed verification.
- `CharacterPhysicsGuard` consumes that marker once, resets its previous-position/time baseline to the server-observed post-teleport position, and increments an aggregate `authorizedTeleportSamples` counter. This prevents the verified Tiki Tide Settings CFrame teleport from polluting ordinary displacement-speed measurements.
- The marker is server-only, character-identity checked, expiring, one-use, and cleaned up on PlayerRemoving. It does not create a client exemption, authorize a teleport, skip property/velocity observation, or alter character physics.
- The Security Core installer release pin is updated to the exact commit containing both module changes.
- This integration covers the tracked Tiki Tide Settings teleport path that calls Begin → server CFrame assignment → Complete. It does not automatically cover native Kohl's teleport commands, spawn transitions, mounts, vehicles, or other untracked CFrame/PivotTo/MoveTo writers.
- This is not CFrame rollback or horizontal speed correction. Safe recovery CFrames, collision-safe destination validation, sustained anomaly detection, and clamping remain unimplemented and disabled.

## Runtime measurement and acceptance matrix — outstanding

- [ ] Collect baseline traces for normal players on PC, mobile, and console; default and Tiki Tide movement profiles; R6/R15/custom rigs; low/medium/high latency; and normal server load.
- [ ] Exercise Utility Bar scale endpoints and intermediate values, respawn, entitlement revoke, and character replacement.
- [ ] Test every actual mount/vehicle and every knockback/launch/impulse source.
- [ ] Test teleport ticket success, expiry, replay, destination mismatch, actor/target departure, respawn during action, and external teleport origins; verify exactly one movement sample is exempted only after successful Complete.
- [ ] Test network ownership changes, seats, moving platforms, collisions, swimming, slopes, stairs, and large but legitimate impulses.
- [ ] Validate vertical and horizontal displacement measurements independently across grounded, airborne, seated, swimming, falling, and moving-platform contexts.
- [ ] Build disposable-map tests for noclip and wall-clip detection: intended solid walls, collision groups, doors, moving barriers, pass-through zones, respawns, and authorized teleports; measure false positives and missed detections.
- [ ] Test fly-detection candidates over sustained multi-sample windows, including legitimate jumps/falls, launch/knockback, mounts/vehicles, staff flight/freeze tools, and latency/ownership handoffs.
- [ ] Validate horizontal speed detection against every approved movement source and size factor; do not set a clamp threshold until representative baseline traces are accepted.
- [ ] In a separate disposable test, exercise any proposed horizontal clamp under normal movement, impulses, collisions, latency, respawn, and mount/vehicle transitions; verify vertical velocity and legitimate movement are not unintentionally suppressed. Keep the clamp disabled unless separately approved.
- [ ] Measure false-positive rates before defining any displacement/path anomaly threshold. Document sample counts, time windows, device/network conditions, and confidence limits.
- [ ] Verify bounded memory/CPU cost and cleanup under player churn and burst events.
- [ ] Confirm telemetry never changes gameplay and all SecurityCore/entitlement checks remain authoritative.

## Exit criteria

Phase 26 is not complete until the live movement sources are inventoried, legitimate movement envelopes are measured, reliable server-observed path/displacement signals are demonstrated with acceptable false-positive rates, and Studio plus published-server tests prove safe recovery. Correction and enforcement remain disabled unless a later explicit design review authorizes them.

**Current Phase 26 status:** source inventory, separate aggregate horizontal/vertical displacement-speed measurement, and one-use verified-teleport sampling integration committed. Noclip/wall-clip geometry validation, sustained fly analysis, thresholds, safe CFrame recovery, horizontal correction/clamping, runtime measurement, and live hierarchy/package inspection remain open. Phase 25 remains separately recorded. Phases 27–39 and Phase 40 cleanup are not changed by this document.

## Follow-up review — scale and physics network ownership examples (2026-11-17)

### Character scale policy

- The supplied fixed 0.85×–1.15× clamp is not compatible with Tiki Tide's existing Utility Bar feature and is not adopted.
- The tracked Utility Bar server action accepts finite numeric scale factors from 0.5× through 5×, applies them to the caller's own R15 scale values, and registers the resulting BodyScale factor with the existing MovementAuthority ledger. It does not support R6 scaling.
- CharacterPhysicsGuard observes the four R15 scale values, compares their relative factor with the captured baseline, checks for inconsistent component scaling and broad sanity bounds (0.1×–10×), and consults MovementAuthority. It records bounded signals only; it does not clamp or rewrite scale values.
- The observer's broad sanity bounds are not the Utility Bar entitlement/range policy. Preserve the 0.5×–5× Utility Bar contract. Do not add a second Changed-handler that races the legitimate scale service.
- Remaining tests: exact 0.5×, 1×, intermediate, and 5× values; reset to captured baseline; respawn; character replacement; entitlement revoke; concurrent requests; R15 avatar scale defaults and unsupported R6/custom rigs.

### Network ownership inventory

- CharacterPhysicsGuard calls GetNetworkOwner on the observed HumanoidRootPart and aggregates server/client/unknown ownership buckets together with server-observed ping buckets. This is measurement only.
- The reviewed first-party movement, Utility Bar, Tiki Tide Settings, and Kohl's adapter sources did not establish a server-owned InteractiveProps folder policy or a SetNetworkOwner(nil) enforcement service.
- The supplied InteractiveProps example is therefore a design reference, not an existing Tiki Tide implementation. No blanket network-ownership override was added.
- Before adding a policy, identify actual shared unanchored props and their scripts, constraints, touch/query behavior, ownership eligibility, and gameplay responsiveness requirements. Explicitly exclude player characters and evaluate mounts/vehicles separately. Apply server ownership only to designated shared objects when the server load and interaction latency are acceptable.
- Runtime acceptance must cover ownership handoffs, player churn, newly inserted descendants, destroyed/reparented props, ineligible assemblies, and server physics cost. A failed SetNetworkOwner call must not silently become an assumed server-owned state.

### Implementation decision

No fixed scale clamp, standalone network-owner loop, or automatic movement correction was added. Existing Utility Bar scale authority, MovementAuthority, and passive CharacterPhysicsGuard observation remain the only tracked first-party paths.


## Follow-up source audit and implementation — mount, companion, Tool, and accessory state (2026-11-17)

### Tracked source findings

- The Utility Bar Mount action is server-side and checks the server-populated `HasIslandMountPass` attribute. It only equips/unequips an existing Tool found in the caller's Character or Backpack when `UtilityMount=true` or its name is `Mount` / `MountTool`. It does not grant the Tool and does not verify its original asset source or grant provenance.
- The companion action clones the caller's current character on the server, removes Script/LocalScript descendants from the clone, disables collision/touch/query on clone BaseParts, makes them massless, anchors the clone root, follows the owner for 12 seconds, and destroys the clone on expiry or PlayerRemoving. This is a temporary visual clone, not a persistent Tool or entitlement grant.
- Tool Shop remains an empty placeholder: the server RemoteFunction only supports `GetShop` and returns an empty `items` array. There is no tracked purchase/grant/equip implementation in ToolShop.
- Avatar refresh is server-owned: the server fetches the caller's own HumanoidDescription, rechecks character identity after the asynchronous lookup, and applies the description. It accepts no client target or description.
- The tracked repository tree contains no separately named vehicle/mount controller script. No first-party vehicle seat/vehicle control or shared-vehicle network-owner policy was established in the inspected Utility Bar, controller, SecurityCore, or Kohl's adapter sources. The live place and third-party package descendants may contain additional systems.
- CharacterPhysicsGuard's network-owner telemetry is limited to the observed HumanoidRootPart and is aggregate observation only. It does not establish network ownership for a mount, vehicle, or world prop.

### Detection-only inventory observer update

Updated `ClubMusicSecurityCore/AvatarAccessoryValidationService.lua`, which the main controller already requires and starts:

- Tracks server-visible Tool inventory changes in the player's Backpack, Character, and StarterGear.
- Emits bounded signals for Tools added after appearance initialization and Tools removed from the player's tracked inventory. A Tool moved between Backpack and Character is checked after the parent transition settles, so ordinary equip/unequip transfer is not treated as a removal.
- Bounds tracked Tool instances per player at 100 and accessory handle observers per character at 50; per-signal cooldown and existing bounded service state remain in place.
- Signals Accessory additions/removals after appearance initialization and changes to an observed Handle's Size or CanCollide state. Existing description asset-ID, duplicate-ID, accessory count, Handle size/collision, and excessive-descendant checks remain.
- The observer does not label a Tool as definitively unauthorized: a legitimate server grant may also appear after appearance initialization. It records the change for review; it never strips, destroys, disables, or re-equips a player's Tool or Accessory.
- The main controller now calls the observer's `Stop()` during script destruction. PlayerRemoving and character teardown continue to disconnect per-player/per-character observers.
- The Security Core installer release pin now targets the exact commit containing the updated observer. A tree comparison confirmed the other 23 SecurityCore module blobs match the previous installer release; only AvatarAccessoryValidationService changed in that pinned source commit.

### What this does not prove

- Server-visible inventory observation does not prove the origin or approval of a Tool. The current mount action has no provenance registry; Kohl's grant commands remain separate privileged entry paths. No generic grant API or parallel permission authority was introduced.
- The observer does not inspect every Tool descendant's executable code, verify all Tool asset IDs against an allowlist, or certify third-party scripts. Those require a complete live hierarchy and asset provenance audit.
- No vehicle or mount network-owner policy was added. Do not call SetNetworkOwner(nil) on all unanchored parts or character assemblies; first identify actual vehicle/mount assemblies, constraints, drivers, and responsiveness requirements.
- R6 rigs do not expose the same four NumberValue body-scale values used by the existing R15 scale observer. The Utility Bar scale action is R15-only. R6, R15, and custom-rig behavior must be tested separately rather than forcing an R15 scale policy onto R6.

### Runtime acceptance matrix — outstanding

- [ ] Confirm server observer signals for a new Tool granted into Backpack, Character, and StarterGear after appearance initialization.
- [ ] Confirm ordinary Backpack ↔ Character equip/unequip transfers do not emit false Tool-removal signals.
- [ ] Test authorized `give`, `startergive`, `starterremove`, `copytools`, `gear`, `btools`, and `insert` commands; correlate actor, target, resulting Tool, and audit entry. Also test denied actors and malformed targets.
- [ ] Verify Tool persistence and cleanup through death, respawn, Backpack replacement, StarterGear changes, player departure, and controller teardown.
- [ ] Test legitimate avatar refresh and appearance reload; record expected accessory add/remove signals and ensure no automatic stripping occurs.
- [ ] Mutate an existing Accessory Handle's Size and CanCollide values; verify one bounded observation per signal cooldown and no automatic correction.
- [ ] Test accessories and Tools on R6, R15, and custom rigs, including missing/atypical Handles and equipped Tools.
- [ ] Verify the actual Mount Tool asset, source container, scripts, grant path, pass gate, and server equip/unequip behavior in Studio.
- [ ] Inventory every actual vehicle/mount, VehicleSeat/Seat, constraint, driver controller, network owner transition, and cleanup path in the live place.
- [ ] Inspect the complete installed Kohl's Admin and F3X/Building Tools package descendants, including SyncAPI server handlers, ModuleScript provenance, numeric asset requires, and runtime asset insertion. The 7.4 MB tracked Kohl's Admin model export could not be fully inspected through the available repository reader; the presence of a hardening patch script is not proof it was applied.
- [ ] Confirm the observer's bounded memory/connection cleanup over repeated respawns, Backpack replacement, player churn, and controller teardown.

**Current status:** tracked first-party mount/companion/Tool Shop/avatar-refresh paths reviewed; Tool and Accessory inventory observation extended as detection-only; installer pin and controller teardown updated. Server grant provenance, native third-party package internals, actual vehicles/mount assets, R6/R15/custom runtime behavior, and all Studio/published-server acceptance remain open. No automatic asset removal or movement enforcement was enabled.
