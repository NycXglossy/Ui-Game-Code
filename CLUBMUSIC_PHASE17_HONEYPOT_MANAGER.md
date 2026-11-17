# Phase 17 — Honeypot Manager

**Status:** Source implementation committed; Studio/published-server acceptance remains open. This phase adds isolated decoy remotes for detection and review. It does not replace real remotes, authorization, SecurityMonitor, SecurityReplayService, or SecurityThreatIntelligence.

## Implementation

- Added `ClubMusicSecurityCore/HoneypotManager.lua`, staged by the SecurityCore installer and pinned to the module release commit.
- Creates a dedicated `ReplicatedStorage/TikiTideSecurityDecoys` folder containing four isolated decoys:
  - `TTHP_AdminPrivilegeEvent`
  - `TTHP_PurchaseReceiptFunction`
  - `TTHP_VIPEntitlementEvent`
  - `TTHP_ModerationActionFunction`
- Decoys do not share names, arguments, or handlers with real gameplay remotes. They grant no privilege, process no purchase, modify no entitlement, and perform no moderation action.
- RemoteFunction decoys return a neutral unavailable response. RemoteEvent decoys perform no action.
- Each accepted hit records a fixed signal code to the existing server-local threat-intelligence and replay services. No client payload, argument, text, or arbitrary instance data is retained.
- Per-player hit cooldown is five seconds; tracked subject state is capped at 256. Aggregate counters are bounded. Player-removal cleanup is connected.
- Adds server-only `ServerStorage.GetTikiTideHoneypotStatus` and includes its state/counters in the existing unified diagnostics and staff `;cmdiagnostics` output.
- Installer shutdown stops the manager and destroys its dedicated decoy folder. A pre-existing folder is never overwritten; startup fails closed for the honeypot service only.
- No DataStore, MemoryStore, MessagingService, client-to-server diagnostics channel, enforcement action, or gameplay change is added.

## Evidence and response boundaries

- A decoy interaction is suspicious telemetry, not proof of cheating. It may be caused by a copied script, a test, or an unintended interaction.
- A single decoy hit does not trigger a kick, ban, shadow restriction, movement correction, or automatic IncidentResponse case.
- ThreatIntelligence still requires independent categories/codes before creating a review item. Honeypot-only signals do not bypass that correlation threshold.
- The service is local to each server. It does not share player hit history across servers.
- Decoys are visible in ReplicatedStorage and are not secrets. Their purpose is to detect interaction by scripts that enumerate or probe unexpected remote objects, not to make an exploiter unable to discover them.

## Runtime acceptance still required

1. Run installer in a disposable Studio test place; verify module staging, pinned source, promotion, rollback, and shutdown cleanup.
2. Verify the dedicated folder contains exactly the four expected remote objects and no real remote was replaced or renamed.
3. Invoke each decoy from a test client; verify the expected fixed signal, server-local replay entry, and threat-intelligence signal are recorded.
4. Verify RemoteFunction calls return the neutral response and RemoteEvent calls have no gameplay effect.
5. Verify repeated hits inside the five-second window are suppressed, subject tracking remains capped, and PlayerRemoving clears subject state.
6. Verify an isolated hit does not create a threat review item or enforcement action; verify correlation still requires independent categories/codes.
7. Verify wrong-class folder collisions do not overwrite existing objects and optional honeypot failure does not block ClubMusic startup.
8. Verify the status endpoint is ServerStorage-only and staff diagnostics show bounded counters without client payloads.
9. Profile burst traffic and run playback, queue, global playback-only sync, purchases, moderation, Utility Bar, Settings, spectator, and diagnostics regressions in Studio and published servers.

**Exit criteria:** no real remote contract changes, bounded detection overhead/state, no automatic enforcement, accurate local diagnostics, installer rollback/cleanup, and successful Studio/published-server testing.

**Implementation note:** the source phase is not production runtime certification. Do not treat honeypot activity as standalone grounds for punishment.
