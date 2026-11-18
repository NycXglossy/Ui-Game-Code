# Phase 29 — Economy, Entitlement & Reward Abuse Protection

## Goal

Audit the ClubMusic/Tiki Tide economy and move the Developer Product receipt ingress and transaction coordinator into ClubMusic Security Core without changing the existing Roblox receipt owner, durable receipt stores, journal keys, profile schema, reward mappings, or purchase IDs.

This is the first Security Core receipt integration. It is deliberately staged: Security Core now owns receipt metadata validation, registered-product resolution, same-server concurrency exclusion, and the bounded successful-receipt fast path. The existing controller profile-journal adapter and global XP-boost journal remain the durable transaction backends until their migration can be performed with explicit recovery compatibility tests.

## Authority invariants

- There is exactly one intended `MarketplaceService.ProcessReceipt` assignment: `UI_Server_Controller_server (1).lua`.
- The controller callback delegates to `ClubMusicSecurityCore.ReceiptAuthority`; no second callback or parallel receipt handler is installed.
- Only the Roblox-supplied server receipt callback can enter the reward transaction path. Client purchase prompts and `PurchaseDiagnostic` events are unverified telemetry only.
- The server-side `PRODUCT_MAP` remains the Developer Product allowlist. A receipt's ProductId never supplies a reward amount, pass tier, coin amount, slot number, or boost duration.
- Security Core returns `PurchaseGranted` only after the existing authoritative transaction handler confirms success. Invalid metadata, unknown products, capacity pressure, concurrent in-flight duplicates, storage failures, or handler errors return `NotProcessedYet` so Roblox can retry.
- Legitimate purchases are not denied based on threat scores, moderation state, or client integrity telemetry.
- The generic Security Core `Idempotency` service is not used as a receipt ledger. Its local TTL cache and optional MemoryStore reservation are not substitutes for the durable purchase journals.

## Security Core integration

New module: `ClubMusicSecurityCore/ReceiptAuthority.lua`.

- Validates table payload, positive finite safe-integer PlayerId/ProductId, and string PurchaseId of 1–128 bytes.
- Resolves ProductId only through the server's registered product map.
- Uses a composite in-memory key of PlayerId, ProductId, and PurchaseId.
- A repeated callback for the same in-flight purchase returns `NotProcessedYet`; it cannot run a second reward handler concurrently in the same server.
- Caps concurrent distinct receipt handlers at 64. Saturation is retryable and does not discard receipts.
- Maintains a 512-entry bounded cache of receipts whose authoritative handler returned `PurchaseGranted`. Cache eviction only removes a fast-path hint; it does not prune or weaken durable history.
- Wraps the transaction handler in protected execution. Unexpected errors become retryable results.
- Exposes bounded server-local counters through `ServerStorage.GetTikiTideReceiptAuthorityStatus`.
- Does not persist PurchaseIds in a new store, add MemoryStore traffic, create remotes, or change the existing durable journal format.

The controller remains the sole Roblox callback owner. It passes the server product resolver and existing transaction handler to ReceiptAuthority. The durable profile transaction and the separate global XP transaction remain in their existing storage adapters. This preserves the established recovery implementation while moving the trust boundary and in-server receipt coordination into Security Core.

Installer update: `ClubMusic_Security_Core_Installer.lua` includes `ReceiptAuthority` and pins the Security Core release to commit `24a26719f36a63fd5efeaf73420eaf78491f521c`, which contains the module. Install the matching Security Core release and controller source together. If the module is unavailable, the controller leaves receipts retryable rather than granting outside Security Core.

## Existing durable receipt guarantees preserved

### Profile-backed products

- DataStore: `ClubMusic_ProductReceipts_v1`.
- Journal key: `r_` plus the first 160 bits of the SHA-256 digest produced by `ClubMusic_ReceiptHash.KeySuffix(userId .. ":" .. PurchaseId)`.
- The journal stores the full PurchaseId, UserId, ProductId, product type, and `Prepared` / `Completed` state. Full PurchaseId and identity comparisons remain the collision check.
- The profile reward and `pendingReceipt` marker are written atomically in the profile `UpdateAsync`.
- The receipt journal is completed before the profile pending marker is cleared and before Roblox is told `PurchaseGranted`.
- Existing profile session locks, per-user profile write serialization, pending-receipt recovery, legacy `receiptIds` reads, and in-memory reconciliation remain unchanged.
- Durable receipt history is not pruned. The 512-entry Security Core cache is only a session fast path.

### Global XP boost products

- DataStore: `ClubMusic_XPBoostReceipts_v1`, with existing `globalXPBoost_v1` timer state in `ClubMusic_GlobalControl_v1`.
- New hashed receipt keys use the existing `xph_` prefix and `ClubMusic_ReceiptHash`; legacy `xpr_` keys and the legacy shared `receipts` map remain readable.
- The active boost extension and `pendingReceipt` marker are committed atomically in the global timer record. The per-purchase journal is completed and the pending marker cleared before activation is acknowledged.
- 2x and 4x global boost durations remain 900 and 1,800 seconds respectively; existing timer stacking/cap behavior is unchanged.
- Studio's existing session-only boost path remains a Studio-only exception and is not represented as a production durable purchase.

## Configured product and pass inventory

### Developer Products

| Product | ID | Existing reward |
|---|---:|---|
| Coconut donation | 3731488823 | 10 base amount; 15 tickets and 100 coins |
| Pineapple donation | 3731489572 | 50 base amount; 75 tickets and 500 coins |
| Tiki Torch donation | 3731490154 | 100 base amount; 150 tickets and 1,000 coins |
| Volcano donation | 3731490513 | 500 base amount; 750 tickets and 5,000 coins |
| Island Legend donation | 3731490937 | 1,500 tickets and 10,000 coins |
| Island Royalty donation | 3731491257 | 7,500 tickets and 50,000 coins |
| Sultan's Legacy donation | 3731491679 | 15,000 tickets and 100,000 coins |
| 2x global XP boost | 3731386650 | 900 seconds |
| 4x global XP boost | 3731387153 | 1,800 seconds |
| Title Slot 2 | 3731392651 | Unlocks slot 2 |
| Title Slot 3 | 3731394060 | Unlocks slot 3 |

The donation coin/ticket values above follow the current mapping: `coins = amount * 10`; `tickets = floor(amount * 1.5)`.

The five older Shop Item product IDs (`Glowsticks`, `TikiMask`, `NeonAura`, `NeonLei`, `LEDShades`) are currently zero and are intentionally not registered. Their `costCoins` metadata does not make them purchasable. Neon Lei's 500-coin reward is dormant until a real product ID is configured. No replacement IDs are invented.

### Game Passes and group membership

| Entitlement | ID / source |
|---|---|
| Roblox group membership | Group 500470662 grants VIP |
| VIP Game Pass | 2089785323 |
| VVIP Game Pass | 2089263330 |
| Tiki Tide Game Pass | 2087955353 |
| Personal 2x XP Game Pass | 2088891595 |
| Personal 4x XP Game Pass | 2089053637 |
| Island Mount Game Pass | 2087955619 |
| Island Companion Game Pass | 2088585676 |
| Stage & Club Lighting Game Pass | 2088315619 |

Membership tiers continue to resolve through `ClubMusicSecurityCore.Authorization` and `EntitlementAuthority`. The group member rule grants VIP; the highest valid paid/group/owner-awarded tier wins; the configured owner receives all membership tiers. Other staff do not automatically receive membership unless the existing rules grant it. `rewardedPassTier` remains the existing profile field and owner award path.

The server's `PromptGamePassPurchaseFinished` listener uses the `purchased` signal only to decide whether to refresh. Actual access is rechecked through `UserOwnsGamePassAsync` / EntitlementAuthority. Client prompt telemetry never grants a pass or Developer Product.

## Economy mutation audit

### Main ClubMusic profile

- Donation receipts grant tickets and coins through the receipt transaction only.
- Daily reward action `ClaimDailyReward` grants coins (days 1 and 5), Glowsticks (day 2), tickets (day 3), skip token (day 4), Neon Trail (day 6), or Island title tag (day 7). It checks the server profile's `claimedToday` and exact `loginStreak` before mutation, sets the claim marker in the same synchronous handler, then schedules the existing profile save.
- `BuyTitleTag` spends tickets (Bass 150, Sunset 250, Tiki 400) and sets ownership in the same synchronous handler after checking ownership and balance. It uses the existing one-second action cooldown and schedules the existing profile save.
- `ModSetPassTier` is owner-only (Security Core rank level 4), validates target and tier 0–3, and writes the existing `rewardedPassTier` field. It is not a client-purchase grant.
- XP accrual is server-owned in `settlePlayerXP`: it uses elapsed server time, fractional carry, the server-cached global boost, and `PersonalXPMultiplier` populated from verified Game Pass ownership. The client does not submit XP amounts or multipliers. XP is capped and saved through the existing profile save path.
- Club playtime increments by 60 server-observed seconds per minute. It drives the 10-hour Party Animal tag; the 7-day login streak grants Wave Rider; verified VIP status grants the VIP title tag. These are server-derived, idempotent ownership flags rather than client reward requests.
- Staff title-slot elevation remains a server-derived staff benefit, not a Developer Product grant.
- No general client coin-grant or client-provided reward amount path was found in the audited controller/Utility Bar paths.

Daily claim and title-tag purchase state changes are synchronous against the one active in-memory profile session and use existing profile session ownership and save serialization. They do not currently have separate durable per-action transaction journals. Their crash/rejoin persistence and rapid concurrent RemoteEvent behavior remain explicit Studio acceptance tests before adding another idempotency layer.

### Separate Utility Bar Tool Shop currency

- `UtilityBar/ToolShop.server.lua` owns a separate `TikiTideCoins_v1` DataStore and `leaderstats.Coins` value.
- It loads, autosaves, and saves on leave/shutdown; its RemoteFunction currently supports only `GetShop` and returns an empty item list.
- There is no current Tool Shop purchase, spend, grant, or client balance mutation path.
- This is not the main ClubMusic profile `coins` field. Do not silently merge the two stores or balances during a security-only phase.

## Prompt telemetry boundary

- `PurchaseDiagnostic` accepts bounded, rate-limited client telemetry and explicitly records prompt outcomes as unverified.
- `ProcessReceipt` is the only Developer Product reward grant authority.
- `PromptGamePassPurchaseFinished` does not assign pass ownership from its boolean. It triggers an authoritative Marketplace ownership refresh.
- No client purchase callback, replicated attribute, prompt result, or client-supplied ProductId is accepted as proof of payment.

## Remaining audit and acceptance work

1. Run source-wide search in the actual deployed place for every `MarketplaceService.ProcessReceipt` assignment and ensure only this controller owns it.
2. Execute the updated installer and controller together in a disposable Studio universe; confirm ReceiptAuthority loads and the status endpoint reports Ready.
3. Verify Roblox catalog metadata for all configured Game Pass and Developer Product IDs using the controller's startup Marketplace metadata diagnostics. Source-level ID consistency is checked; live catalog ownership/name/price availability is not certified by this repository pass.
4. Test every donation tier, both global boosts, and title slots 2/3. Confirm exact reward values and one grant per PurchaseId.
5. Test malformed metadata, unknown ProductId, same-PurchaseId concurrent callbacks, distinct concurrent receipts, the 64-handler cap, and 512-cache eviction.
6. Test missing player/profile, profile lock contention, DataStore budget exhaustion, transient failure at every Prepared/apply/Completed/marker-clear boundary, interrupted server, rejoin recovery, and duplicate receipt after cache eviction.
7. Test XP boost legacy `xpr_` keys, hashed `xph_` keys, legacy shared receipt map, pending-marker recovery, stacking, cap, and cross-server publication.
8. Confirm client prompt telemetry cannot grant any product or pass. Confirm a spoofed `PurchaseDiagnostic` event changes only bounded telemetry.
9. Test group-only VIP, each paid membership pass, owner access, owner-awarded tiers, Marketplace transient failures, and every feature pass separately.
10. Test daily reward double-click/concurrent requests, midnight/day rollover, reconnect after claim, profile save failure, and rapid repeated `BuyTitleTag` requests. Confirm no duplicate reward or negative ticket balance.
11. Verify the separate Tool Shop coin store remains isolated and empty; no unexpected mutation path is present.
12. Profile receipt latency, DataStore budgets, retries, memory, and queue behavior under normal and burst purchases.

## Verification boundary

- Source-level integration and static consistency checks only.
- No Luau parser, Roblox Studio runtime, live Marketplace metadata request, or published-server runtime was available for this pass.
- Do not claim receipt certification until the above Studio and published-server tests pass.
- No production DataStore records or player profiles were read or modified.
- The feature branch is not merged or published; the live Roblox place is unchanged.


## Phase 29 implementation record

- `ReceiptAuthority.lua` added in commit `24a26719f36a63fd5efeaf73420eaf78491f521c`.
- The controller's sole ProcessReceipt callback delegates to Security Core in commit `59e7bdf1ad58aca8e5b61c6c61754246f1d1f5f1`; callback structure/logging refinements followed in `cbaf57a6c4b8a7685e090ed548ca334c20e080ec`.
- Receipt diagnostics and malformed-ID sanitization were refined in `6df1539279ec288af61063df2e016b391f74d356`, `7260c9e18b26d2b57bc8f1d97ad026b3b5d2bb7e`, and `94000c0d85e9530b33b8c60ec9f231d688c657e8`.
- Startup Marketplace metadata diagnostics now include all seven donation products in `62df424d5189d2a6a653dac330f4ee7f453d7e43`.
- Security Core installer includes the module and pins its source release in `08db637fbeb9cea0502afd5288af38472d325aad`.
- Phase 5 receipt documentation cross-reference: `30458b8f0a20c46792f8d1ebaf3bddcddb9a81b8`.

Static source checks confirmed the expected 20 configured group/pass/product identifiers are present, the donation IDs are included in startup metadata checks, the controller contains one ProcessReceipt assignment, the callback delegates to ReceiptAuthority, the old controller-local 512-entry cache is removed, and the existing profile/global durable journals and legacy XP receipt compatibility paths remain in place.

**Migration boundary:** ReceiptAuthority now owns validation, server product resolution, in-flight exclusion, bounded successful-receipt caching, and dispatch into the existing transaction handlers. The durable profile journal implementation still resides in the controller, while global XP receipt persistence remains in the cross-server service. Those storage backends were intentionally not rewritten in this first integration slice; their journal names, keys, recovery protocol, and existing production data compatibility remain unchanged.
