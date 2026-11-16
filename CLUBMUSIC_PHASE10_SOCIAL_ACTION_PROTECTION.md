# Phase 10 — Social Action Protection

**Status:** Implemented in source for the social-action pathway found in the audited repository snapshot; runtime verification remains outstanding.

## Audit scope

The inspected snapshot contains one direct player-to-player social movement action: Tiki Tide Settings' `TeleportTo` request. The Utility Bar extended actions inspected here operate on the caller's own character or shared stage/club lighting; no separate friend, follow, invitation, trade, or emote remote was found in the inspected files. This is not a claim that no such feature exists elsewhere in the full Roblox place.

## Implemented safeguards

- Validate the requested target user ID as a finite, positive integer within the safe integer range.
- Resolve the target from the live server-side Players service; reject missing or self targets.
- Require both players to have live characters and living Humanoids.
- Preserve recipient opt-in through `TikiTideAllowTeleport`; retain the existing authorized GlobalModeration exception.
- Re-check the actor's Tiki Tide entitlement, both live sessions, both character identities, and recipient consent after permission checks that may yield.
- Re-check character and root-part identity immediately before moving the actor.
- Keep destination selection server-derived from the target's observed root transform and continue to require the existing server-only TeleportValidationService ticket.
- Add a per-actor teleport cooldown (2 seconds) and per-recipient inbound cooldown (3 seconds). Both reservations occur without yielding, preventing concurrent requests from bypassing the budgets.
- Release reservations when ticket creation or movement fails before execution; retain the recipient budget if movement occurred but final verification fails.
- Clear per-session cooldown entries when a player leaves.
- Keep the existing global ingress token bucket and request cooldown; no new remote, DataStore, MemoryStore, polling loop, or client authority was introduced.

## Deliberate non-changes

- No changes to the teleport UI or client request contract.
- No changes to mobile layout.
- No new friend/follow/invite/trade/emote systems were invented.
- No automatic kick, ban, or moderation incident is generated from a denied or rate-limited request.
- Existing staff hierarchy and recipient consent exception remain intact.

## Verification still required

- Studio multi-client tests: recipient opt-in on/off, authorized moderation override, self-target, departed target, respawn during permission resolution, and simultaneous requests from multiple actors to one recipient.
- Verify actor and recipient cooldown boundaries and that failed ticket creation does not strand the cooldown.
- Verify the TeleportValidationService ticket is consumed and the destination remains correctly verified.
- Regression-test Tiki Tide Settings, player roster refresh, Utility Bar, and desktop/mobile/console clients.
- Run adversarial request flooding and malformed user-ID tests.
- No Roblox Studio or published-server runtime test is claimed by this source commit.
