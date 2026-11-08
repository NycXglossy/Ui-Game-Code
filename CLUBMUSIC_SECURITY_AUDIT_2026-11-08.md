# ClubMusic Security and Integration Audit — 2026-11-08

## Scope

Reviewed the current `main` branch scripts:

- `UI_Server_Controller_server (1).lua`
- `ClubMusic_Global_Service_server_1.lua`
- `UI_Network.lua`
- `UI_Renderer (2).lua`
- `ClubMusicBootstrap.client.lua`
- `ClubMusic_Overhead_Title_Renderer_client.lua`

The working changes are on `audit/hardened-clubmusic-2026-11-08`. The `main` branch was not modified.

## Changes made on the audit branch

1. **Restart-safe global event attachment**
   - Removed the persistent `ClubMusicControllerConnected` attribute as the connection guard.
   - A restarted controller now uses its own connection table and can attach to the existing global BindableEvent again.

2. **Profile lease safety on player departure and shutdown**
   - The controller now releases a profile session lease only after `saveProfile` confirms the final save.
   - When the final save fails, the lease is left to expire naturally instead of immediately allowing another server to load a possibly stale profile.
   - The saved profile snapshot clones `ownedTags` and `favorites` before the yielding DataStore operation.

3. **Fail-closed global request moderation**
   - A global request block is applied locally before persistent storage is attempted.
   - A failed global block save is reported as a local-only restriction, not falsely reported as a global success.
   - A failed global unblock leaves the player blocked rather than silently removing the local restriction.

4. **Bounded cross-server fallback memory**
   - Local fallback token buckets now have idle pruning and a hard 2,048-key cap.
   - Diagnostic signal aggregation now has a hard 2,048-key cap.

5. **Shared DataStore operation budget**
   - Global moderation reads and writes now consume the shared DataStore budget.
   - If the shared budget is unavailable, moderation reads/writes fail closed instead of bypassing the global limiter.

## Architecture and compatibility findings

- The renderer's action names are aligned with the network facade and the server controller's action handlers.
- The renderer and network facade contain no DataStore calls.
- The bootstrap loads `UI_Network` and `UI_Renderer` as ModuleScripts and expects the server controller to create `ReplicatedStorage.ClubMusicRemotes`.
- The overhead title renderer reads server-published Player attributes. It does not authorize or save title changes.
- The server controller is the authority for ranks, pass ownership, queue actions, title filtering, profile data, and developer-product receipts.
- Cross-server DJ skip/clear notifications use MessagingService, which is best-effort rather than a durable synchronized queue. This implementation is not a globally synchronized music playback queue.

## Important configuration before live release

- Replace the zero Game Pass IDs in the server controller:
  - `VipGamePassId`
  - `VvipGamePassId`
  - `TikiTideSultanPassId`
- Replace the zero Developer Product IDs in `PRODUCT_IDS` and `TitleSlotProductIds` with real, unique IDs.
- Set the correct `GroupId`, rank thresholds, and `StaffUserIds`.
- Decide whether `RestrictAudioToAllowlist` should be enabled and populate `AllowedAudioAssetIds` if so.
- Keep `StudioUseDataStore = false` for session-only Studio profile tests unless DataStore API access is intentionally enabled.
- `ClubMusic_Global_Service_server_1.lua` has `EnableInStudio = false` by default. Cross-server services are intentionally disabled in Studio unless deliberately enabled for a controlled test.

## Integrated XP progression and global boosts

The audit branch now includes:

- Persistent per-player XP in the existing profile DataStore.
- Server-awarded 10 base XP for each full minute actually spent in the server after a profile loads.
- 100 XP per level, with XP, level, and next-level attributes/state replicated to the player's UI.
- A new **XP & Boosts** renderer tab.
- A 2x XP Developer Product (15 minutes) and a 4x XP Developer Product (30 minutes).
- Cross-server boost timers stored in the existing global control DataStore key `globalXPBoost_v1`.
- Separate 2x and 4x timers are preserved; the effective rate can step from 4x back down to an active 2x timer.
- XP is accrued by weighted elapsed seconds, retaining fractional XP and splitting accrual at known boost-expiry boundaries. A boost change settles the prior interval before the new multiplier is applied.
- MessagingService publishes prompt boost-state changes to live servers. A staggered 45–60 second durable DataStore refresh reconciles missed messages without every server polling every 15 seconds.
- XP boost PurchaseIds are recorded in the separate `ClubMusic_XPBoostReceipts_v1` DataStore, one small durable record per purchase. The shared timer update and its `pendingReceipt` marker are committed in the same `UpdateAsync`; recovery completes an interrupted journal without extending the timer twice.
- XP boost receipts bypass the player-profile receipt map because the global purchase journal is authoritative for that product type. Existing legacy receipt entries in the old global timer record and legacy per-purchase journal keys are still recognized.
- All non-XP Developer Products now use the shared `ClubMusic_ProductReceipts_v1` DataStore. Each purchase gets a compact record keyed by a SHA-256-derived 160-bit suffix over UserId plus PurchaseId, with the complete PurchaseId, user ID, and product ID stored and compared to detect key collisions. The profile's legacy `receiptIds` map is preserved and checked for old receipts but no longer grows with new purchases.
- For non-XP products, the profile reward and `pendingReceipt` marker are committed together in one profile `UpdateAsync`. The receipt journal is then marked Completed and the pending marker is cleared. A retry first recovers any pending transaction; a crash between those steps cannot cause the reward to be applied a second time.
- Added `ClubMusic_ReceiptHash.lua`, a server-only SHA-256-derived key helper. Both server scripts require it from `ServerStorage`; it must not be replicated to clients.
- Studio test purchases use session-only boost state because cross-server services are disabled by default in Studio.

Configuration required before purchases work:

- Set `CONFIG.XPBoost2xProductId` and `CONFIG.XPBoost4xProductId` in the server controller to two distinct, real Developer Product IDs.
- Keep `0` until the products are created; the UI intentionally refuses to prompt an unconfigured product.
- Keep the global service enabled in live servers. The global service remains disabled in Studio by default.
- XP profiles in Studio memory mode do not persist after the Studio server session.

The existing `ClubMusic_Overhead_Title_Renderer_client.lua` is already present on this branch. It consumes server-published title attributes and supports fixed, RGB, gradient, rainbow, two-tone, and shimmer effects. It was retained rather than duplicated.

## XP boost corrections applied on the audit branch

The earlier XP receipt and accrual findings have been corrected in the current branch version:

1. Removed the 2,500-entry cap from the global XP boost receipt map for new purchases. New purchases use per-PurchaseId journal keys instead of growing a single shared DataStore value. Existing `globalXPBoost_v1` timers and legacy receipt entries are retained.
2. Added a durable `Prepared`/`Completed` per-purchase journal and an atomic `pendingReceipt` marker alongside the timer extension. If a server stops between the timer update and journal completion, the next retry recovers the pending transaction before another receipt can be applied.
3. Removed the 2,500-entry profile receipt cap as an active limit. New donation, item, and title-slot receipts use per-user receipt journals with collision-checked hashed keys and recoverable profile pending markers. The old `receiptIds` table remains for compatibility with previously granted purchases but is not expanded by new purchases.
4. Replaced whole-minute/current-multiplier awarding with weighted elapsed-time accrual. The controller settles the previous rate before switching multipliers and handles the 4x-to-2x fallback when both timers overlap.
5. Added cross-server XP boost notifications and a staggered DataStore reconciliation fallback. The renderer/network remote contract is unchanged; the existing state snapshot is published immediately on a received boost update.

The XP journal now uses keys prefixed with `xph_` plus a 160-bit SHA-256-derived suffix, and accepts PurchaseIds up to 128 bytes. The full PurchaseId is stored in the journal and compared on every read/update; identity mismatches fail closed. Existing legacy `xpr_<PurchaseId>` keys are checked and recovered before new hashed records are created. The non-XP shared journal uses the same hash helper with a distinct `r_` prefix. This avoids key-length restrictions and reduces DataStore value growth without silently pruning idempotency records.

## Studio DataStore error investigation

## Studio DataStore error investigation

The current repository's `UI_Renderer (2).lua` has no references to `DataStoreService`, `GetDataStore`, `GetAsync`, `SetAsync`, or `UpdateAsync`. Its line 308 is a text-stroke color assignment in the title preview helper, not a DataStore operation.

Therefore, an error reporting **“DataStore can't be accessed from client”** at `ReplicatedStorage.UI_Renderer`, line 308, does not match the current GitHub renderer source. The copy installed in Studio is different/stale, or another client-side module/script is involved. Re-copy the current renderer from this repository and search every LocalScript/ModuleScript required by client scripts for DataStore service access. DataStore access must remain in server Scripts.

## Remaining validation

- These are source-level changes and review findings only.
- No Roblox Studio multiplayer session, live DataStore, Marketplace receipt, MemoryStore, MessagingService, or exploit-client test was run.
- Before publishing, test at least: Studio session-only profiles; live profile join/save/rejoin; failed DataStore save and lease expiry; duplicate and retry receipts; staff moderation persistence failure; global request-lock recovery; player respawn and title rendering; and two-server message delivery.
- Do not treat this report as a claim that Roblox runtime behavior has been verified.

