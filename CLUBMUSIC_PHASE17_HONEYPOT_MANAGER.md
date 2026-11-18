# Phase 17 — Honeypot Manager

**Status:** Source implementation committed; Studio/published-server acceptance remains open. The current implementation provides eight isolated decoy remotes for detection and review. It does not replace real remotes, authorization, SecurityMonitor, SecurityReplayService, SecurityThreatIntelligence, or the separate moderation authority.

## Implementation

- Added `ClubMusicSecurityCore/HoneypotManager.lua`, staged by the SecurityCore installer.
- The installer pins SecurityCore modules to `5b9d772d6320e8c0c3605bd49d1ff3e6da0c6dcf`. The pinned HoneypotManager source was checked and contains all eight decoys listed below.
- Creates a dedicated `ReplicatedStorage/TikiTideSecurityDecoys` folder containing eight isolated decoys:

| Decoy | Class | Fixed signal |
|---|---|---|
| `TTHP_AdminPrivilegeEvent` | RemoteEvent | `honeypot_admin_privilege_remote` |
| `TTHP_PurchaseReceiptFunction` | RemoteFunction | `honeypot_purchase_receipt_remote` |
| `TTHP_VIPEntitlementEvent` | RemoteEvent | `honeypot_vip_entitlement_remote` |
| `TTHP_ModerationActionFunction` | RemoteFunction | `honeypot_moderation_action_remote` |
| `AdminCommandEvent` | RemoteEvent | `honeypot_admin_command_event` |
| `UnlockAllGear` | RemoteEvent | `honeypot_unlock_all_gear_event` |
| `SetVIPRank` | RemoteEvent | `honeypot_set_vip_rank_event` |
| `GiveTipMoney` | RemoteEvent | `honeypot_give_tip_money_event` |

- The four additional RemoteEvents above implement the first supplied Phase 17 suggestion. They remain inside the dedicated `TikiTideSecurityDecoys` folder; the manager does not create or replace objects inside the live `ReplicatedStorage.Remotes` folder.
- Decoys do not grant privileges, unlock gear, modify VIP entitlements, issue money, process purchases, or perform moderation actions.
- RemoteFunction decoys return a neutral unavailable response. RemoteEvent decoys perform no gameplay action.
- Each accepted hit records a fixed signal code to the existing server-local threat-intelligence and replay services. No client payload, argument, text, or arbitrary instance data is retained.
- Per-player hit cooldown is five seconds; tracked subject state is capped at 256. Aggregate counters are bounded. Player-removal cleanup is connected.
- Adds server-only `ServerStorage.GetTikiTideHoneypotStatus` and includes its state/counters in the existing unified diagnostics and staff `;cmdiagnostics` output.
- Status reports eight decoys: six RemoteEvents and two RemoteFunctions.
- Installer shutdown stops the manager and destroys its dedicated decoy folder. A pre-existing folder is never overwritten; startup fails closed for the honeypot service only.
- No DataStore, MemoryStore, MessagingService, client-to-server diagnostics channel, enforcement action, or gameplay change is added.

## VIP-zone suggestion — deferred pending live-place audit

The supplied `VIPHoneypotZone.Touched` sample is an access-control detector, not a decoy remote. It is not added to Phase 17 because the audited repository does not identify the actual VIP zone part(s), room geometry, collision/query configuration, entrances, alternate routes, or safe return destination.

- Reuse `ClubMusicSecurityCore/EntitlementAuthority.lua` as the sole server-side membership resolver; do not introduce a second `authorizedVIPs` table or manually grant access in a separate script.
- Preserve the existing membership rules: group `500470662`, VIP/VVIP/Tiki Tide passes, owner-awarded tier, and owner access.
- An unavailable or unknown Marketplace lookup is not proof of unauthorized access or exploitation.
- Any future physical-zone denial must use the actual audited boundary and the existing `TeleportValidationService` ticket flow with a validated destination. Do not directly assign a hardcoded CFrame, and do not kick or ban based on a single touch.
- Before implementation, inspect the live place for all entry paths and test multi-part characters, boundary edges, overlapping zones, respawns, and legitimate VIP/VVIP/Tiki Tide/owner-awarded access.

## Ban and punishment suggestion — kept outside Phase 17

The supplied `RegisterViolation` / `Players:BanAsync()` sample is not added to HoneypotManager. A honeypot hit is suspicious telemetry, not verified proof; it must not automatically kick, ban, or trigger alt-account propagation.

The repository already has a separate Phase 32 `ModerationPunishmentService.lua` and staff-authorized moderation workflow for persistent warnings, restrictions, temporary/permanent bans, reversals, bounded evidence, and Roblox native ban APIs. Any future moderation action must go through that authority and its existing permission, evidence-persistence, and review requirements. Phase 17 does not create a second violation counter or enforcement path.

## Evidence and response boundaries

- A decoy interaction is suspicious telemetry, not proof of cheating. It may be caused by a copied script, a test, or an unintended interaction.
- A single decoy hit does not trigger a kick, ban, shadow restriction, movement correction, or automatic IncidentResponse case.
- ThreatIntelligence still requires independent categories/codes before creating a review item. Honeypot-only signals do not bypass that correlation threshold.
- The service is local to each server. It does not share player hit history across servers.
- Decoys are visible in ReplicatedStorage and are not secrets. Their purpose is to detect interaction by scripts that enumerate or probe unexpected remote objects, not to make an exploiter unable to discover them.

## Runtime acceptance still required

1. Run installer in a disposable Studio test place; verify module staging, pinned source, promotion, rollback, and shutdown cleanup.
2. Verify the dedicated folder contains exactly eight expected objects: six RemoteEvents and two RemoteFunctions; verify no object in the live `ReplicatedStorage.Remotes` folder was replaced, renamed, or modified.
3. Invoke all eight decoys from a test client; verify each fixed signal, server-local replay entry, and threat-intelligence signal are recorded.
4. Verify RemoteFunction calls return the neutral response and RemoteEvent calls have no gameplay effect.
5. Verify repeated hits inside the five-second window are suppressed, subject tracking remains capped, and PlayerRemoving clears subject state.
6. Verify an isolated hit does not create a threat review item or enforcement action; verify correlation still requires independent categories/codes.
7. Verify wrong-class folder collisions do not overwrite existing objects and optional honeypot failure does not block ClubMusic startup.
8. Verify the status endpoint is ServerStorage-only and staff diagnostics show bounded counters without client payloads.
9. Profile burst traffic and run playback, queue, global playback-only sync, purchases, moderation, Utility Bar, Settings, spectator, and diagnostics regressions in Studio and published servers.
10. For any later VIP-zone work, complete the separate live-place geometry and entitlement audit described above before adding a zone handler.
11. Confirm all punishment remains routed through the existing Phase 32 authorized moderation workflow; honeypot signals alone must never invoke `BanAsync`, `UnbanAsync`, or `Player:Kick()`.

**Exit criteria:** no real remote contract changes, bounded detection overhead/state, no automatic enforcement, accurate local diagnostics, installer rollback/cleanup, and successful Studio/published-server testing. VIP-zone physical enforcement is explicitly outside this phase until live geometry and entry paths are audited.

**Implementation note:** the source phase is not production runtime certification. Do not treat honeypot activity as standalone grounds for punishment.
