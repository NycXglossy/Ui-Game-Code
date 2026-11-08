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

## Version-parity gap: XP boosts

The current repository does **not** contain the previously discussed 2x XP (15-minute) and 4x XP (30-minute) Developer Product boosts, the playtime XP award loop, or the cross-server persistent boost reconciliation. The controller includes level/rank references, but the requested XP boost feature is not present in these six files. It must be integrated as a separate, explicitly tested feature; this audit branch does not claim it has been added.

## Studio DataStore error investigation

The current repository's `UI_Renderer (2).lua` has no references to `DataStoreService`, `GetDataStore`, `GetAsync`, `SetAsync`, or `UpdateAsync`. Its line 308 is a text-stroke color assignment in the title preview helper, not a DataStore operation.

Therefore, an error reporting **“DataStore can't be accessed from client”** at `ReplicatedStorage.UI_Renderer`, line 308, does not match the current GitHub renderer source. The copy installed in Studio is different/stale, or another client-side module/script is involved. Re-copy the current renderer from this repository and search every LocalScript/ModuleScript required by client scripts for DataStore service access. DataStore access must remain in server Scripts.

## Remaining validation

- These are source-level changes and review findings only.
- No Roblox Studio multiplayer session, live DataStore, Marketplace receipt, MemoryStore, MessagingService, or exploit-client test was run.
- Before publishing, test at least: Studio session-only profiles; live profile join/save/rejoin; failed DataStore save and lease expiry; duplicate and retry receipts; staff moderation persistence failure; global request-lock recovery; player respawn and title rendering; and two-server message delivery.
- Do not treat this report as a claim that Roblox runtime behavior has been verified.

