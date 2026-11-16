# Phase 3 — Main UI Remote Ingress Hardening

## Goal

Apply the shared Server Authority & Sanity Validation Standard to the main ClubMusic UI remote boundary while preserving existing action-specific authorization, cooldowns, gameplay behavior and client contracts.

## Updated entry points

The main UI_Server_Controller_server (1).lua now:

- Loads ClubMusicSecurityCore.SanityValidation when the installer has deployed it.
- Uses ValidateDataTree for incoming action payloads with strict per-request ceilings: depth 3, 64 total entries and 1,024 characters per string.
- Retains the existing shallow action-field contract as a second compatibility check. The shared validator does not replace permission, entitlement, consent or game-state checks.
- Verifies the live Player instance at the action handler and read-only catalog, playlist and state query boundaries.
- Rejects catalog offsets outside 0–10,000 and page sizes outside 1–50, in addition to existing type/integer checks.
- Bounds client purchase-prompt diagnostic strings and product/pass identifiers. These remain untrusted telemetry and are not purchase proof; ProcessReceipt remains authoritative.

## CPU and memory controls

This phase is intentionally local to each server and adds no DataStore, MemoryStore or MessagingService calls.

- The action ingress token budget is consumed before traversing attacker-controlled payload tables, so malformed request spam is throttled before structural validation.
- Payload validation has fixed depth, entry and string-size ceilings. Work and temporary traversal state are therefore bounded per accepted validation attempt.
- Existing global/per-player action budgets, query budgets and cooldowns remain in place.
- Existing bounded purchase diagnostic storage and per-player cleanup remain in place.
- No new polling loops, background tasks, unbounded queues or persistent telemetry buffers are introduced.
- The shared validator is optional at startup for compatibility with servers where the installer has not yet been run; the controller retains its existing bounded local payload checks and emits a warning. Deploy the installer before treating the shared-validator integration as active.

These controls bound validation work; they do not claim a fixed CPU percentage or a precise per-script memory quota. Roblox does not expose a reliable per-module CPU budget control. Runtime profiling is still required.

## Preserved authority boundaries

- Client-side UI checks remain convenience only.
- The server continues to decide permissions, entitlements, queue changes, playlist mutations and playback controls.
- Client purchase prompt events are diagnostic telemetry only. They cannot grant passes, products, boosts or rewards.
- Durable ProcessReceipt handling and the existing receipt ledger are unchanged.
- Modern AudioPlayer playback, crossfade, local queues and optional playback-only global sync are unchanged.
- The Utility Bar remains separate from ClubMusic.

## Studio validation checklist

1. Run the Security Core installer so SanityValidation is present under ServerStorage.ClubMusicSecurityCore.
2. Confirm startup logs do not report the shared-validator fallback warning.
3. Exercise normal guest track requests, favorites, skip votes and read-only catalog browsing.
4. Exercise owner/co-owner/staff playlist and playback controls; confirm permission hierarchy is unchanged.
5. Send malformed payloads in a controlled test: non-table payload, unsupported value, cyclic table, excessive nesting, more than 64 entries, overlong strings, NaN/infinity, and invalid key types. Confirm no state mutation occurs.
6. Test catalog offsets at -1, 0, 10,000 and 10,001; test page sizes at 0, 1, 50 and 51.
7. Burst malformed and valid action requests; confirm ingress budgets reject excess traffic without excessive log growth or server degradation.
8. Check that player departure clears per-player request and purchase-diagnostic rate state.
9. Profile a representative server at expected player count and under controlled request bursts. Compare script activity, server memory and responsiveness before/after.
10. Re-test modern playback controls, queue operations and global playback-only sync to ensure the shared server script remains behaviorally compatible.

## Scope not yet completed

This phase does not claim that every server remote in the experience is covered. The following still need their own inventory and domain-specific integration: Tiki Tide Settings, Utility Bar, VIP/zone access, purchases and receipt processing, avatar/accessory changes, audio/animation requests, chat/text and social actions. Kohl's Admin bring/tp/to ticket integration remains pending until the external command handler's exact semantics are verified.

No Roblox Studio or published-server runtime tests have been performed for this phase.