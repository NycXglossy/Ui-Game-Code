# Phase 6 — VIP Zone & Entitlement Security

## Goal

Centralize server-side membership entitlement decisions without changing the existing player-profile schema, DataStore contracts, durable receipt journals, pass products, or owner-awarded membership workflow.

## Added component

`ClubMusicSecurityCore/EntitlementAuthority.lua` is a server-only resolver for the three membership tiers.

It accepts the existing `SecurityCore.Authorization` instance and configured pass IDs. It does not independently query group membership; group status and staff rank continue to come from the existing Authorization cache.

### Membership rules preserved

| Source | Result |
|---|---|
| Roblox group `500470662` membership | VIP |
| VIP Game Pass `2089785323` | VIP |
| VVIP Game Pass `2089263330` | VVIP |
| Tiki Tide Game Pass `2087955353` | Tiki Tide |
| Existing profile `rewardedPassTier` | Owner-awarded tier, 0–3 |
| Configured owner rank | All membership tiers |

The highest applicable tier wins. The owner-awarded tier remains in the existing profile and can grant VIP, VVIP, or Tiki Tide without requiring a paid pass. Paid purchase options remain enabled and unchanged.

Other staff ranks do not automatically receive membership tiers unless the existing owner/group/pass/award rules grant them.

## Storage and performance compatibility

- No DataStore or MemoryStore was added.
- No profile field, profile key, DataStore name, receipt key, receipt journal, or save format was changed.
- `rewardedPassTier` remains the existing persisted owner-award field.
- Group membership reuses `SecurityCore.Authorization` and its bounded 120–300 second cache.
- Paid membership checks use a bounded, per-live-player in-memory cache with a 300-second successful TTL.
- Concurrent refreshes for the same player are coalesced.
- Player cache entries are cleared when the player leaves.
- Failed marketplace lookups use a short 15-second retry window. Previously verified pass ownership is retained through a transient lookup failure; a first-time unknown result does not grant access.
- Successful membership purchases force a refresh so the new pass is not hidden behind a still-valid cache entry.
- No new periodic polling loop was added. The existing join, purchase, and refresh call sites use the centralized cache.

The existing `ownsGamePass` helper remains for unrelated feature passes such as Island Mount, Companion, Lighting and personal XP. Those products are not conflated with membership tiers.

## Main controller integration

`UI_Server_Controller_server (1).lua` now routes:
- `passTier`, `isVip`, `isVvip`, and `hasTikiTideAccess` through EntitlementAuthority;
- membership refreshes through the authority instead of three independent pass lookups every refresh cycle;
- the group-member roster field through the existing Authorization group cache;
- player-removal cleanup through the authority's bounded cache cleanup.

The controller continues publishing the existing server-derived attributes:
`IsVIP`, `IsVVIP`, `HasTikiTideAccess`, and `ClubPassTier`.

`TikiTideSettingsService.server.lua` already consumes the server-set `HasTikiTideAccess` attribute, so its existing Tiki Tide gate now receives the centralized result without introducing another entitlement lookup or changing its session-only settings state.

If the new module is unavailable during staged deployment, paid/group membership access fails closed. Existing owner access and profile-awarded tiers remain available. Deploy the Security Core installer and controller update together.

## Physical VIP zone scope

The repository tree at the Phase 6 audit commit contains no dedicated VIP/VVIP/Tiki Tide physical zone boundary or touch-handler script. The current work therefore centralizes the entitlement source and integrates the existing membership-dependent controller and Tiki Tide Settings paths; it does not invent zone names, parts, or collision behavior.

When the actual zone scripts/parts are supplied or added, each entry point must call the same server-side entitlement authority, validate the live character/root and zone boundary, and deny unauthorized entry safely. Entitlement API failure must not be recorded as proof of exploitation. No automatic kick or ban is part of this phase.

## Installer

The Security Core installer now includes `EntitlementAuthority` immediately after `Authorization`. Its download pin points to commit `1d33ed0b8019361fcfac36f6d2f35ba6020de973`, which contains the module source.

The installer has not been executed in Roblox Studio.

## Verification checklist

### Source-level checks
- [x] Existing group ID and three membership pass IDs preserved.
- [x] Existing owner and owner-awarded membership rules preserved.
- [x] Profile schema and durable receipt processing untouched.
- [x] No new DataStore, MemoryStore, MessagingService, polling loop, or client entitlement authority.
- [x] Paid-pass refresh after a successful purchase bypasses the cache.
- [x] Entitlement cache is per active player, bounded by player lifecycle, and cleared on leave.
- [x] No physical VIP-zone scripts were found in the audited repository tree.

### Required Roblox tests
1. Join with a group-member account but no membership pass: VIP tier and VIP attributes should apply after group-rank cache resolution.
2. Join with each paid pass separately and confirm the expected tier and perks.
3. Confirm VVIP and Tiki Tide paid tiers supersede lower tiers.
4. Award VIP, VVIP, and Tiki Tide through the existing owner rank-up action; confirm the awarded tier survives refresh and rejoin.
5. Confirm owner receives all membership tiers.
6. Purchase a membership pass during a session; confirm the forced refresh activates it immediately.
7. Simulate MarketplaceService lookup failure: a first-time unknown pass must not grant access, and previously verified pass ownership must not be erased by a transient failure.
8. Confirm group membership refresh and rank promotion/demotion behavior after the existing Authorization cache expires.
9. Confirm Tiki Tide Settings remains gated by the server-set attribute and existing teleport validation remains unchanged.
10. Run multiplayer tests with Studio mode configured for both `StudioStaff = true` and `StudioStaff = false`.

## Verification status

- Repository source integration: completed.
- Installer execution: not performed.
- Roblox Studio multiplayer tests: not performed.
- Published-server tests: not performed.
- Physical VIP-zone enforcement: pending identification/integration of the actual zone scripts and parts.

No live DataStore records or production player profiles were read or modified by this phase.
