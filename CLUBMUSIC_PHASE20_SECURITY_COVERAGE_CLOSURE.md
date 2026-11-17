# Phase 20 — Security Coverage Closure

**Status:** Scoped repository text-source coverage audit completed. This phase records confirmed owners and trust boundaries; binary package and native third-party internals remain explicitly outside the inspected text-source scope.

## Audit inventory

| Surface | Server owner | Security boundary / current finding |
|---|---|---|
| ClubMusic RequestAction | UI_Server_Controller_server (1).lua | Fixed action dispatcher, bounded payload validation, per-player/server budgets, action-specific permission and entitlement checks |
| ClubMusic state/catalog/playlists | Same controller | Read-only RemoteFunctions with query bounds/throttles; no diagnostic event history returned to clients |
| Purchase prompt diagnostics | Same controller | Untrusted bounded prompt telemetry only; ProcessReceipt and durable receipt ledger remain purchase authority |
| Tiki Tide Settings Request | TikiTideSettingsService.server.lua | Live player, bounded payload, action allowlist, entitlement/permission, cooldown and post-yield reauthorization |
| Tiki Tide Settings Broadcast | Same service | Server-to-client only in the inspected source; filtered server-authored content |
| UtilityBar RefreshOwnAvatar | UtilityBarActions.server.lua | Own-avatar scope, cooldown, live-player and post-yield character/session checks |
| UtilityBar ExecuteUtility | UtilityBarExtendedActions.server.lua | Live player, action allowlist, bounded payload, server-owned entitlement checks, cooldowns |
| UtilityBar ToolShop | ToolShop.server.lua | Read-only catalog query, live-player guard and query cooldown |
| Kohl's Admin adapter | KohlsAdmin_ClubMusic_Addon.lua, RegularCommandsSecurityServer.lua | Command groups plus independent server-side SecurityCore checks and bounded target/value validation; native package internals are not certified |
| Teleport tickets | TeleportValidationService.lua | ServerStorage-only BindableFunction; caller must authorize before ticket issuance; ticket validates identity, expiry and destination |
| Movement observer | CharacterPhysicsGuard.lua | Detection-only property/velocity observer; not an enforcement authority |
| Staff spectator | StaffSpectatorService.lua | Server-only service; live actor and SecurityCore GlobalModeration authorization; camera script is presentation only |
| Diagnostics/replay/threat/honeypot | SecurityCore modules and ServerStorage endpoints | Server-only read paths; diagnostics local to each server; client-integrity observations remain untrusted |

## Source-level findings

- The audited text sources expose no additional client-to-server ProximityPrompt, ClickDetector, or DragDetector handlers. This is limited to tracked text sources and does not certify binary assets or packages.
- ServerStorage BindableFunctions are server-to-server interfaces, not client remotes. Each mutating endpoint must still authorize the supplied live actor independently.
- SecurityCore.Authorization remains the central permission authority. EntitlementAuthority resolves pass/group tiers; a pass entitlement is not a staff permission.
- Tiki Tide movement settings, UtilityBar Size, and the reviewed Kohl's adapter have identifiable server-side owners. Native flight/freeze/vehicle/mount/knockback behavior remains unverified until the actual handlers/assets are inspected.
- Audio validation/replay hooks are present in the controller. This audit does not claim every external boombox or third-party animation path is in the repository.
- No client-side integrity report is treated as proof, authorization, or a moderation decision.

## Coverage closure decisions

- Keep unknown or third-party paths denied until an explicit server adapter is reviewed; do not invent permissive fallbacks.
- Do not add a generic remote that accepts arbitrary action names, Instance paths, asset IDs, or server object references.
- Every newly discovered client-triggered path must document: owner, live actor check, SecurityCore permission or entitlement, state/context checks, type/size validation, server-side rate limit, audit/replay outcome, and failure behavior.
- Preserve modern AudioPlayer ownership, crossfade, independent local queues, playback-only global sync, purchase receipts, UtilityBar, and mobile UI.

## Acceptance matrix

- [ ] Exercise ordinary player, DJ 100, Moderator 150, Admin 200, Co-owner 254 and Owner 255 permissions.
- [ ] Test malformed, oversized, non-finite, unknown, replayed and burst remote requests.
- [ ] Verify permission revocation and authorization cache failure during yielding operations.
- [ ] Inspect live-place hierarchy and all binary .rbxm/.rbxmx and third-party packages, or record explicit exclusions.
- [ ] Test all actual movement, vehicle, mount, knockback, prompt and click handlers present in the live place.
- [ ] Re-run purchases, receipt recovery, playback, queues, global sync, UtilityBar, Settings, moderation and spectator regressions.

**Exit boundary:** the tracked text-source inventory is documented; this is not a blanket certification of uninspected assets or native Kohl's Admin internals.
