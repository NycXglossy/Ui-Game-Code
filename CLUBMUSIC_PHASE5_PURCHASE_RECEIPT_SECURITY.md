# Phase 5 — Purchases & Receipt Security

## Scope

Harden the existing Developer Product receipt boundary without replacing its durable storage design, reward handlers, recovery sequence, or Roblox `MarketplaceService.ProcessReceipt` ownership.

## Receipt metadata validation

Before looking up players, profiles, products, or receipt caches, the callback now requires:

- a table-shaped receipt payload;
- a positive, finite, whole-number PlayerId within the safe integer range;
- a positive, finite, whole-number ProductId within the safe integer range;
- a PurchaseId that is already a string, with 1–128 bytes.

Malformed metadata returns `NotProcessedYet`; it is never coerced into a fake identifier such as the string `"nil"`, and no reward is granted.

The registered `PRODUCT_MAP` remains the allowlist. Unrecognized product IDs remain ungranted and retryable; receipt metadata never supplies reward amounts or entitlement values.

## Bounded receipt fast-path cache

The per-server `processedReceipts` optimization is now a 512-entry ring cache. It is only a fast path:

- eviction removes only an in-memory acknowledgement hint;
- the durable receipt journals remain the source of truth;
- normal products still verify the durable `ClubMusic_ProductReceipts_v1` journal and profile transaction;
- XP boosts still use the existing global `ClubMusic_XPBoostReceipts_v1` receipt journal and its legacy-key compatibility path.

No durable receipt history is pruned or replaced by this cache.

## Preserved transaction guarantees

- Existing `Prepared` / `Completed` journal lifecycle remains intact and is now implemented by `ClubMusicSecurityCore.ReceiptTransactionService`.
- Reward mutation and profile pending marker remain in the existing atomic profile update.
- Receipt journal completion and pending-marker cleanup remain required before `PurchaseGranted`.
- Failed DataStore operations continue to return `NotProcessedYet` so Roblox can retry.
- Existing SHA-256-derived receipt hash key derivation and full PurchaseId collision comparison remain intact; the hash implementation now lives at `ClubMusicSecurityCore.ReceiptHash`.
- Existing legacy profile receipt map and legacy XP receipt keys remain readable.
- Product reward mappings, donation rewards, title-slot unlocks and XP boost durations are unchanged.
- Legitimate purchases are not denied based on security threat scores or moderation state.

## CPU and memory considerations

- The fast-path cache is strictly bounded to 512 receipt IDs.
- Receipt validation is constant-time and runs before player/profile lookups.
- No new polling loops, background workers, DataStore reads, MessagingService traffic or per-receipt diagnostic history were added.
- The durable receipt ledger remains intentionally persistent and is not pruned; its growth is part of the purchase audit/replay guarantee.
- DataStore budget waits and transaction work remain the existing purchase-path costs. This phase does not claim a fixed CPU percentage or a hard Roblox memory quota.


## Security Core receipt boundary integration — Phase 29

The sole `MarketplaceService.ProcessReceipt` assignment remains in `UI_Server_Controller_server (1).lua`, but now delegates to `ClubMusicSecurityCore.ReceiptAuthority`. Security Core owns receipt metadata validation, registered-product resolution, same-server in-flight exclusion, a 64-handler concurrency cap, and the bounded 512-entry successful-receipt cache.

`ClubMusicSecurityCore.ReceiptTransactionService` now owns the profile-backed durable journal, `Prepared`/`Completed` transitions, profile pending-marker recovery, per-profile write-lock coordination, and bounded in-memory reconciliation. `ClubMusicSecurityCore.ReceiptHash` preserves the exact previous key derivation. The separate global XP receipt journal remains owned by the Global Service because its atomic global boost timer mutation is cross-server domain state. The standalone root-level `ClubMusic_ReceiptHash` module and controller-side journal implementation are retired. No second ProcessReceipt callback, replacement ledger, MemoryStore receipt reservation, or new purchase ID format is introduced.

See [Phase 29 — Economy, Entitlement & Reward Abuse Protection](CLUBMUSIC_PHASE29_ECONOMY_ENTITLEMENT_REWARD_ABUSE.md) for the economy mutation inventory, configured IDs, entitlement rules, and runtime acceptance checklist. The Security Core installer must be updated with the matching ReceiptAuthority module release before the updated controller is deployed. If the module is unavailable, the callback returns `NotProcessedYet`; it does not fall back to an unprotected grant path.

## Required Studio and published-server tests

1. Test every configured Developer Product: all donation tiers, 2x/4x XP boosts and title slots 2/3.
2. Confirm one purchase grants exactly one reward and updates the expected player attributes/UI.
3. Simulate duplicate ProcessReceipt callbacks and verify no duplicate reward.
4. Test receipt retry while player/profile is unavailable; verify Roblox can retry and reward is eventually granted once.
5. Test DataStore budget exhaustion and transient failures at prepare, profile apply, journal completion and pending-marker cleanup.
6. Rejoin after an interrupted receipt and verify recovery completes before another receipt is processed.
7. Confirm XP boost duplicate/retry behavior through the existing global XP receipt journal, including legacy receipt-key recovery.
8. Confirm an unrecognized ProductId is never granted.
9. Exercise the bounded 512-entry cache in a controlled harness and confirm eviction does not bypass durable journal checks.
10. Profile CPU and memory during normal purchase traffic and controlled bursts.

No Roblox Studio or published-server runtime tests have been performed for this phase.


## Phase 33 — Complete Security Core transaction migration

- `ReceiptAuthority` remains the only receipt ingress coordinator and is called by the controller's single `MarketplaceService.ProcessReceipt` adapter.
- `ReceiptTransactionService` owns the normal product durable journal and pending-receipt recovery.
- `ReceiptHash` is installed under `ServerStorage.ClubMusicSecurityCore` and is shared by the profile journal and Global Service XP journal.
- The controller retains only the product allowlist, game-specific reward application/presentation adapters, profile/session adapter closures, and the one Roblox callback assignment. It no longer owns the durable receipt journal implementation or receipt-memory caches.
- `ClubMusic_ReceiptHash.lua` was removed from the repository after both consumers moved to Security Core.
- Existing DataStore names, key prefixes, hash output, full PurchaseId checks, legacy `receiptIds`, legacy XP key compatibility, reward mappings, and boost timer behavior are preserved.
- The installer includes `ReceiptHash` and `ReceiptTransactionService` and is pinned to the source snapshot containing both modules.

This is source-level migration only. The purchase matrix, interrupted-write recovery, and two-server XP boost tests remain required in a disposable Studio universe before production installation.
