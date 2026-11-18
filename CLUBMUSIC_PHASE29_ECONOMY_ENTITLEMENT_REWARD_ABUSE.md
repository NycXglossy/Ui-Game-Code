# Phase 29 — Economy, Entitlement & Reward Abuse Protection

## Goal

Audit the ClubMusic/Tiki Tide economy and move the Developer Product receipt ingress and transaction coordinator into ClubMusic Security Core without changing the existing Roblox receipt owner, durable receipt stores, journal keys, profile schema, reward mappings, or purchase IDs.

Phase 29 introduced the staged Security Core receipt boundary. Phase 33 completed the profile-journal migration: Security Core now owns receipt metadata validation, registered-product resolution, same-server concurrency exclusion, the bounded successful-receipt fast path, the durable profile receipt journal, and pending-receipt recovery. The Global Service continues to own the cross-server XP boost journal because that transaction atomically updates shared boost state.

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

The controller remains the sole Roblox callback adapter because Roblox requires one `MarketplaceService.ProcessReceipt` assignment. It supplies the server product allowlist, game-specific reward mutators, profile/session adapters, and presentation callbacks. `ReceiptAuthority` delegates profile-backed persistence to `ReceiptTransactionService`; the Global Service retains its existing durable XP boost journal.

Installer update: `ClubMusic_Security_Core_Installer.lua` includes `ReceiptAuthority`, `ReceiptTransactionService`, and `ReceiptHash`, and pins the Security Core release to the source snapshot containing all three modules. Install the matching Security Core release and controller/global-service source together. If a required module is unavailable, the controller leaves receipts retryable rather than granting outside Security Core.

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
- New hashed receipt keys use the existing `xph_` prefix and `ClubMusicSecurityCore.ReceiptHash`; legacy `xpr_` keys and the legacy shared `receipts` map remain readable.
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

Membership tiers continue to resolve through `ClubMusicSecurityCore.Authorization` and `EntitlementAuthority`. Group members receive VIP. All verified staff ranks receive VIP automatically: Moderator (150), Admin (200), Co-Owner (254), and Owner (255). The configured Owner receives all membership tiers; other staff receive VIP only unless a higher tier is independently paid or owner-awarded. `rewardedPassTier` remains the existing profile field and owner award path.

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

- `ReceiptAuthority.lua` added in commit `24a26719f36a63fd5efeaf73420eaf78491f521c`; its in-flight identity was aligned with the durable per-user PurchaseId key in `d5a38b3740e7c2e1e03d4115db2d46cb3e813ec4`.
- The controller's sole ProcessReceipt callback delegates to Security Core in commit `59e7bdf1ad58aca8e5b61c6c61754246f1d1f5f1`; callback structure/logging refinements followed in `cbaf57a6c4b8a7685e090ed548ca334c20e080ec`.
- Receipt diagnostics and malformed-ID sanitization were refined in `6df1539279ec288af61063df2e016b391f74d356`, `7260c9e18b26d2b57bc8f1d97ad026b3b5d2bb7e`, and `94000c0d85e9530b33b8c60ec9f231d688c657e8`.
- Startup Marketplace metadata diagnostics now include all seven donation products in `62df424d5189d2a6a653dac330f4ee7f453d7e43`.
- Receipt status endpoint typing and PurchaseId log redaction were hardened in `756ed8577cd64da2eb7bd5e3ed467d718cb45a97` and `de61ff51473345d6fa83894e0882c7c3a5fcd655`.
- Security Core installer first included the module in `08db637fbeb9cea0502afd5288af38472d325aad`; it now pins the refined module source in `f87a15fb7a155adbbee9caa8a541d48dc3e06b27`.
- Phase 5 receipt documentation cross-reference: `30458b8f0a20c46792f8d1ebaf3bddcddb9a81b8`.

Static source checks confirmed the expected 20 configured group/pass/product identifiers are present, the donation IDs are included in startup metadata checks, the controller contains one ProcessReceipt assignment, the callback delegates to ReceiptAuthority, the old controller-local 512-entry cache is removed, and the existing profile/global durable journals and legacy XP receipt compatibility paths remain in place.

**Migration boundary:** ReceiptAuthority now owns validation, server product resolution, in-flight exclusion, bounded successful-receipt caching, and dispatch into the existing transaction handlers. The durable profile journal implementation still resides in the controller, while global XP receipt persistence remains in the cross-server service. Those storage backends were intentionally not rewritten in this first integration slice; their journal names, keys, recovery protocol, and existing production data compatibility remain unchanged.

## Player-to-player transfer proposal audit (TipPlayerRemote)

The supplied `EconomyHandler.server.lua` example was reviewed against the actual branch source. It is not installed as written and no `TipPlayerRemote` or existing player-to-player transfer endpoint was found in the inspected controller and Utility Bar sources.

### Confirmed existing economy ownership

- Main ClubMusic currency is `Profile.coins` and `Profile.tickets`, persisted in per-user keys in `SunsetStageClubProfiles_v1`.
- The main controller owns the active profile session lease, per-user in-memory write lock, snapshot save path, and coalesced save queue.
- The separate Utility Bar `TikiTideCoins_v1` store is exposed only through the current empty Tool Shop query endpoint. It is not a safe substitute for the main profile currency and must not be used for tips.
- The supplied example's local `Balances` table would create a third non-persistent currency authority and is rejected.
- Security Core `RateLimit` is a facade over the existing shared token buckets. `Idempotency` is a local-first / optional MemoryStore reservation service, not a durable two-account transaction ledger.

### Transaction-safety blocker

The main profile store persists each player under a separate DataStore key. Its current write lock is per user and protects a single profile snapshot. Roblox DataStore `UpdateAsync` cannot atomically mutate two different player keys in one transaction. Therefore, simply acquiring two in-memory locks, subtracting from one profile, adding to another, and scheduling two independent saves is not crash-safe: a server interruption or a failed save between the two writes can lose or duplicate currency.

A safe transfer requires a durable transfer journal and a recoverable two-phase protocol integrated with profile load/save/session ownership. Each transfer must have a server-generated immutable transaction ID, explicit Prepared/Debited/Credited/Completed progression, participant identity and amount validation, and idempotent recovery for both profiles. Recovery must not depend on either player remaining online or on a bounded in-memory cache. The design must also serialize conflicting transfers involving the same profile and preserve the existing profile receipt pending markers and session leases.

### Safe implementation decision

- No new RemoteEvent, balance mutation, third balance store, or partial debit/credit handler was added in this audit.
- Do not use Security Core's generic TTL idempotency cache as the durable transfer journal.
- Do not assume two independent profile saves constitute an atomic transfer.
- Before implementing the feature, select the currency explicitly (`coins` or `tickets`) and design/test the durable transfer journal and profile recovery protocol against the existing per-user session lease.
- Once implemented, validate targetUserId and amount as positive finite safe integers, reject self/offline targets, enforce the 10–5,000 amount range if retained, and use Security Core's existing rate-limit facade without throttling essential recovery or profile persistence.

### Source verification boundary

The branch source inspected for this audit contains no `TipPlayerRemote` reference and no player-to-player transfer handler. The main profile save path uses per-user `UpdateAsync` calls and a per-user in-memory lock; the Tool Shop uses a separate `TikiTideCoins_v1` DataStore and currently has no spend/grant operations. No runtime tests were run.


### Staff VIP policy update

- User-confirmed policy: every verified staff rank from Moderator (150) upward receives VIP automatically.
- `EntitlementAuthority:GetTier` now derives staff status from the existing `Authorization.GetRank` result; it does not introduce another role resolver or staff list.
- Staff VIP contributes tier 1. Owner remains tier 3. Admin and Co-Owner do not automatically receive VVIP or Tiki Tide.
- Installer release pin updated to the Security Core commit containing this change.
- Runtime verification of each rank remains outstanding.

## Dance Floor playtime rewards — server-authoritative integration

The supplied PlaytimeRewards.server.lua example was integrated into the existing main controller rather than installed as a second economy owner.

- The controller runs one bounded server loop at a 10-second interval. It awards 15 main-profile Coins per eligible interval.
- A 2x payout (30 Coins) is resolved through ControllerFunctions.passTier and the existing Security Core EntitlementAuthority. It does not trust the replicated IsVIP attribute or any client-supplied multiplier. Group members, all verified staff ranks, paid VIP owners, and owner-awarded VIP tiers receive the existing VIP entitlement according to the established policy.
- Zone presence uses oriented-part local coordinates and supports up to 16 valid zones. The map must tag each approved dance-floor BasePart with TikiTideDanceFloorZone. Missing/invalid zones fail closed; no guessed DanceFloorPart world instance is created.
- The player must have a live character, living Humanoid, and HumanoidRootPart inside a tagged zone. The vertical tolerance remains 10 studs above/below the zone's half-height to accommodate jumping.
- AFK activity is refreshed by server-observed displacement (0.5 studs), Humanoid MoveDirection, or playing Movement/Action-priority animation tracks. Animation inspection is capped at 64 tracks per player. Players inactive for more than 180 seconds receive no payout. This is an eligibility heuristic, not an anti-cheat verdict or punishment signal.
- Character replacement resets the position sample without resetting the AFK inactivity clock; repeated respawns cannot refresh eligibility. PlayerRemoving clears per-player state. The loop inspects at most 64 tagged instances and 16 valid zones per interval.
- The main profile adds danceFloorLastRewardAt. The balance and interval marker are written together in the existing profile snapshot, preventing repeat awards within 10 seconds after the updated snapshot is persisted. Saves are coalesced on a 30-second reward cadence and remain covered by normal autosave and final leave save. No third currency, remote, receipt callback, or separate DataStore is introduced.
- Rewards update the existing coins field and Coins player attribute. Tickets and the separate empty Tool Shop currency are untouched.

### Dance Floor acceptance tests still required

1. No tag / wrong-class tag / tag outside Workspace: no payout and no startup failure.
2. One rotated zone and multiple zones; test boundary edges, jumping tolerance, and a character outside every zone.
3. Living versus dead Humanoid, missing root, respawn during interval, and PlayerRemoving cleanup.
4. 15 Coins for regular players; 30 for group VIP, Moderator, Admin, Co-Owner, Owner, paid VIP, and owner-awarded VIP; no VIP multiplier when ownership is not verified.
5. Dancing in place with a Movement/Action animation remains active; walking, jumping, and MoveDirection refresh activity; 180 seconds inactive stops rewards; activity resumes eligibility.
6. Two or more rapid loop starts / controller restart; no more than one award per profile interval after the marker has been persisted.
7. Concurrent receipt, daily reward, title purchase, autosave, and final leave save; verify profile write serialization preserves both Coins and danceFloorLastRewardAt.
8. DataStore budget exhaustion and server interruption before/after a profile snapshot; verify no duplicate balance+marker commit and document the expected possibility of losing not-yet-saved session rewards.
9. Long sessions and full servers; measure DataStore request budget, save queue delay, loop CPU, and bounded per-player state.

The map is unfinished, so this code is intentionally inactive until the actual dance-floor BasePart(s) receive the documented CollectionService tag. No map geometry was invented or modified.

## ReceiptProcessor example — retained single authority and acceptance coverage

The supplied ReceiptProcessor.server.lua example was reviewed but was not installed. Its in-memory ProcessedReceipts table and second MarketplaceService.ProcessReceipt assignment would weaken the existing implementation.

- The existing controller remains the sole intended ProcessReceipt owner and delegates to ClubMusicSecurityCore.ReceiptAuthority.
- ReceiptAuthority already validates safe-integer PlayerId/ProductId and bounded PurchaseId, resolves products through the server-owned PRODUCT_MAP, excludes concurrent callbacks for the same purchase, caps in-flight handlers at 64, and uses a 512-entry session fast-path cache.
- The existing per-profile durable receipt journal and separate global XP receipt journal remain authoritative. Cache eviction does not remove durable receipt history.
- Missing player/profile, unknown product, malformed identity, capacity pressure, concurrent duplicate, DataStore failure, and handler errors remain retryable as NotProcessedYet. Only a completed authoritative transaction returns PurchaseGranted.
- No new receipt table, ProductId, currency grant, remote, client purchase authority, or callback assignment was added. Client purchase-prompt telemetry remains diagnostic only.

### ReceiptProcessor acceptance tests still required

1. Static search of the actual deployed hierarchy for every MarketplaceService.ProcessReceipt assignment; verify only the main controller owns it.
2. Execute the matching Security Core installer and controller together in a disposable Studio universe; confirm ReceiptAuthority loads and its status endpoint reports Ready.
3. Deliver the same PurchaseId sequentially and concurrently, including after the 512-entry cache evicts it; verify exactly one durable grant.
4. Deliver malformed metadata and unknown ProductIds; verify no reward and a retryable result.
5. Test missing player/profile, profile lock contention, DataStore budget exhaustion, and transient failure at each Prepared/apply/Completed/pending-marker-clear boundary.
6. Interrupt/restart after receipt preparation and after durable profile reward application; rejoin and verify recovery grants exactly once.
7. Test all configured donation products, both global XP products, and title slots 2/3; verify exact existing reward amounts and global XP journal compatibility.
8. Test 64-handler saturation and distinct concurrent receipts without starving moderation, security recording, profile recovery, or other essential operations.
9. Spoof client purchase prompt telemetry; verify it changes only bounded diagnostics and never grants a product or pass.
10. Verify no new ReceiptProcessor.server.lua is installed alongside the existing controller.

## Verification update for the script-example implementation

- Dance Floor reward logic and profile marker were added to the tracked controller source in commit a2f8a8271b23be1b326051c4d136f743518f3cbd; follow-up commits e042cf625432e9a77e4455bd6c422134f6adc96d and d3ed2d3b599870f6acc5bd1e871b0f95fd230a35 preserve the AFK timer across respawns and clarify the persistence guarantee.
- ReceiptAuthority and the existing durable receipt transaction handlers were source-reviewed and intentionally left intact; the example's duplicate callback and in-memory receipt cache were not copied.
- Source changes are static repository work only. No Luau parser, Roblox Studio runtime, live DataStore, live Marketplace catalog, or published-server test was available.
- The feature branch remains unmerged and unpublished. The live Roblox place and production player data are unchanged.


## Phase 33 completion — receipt transaction ownership

- Added `ClubMusicSecurityCore/ReceiptTransactionService.lua` for the profile-backed `ClubMusic_ProductReceipts_v1` journal, pending marker recovery, session-lock checks, and per-profile write-lock coordination.
- Moved the unchanged SHA-256 key derivation implementation to `ClubMusicSecurityCore/ReceiptHash.lua`; both the controller adapter and Global Service now load this Security Core module.
- Removed the controller's old `persistReceipt` / `recoverPendingProductReceipt` implementation and receipt-memory cache tables. The controller now delegates commit/recovery and profile-memory reconciliation to `ReceiptTransactionService`.
- Removed root-level `ClubMusic_ReceiptHash.lua` from the repository after migrating both consumers.
- Preserved all durable store names, key formats, full PurchaseId collision comparisons, profile schema markers, legacy profile receipt map compatibility, XP receipt journal compatibility, and reward/product mappings.
- Updated the Security Core installer module list and release pin to include both new modules.

The controller still contains the product allowlist and game-specific reward/presentation adapter; this is not a second receipt processor. There remains exactly one `MarketplaceService.ProcessReceipt` assignment. The global XP receipt journal remains in the Global Service and is not duplicated in Security Core.

Static source migration is complete; Studio and published test-server purchase/recovery verification remain outstanding.
