# Phase 33 — Complete Developer Product Receipt Migration

## Objective

Retire the controller-owned durable receipt journal implementation and consolidate receipt ingress, transaction journaling, recovery, and receipt key hashing under ClubMusic Security Core without changing purchase IDs, DataStore names, journal keys, profile schema, reward mappings, or cross-server XP boost behavior.

## Resulting ownership

| Responsibility | Owner |
|---|---|
| Roblox ProcessReceipt assignment | Single adapter in UI_Server_Controller |
| Receipt payload validation and product resolution | ClubMusicSecurityCore.ReceiptAuthority |
| Same-server in-flight exclusion and bounded acknowledgement cache | ClubMusicSecurityCore.ReceiptAuthority |
| Profile-backed durable receipt journal | ClubMusicSecurityCore.ReceiptTransactionService |
| Pending profile receipt recovery and in-memory reconciliation | ClubMusicSecurityCore.ReceiptTransactionService |
| SHA-256 receipt journal key derivation | ClubMusicSecurityCore.ReceiptHash |
| Product allowlist and game-specific reward mutators | UI_Server_Controller adapter |
| Global XP boost transaction and shared timer | ClubMusic_Global_Service |

The controller's remaining callback is an adapter, not a parallel receipt system. There is exactly one ProcessReceipt assignment. The Global Service retains its XP boost journal because it atomically coordinates cross-server boost state.

## Preserved compatibility

- Profile journal DataStore remains `ClubMusic_ProductReceipts_v1`.
- Profile journal keys remain `r_` plus the first 160 bits of the SHA-256 digest of `userId .. ":" .. PurchaseId`.
- The full PurchaseId, UserId, and ProductId remain stored and compared in the journal record.
- Journal states remain `Prepared` and `Completed`.
- Reward mutation and `pendingReceipt` remain committed together in the profile UpdateAsync.
- Journal completion and pending-marker cleanup remain prerequisites for PurchaseGranted.
- Profile session-lock ownership and the existing per-user writer lock remain enforced.
- Existing legacy `receiptIds` profile values are preserved during saves; they are not deleted or rewritten.
- Global XP receipt DataStore remains `ClubMusic_XPBoostReceipts_v1`; `xph_` keys, legacy `xpr_` keys, and the legacy shared `receipts` map remain readable.
- Donation, item, title-slot, and XP boost product mappings and reward amounts are unchanged.
- Studio's existing session-only XP boost behavior remains a Studio-only exception.

## Source changes

- Added `ClubMusicSecurityCore/ReceiptTransactionService.lua` to own the profile journal and recovery logic.
- Added `ClubMusicSecurityCore/ReceiptHash.lua` with the exact prior SHA-256 implementation and output format.
- Updated the controller to inject profile/session adapters and delegate durable commits, recovery, pending-memory checks, and profile cleanup to ReceiptTransactionService.
- Removed the controller's old `persistReceipt` and `recoverPendingProductReceipt` functions and its receipt-memory cache tables.
- Updated the Global Service to load ReceiptHash from Security Core.
- Deleted root-level `ClubMusic_ReceiptHash.lua` after migrating both consumers.
- Updated the Security Core installer module list and pinned release snapshot to include ReceiptHash and ReceiptTransactionService.
- Updated Phase 5 and Phase 29 documentation to describe the completed migration.

## Failure behavior

- Missing or invalid Security Core receipt modules leave receipts retryable; there is no unprotected fallback grant path.
- Storage budget exhaustion, profile lock contention, journal mismatch, incomplete writes, and transaction errors return NotProcessedYet.
- The bounded in-memory cache remains an optimization only. Durable journals remain authoritative after cache eviction or server restart.
- The migration adds no receipt remotes, client purchase authority, MemoryStore reservation, diagnostics telemetry, or cross-server receipt cache.

## Required validation before production installation

Run in a disposable Studio universe with test DataStores, then in a published test place:

1. Confirm exactly one MarketplaceService.ProcessReceipt assignment exists.
2. Confirm ReceiptAuthority, ReceiptTransactionService, and ReceiptHash load from the installed Security Core folder.
3. Test every configured donation, 2x/4x XP boost, and title-slot product.
4. Replay identical receipt callbacks and confirm exactly one reward.
5. Force failures at journal prepare, profile UpdateAsync, journal completion, and pending-marker cleanup; verify Roblox retries and recovery completes without duplicate rewards.
6. Disconnect/rejoin during a pending receipt and verify the profile reward and journal reconcile correctly.
7. Test XP boost retries and duplicate PurchaseIds across two servers; verify the shared boost timer extends once and legacy key formats remain readable.
8. Test profile save and player departure while a receipt is pending; verify the in-memory profile is not overwritten by stale state.
9. Verify unknown ProductIds, malformed receipt payloads, and concurrency saturation never grant.
10. Confirm the status BindableFunction reports both ingress and transaction service states as Ready.

## Release status

Source migration is committed on `phase13.1-adaptive-load-integration`. This is not a production deployment or runtime certification. Do not remove existing DataStores, profile receipt fields, old journal records, or legacy XP compatibility reads. No live Roblox place has been changed.
