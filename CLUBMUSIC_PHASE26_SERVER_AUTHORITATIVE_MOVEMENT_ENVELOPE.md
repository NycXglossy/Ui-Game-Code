# Phase 26 — Server-Authoritative Movement Envelope

**Status:** Source inventory and bounded passive displacement measurement committed. No anomaly thresholds, path enforcement, correction, or punishment is enabled. Live movement-source inventory, representative runtime measurements, and acceptance remain open.

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
- Only the immediately previous position/time is retained per active character. No position history, path, per-player movement record, persistent storage, cross-server telemetry, or client-supplied physics value is retained.
- These bands are measurement bins, not movement limits or exploit verdicts. They do not emit anomaly signals and cannot change gameplay. The existing coarse velocity observer remains detection-only and unchanged.
- The installer release pin now points to the commit containing the updated CharacterPhysicsGuard source. The module remains server-only.

## Runtime measurement and acceptance matrix — outstanding

- [ ] Collect baseline traces for normal players on PC, mobile, and console; default and Tiki Tide movement profiles; R6/R15/custom rigs; low/medium/high latency; and normal server load.
- [ ] Exercise Utility Bar scale endpoints and intermediate values, respawn, entitlement revoke, and character replacement.
- [ ] Test every actual mount/vehicle and every knockback/launch/impulse source.
- [ ] Test teleport ticket success, expiry, replay, destination mismatch, actor/target departure, respawn during action, and external teleport origins.
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

**Current Phase 26 status:** source inventory committed; runtime measurement, live hierarchy/package inspection, and reliable displacement/path design remain open. Phase 25 remains separately recorded. Phases 27–39 and Phase 40 cleanup are not changed by this document.
