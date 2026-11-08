# ClubMusic XP Progression and Global Boosts — Installation

## Included integration

The branch adds XP and boosts to the existing architecture. Do not install a second profile system or a second `MarketplaceService.ProcessReceipt` handler.

- `UI_Server_Controller_server (1).lua` — authoritative XP awards, profile persistence, and Developer Product receipt handling.
- `ClubMusic_Global_Service_server_1.lua` — persistent cross-server 2x/4x boost state and idempotent receipt activation.
- `UI_Renderer (2).lua` — the **XP & Boosts** page and purchase prompts.
- `UI_Network.lua` and `ClubMusicBootstrap.client.lua` — unchanged; XP is delivered through the existing state snapshot.
- `ClubMusic_Overhead_Title_Renderer_client.lua` — existing overhead title renderer, retained.

## Roblox Studio placement

Use the latest files from this branch. You may rename the files to match these object names when importing:

1. Place `UI_Server_Controller_server (1).lua` as a **Script** named `UI_Server_Controller` in `ServerScriptService`.
2. Place `ClubMusic_Global_Service_server_1.lua` as a **Script** named `ClubMusic_Global_Service` in `ServerScriptService`.
3. Place `UI_Renderer (2).lua` as a **ModuleScript** named `UI_Renderer` in `ReplicatedStorage`.
4. Keep `UI_Network.lua` as a **ModuleScript** named `UI_Network` in `ReplicatedStorage`.
5. Keep `ClubMusicBootstrap.client.lua` as a **LocalScript** in `StarterPlayer/StarterPlayerScripts`.
6. Keep `ClubMusic_Overhead_Title_Renderer_client.lua` as a **LocalScript** in `StarterPlayer/StarterPlayerScripts`.

There must be only one active copy of each controller, global service, bootstrap, and overhead renderer. Do not leave older duplicate scripts enabled.

## Configure Developer Products

In Creator Dashboard, create two distinct Developer Products for this experience. Then set these values near the top of `UI_Server_Controller`:

```lua
XPBoost2xProductId = 0, -- replace with the 2x XP product ID
XPBoost4xProductId = 0, -- replace with the 4x XP product ID
```

Use the actual numeric IDs. Do not reuse a donation, shop, or title-slot product ID. The server rejects duplicate product IDs during startup. A value of `0` disables that purchase prompt.

The controller already owns `MarketplaceService.ProcessReceipt`. Do not create another script that overwrites it. The global service uses a durable per-PurchaseId journal plus an atomic pending marker stored with the existing global timer record. Retries and crash recovery detect an already-applied timer extension before applying it again. New XP boost receipts no longer consume entries in the capped player-profile receipt map.

## XP behavior

- 10 base XP per full minute played after the server successfully loads the player's profile.
- 100 XP per level.
- XP and level are stored in the existing player profile and periodically saved.
- XP is awarded by the server; no client remote accepts an XP amount or playtime value.
- The 2x product adds 15 minutes to the shared 2x timer.
- The 4x product adds 30 minutes to the shared 4x timer.
- The highest currently active multiplier applies to all players in all live servers.
- Separate 2x and 4x timers are retained. A 2x timer resumes after a stronger 4x timer expires if it is still active.
- XP accrues continuously using the multiplier active during each elapsed interval, retaining fractional XP between updates. It does not retroactively apply a newly purchased boost to earlier playtime.
- Cross-server MessagingService notifications update live servers promptly. Staggered DataStore reconciliation is the fallback when a notification is missed.
- The active global timer keeps its existing `globalXPBoost_v1` key. Per-purchase XP receipt records are stored in `ClubMusic_XPBoostReceipts_v1`; this avoids an ever-growing receipt map in the global timer value.

## Studio and live testing

- Studio profile mode is session-only when `StudioUseDataStore = false`.
- Studio uses a local session-only boost timer because `EnableInStudio = false` disables cross-server services by default.
- Live global boosts require the global service and working DataStore/MemoryStore/MessagingService access.
- Publish and test Developer Products in the experience's actual universe; Studio behavior is not proof of live receipt processing.

## Required validation before release

Test in a private published test place with at least two live servers:

1. Join, wait a full minute, verify +10 XP, rejoin, and verify XP persisted.
2. Purchase 2x; verify all players across both servers receive 20 XP per full minute for the active interval.
3. Purchase 4x; verify it overrides 2x while active, then verify any still-active 2x timer resumes.
4. Simulate/retry receipt processing where possible and verify the boost timer extends only once per PurchaseId.
5. Test DataStore outages and confirm XP boost receipts remain unacknowledged until the global per-purchase journal and timer update are durably committed. Player-profile receipt ledger capacity is not part of XP boost acknowledgment.
6. Confirm that overlapping 2x and 4x timers accrue at the correct tier before, during, and after the overlap.
7. Confirm missed MessagingService notifications are reconciled by the staggered DataStore refresh.
8. Confirm no duplicate `ProcessReceipt` handlers or duplicate scripts are running.

## Verification limits

The GitHub source has been updated and statically inspected. It has **not** been executed in Roblox Studio or in published multiplayer servers. Marketplace receipts, DataStore budgets, cross-server synchronization, and visual UI behavior still require the tests above.
