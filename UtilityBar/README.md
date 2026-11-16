# Utility Bar — Phases 1–9

A standalone, responsive utility launcher for the experience. It is intentionally separate from ClubMusic playback, queue, DJ, catalog, and music networking.

## Install

1. Add `UtilityBar.client.lua` as a **LocalScript** under `StarterPlayer > StarterPlayerScripts`.
2. Add `UtilityBarActions.client.lua` as a second **LocalScript** under `StarterPlayer > StarterPlayerScripts`.
3. Add `UtilityBarPanels.client.lua` as a third **LocalScript** under `StarterPlayer > StarterPlayerScripts`.
4. Add `ToolShop.client.lua` as a fourth **LocalScript** under `StarterPlayer > StarterPlayerScripts`.
5. Add `UtilityBarActions.server.lua` as a **Script** under `ServerScriptService`.
6. Add `UtilityBarExtendedActions.server.lua` as a second **Script** under `ServerScriptService`.
7. Add `ToolShop.server.lua` as a third **Script** under `ServerScriptService`.
8. Keep exactly one copy of each Utility Bar script.
9. Keep the existing ClubMusic renderer and compact HUD as the owners of their current UI state.
10. Keep the Tiki Tide Settings client installed separately. The Tiki Tide button requests its panel through the existing settings-open request attribute.

## Included buttons

- Refresh Outfit
- Tiki Tide Settings
- Mount
- Size
- Clone
- Aura
- Inventory (includes Tool equip/unequip)
- Tool Shop (separate placeholder storefront)
- Lighting Control (requires Stage & Club Lighting Game Pass)

The bar uses the ClubMusic dark-surface / muted-gold / teal visual language, fully rounded surfaces, viewport-aware sizing, horizontal scrolling on narrow screens, and controller focus navigation. It hides while the full ClubMusic menu or Tiki Tide Settings is open, then returns when those surfaces close. The Tiki Tide Settings panel uses the shared `TikiTideSettingsOpen` state attribute.

## Independent utility action contract

For actions other than Tiki Tide Settings, the bar fires the local BindableEvent:

`PlayerGui.UtilityBarAction:Fire(actionName)`

Action names are `RefreshOutfit`, `Mount`, `Size`, `Clone` (Clone Companion), `Aura`, `Inventory`, `LightingControl`, and `ToolShop`. The Tool Shop panel listens directly for `ToolShop`; Inventory remains the only owned-Tool equip/unequip surface. Legacy `Tools` requests are routed to the unified Inventory view.

### Implemented: Inventory and Tools

- **Inventory:** includes every Tool in the Backpack and currently equipped Tools in one list. Selecting a Tool equips it; selecting an equipped Tool unequips it. The separate Tools launcher button has been removed so Tool management lives in one place.

### Implemented: Refresh Outfit

The `UtilityBarActions.client.lua` module listens for `RefreshOutfit` and invokes the server-owned `ReplicatedStorage.UtilityBarRemotes.RefreshOwnAvatar` RemoteFunction. The server fetches the requesting player's own current Roblox avatar description and applies it to that player's current Humanoid. Requests are rate-limited per player and the server does not accept a target UserId or arbitrary appearance payload from the client.

This refreshes the player's current Roblox account avatar; it is not an outfit catalog or saved-outfit picker. Changing to a different outfit requires a separate approved outfit-selection flow.

### Implemented: Mount, Size, Clone, and Aura

The `UtilityBarExtendedActions.server.lua` script owns Mount, Size, Clone Companion, Aura, and Lighting Control through the allowlisted `UtilityBarRemotes.ExecuteUtility` RemoteFunction. The server validates each request, checks pass entitlements for paid features, applies a per-player cooldown, and limits lighting changes to explicitly tagged stage/club fixtures.

- **Mount:** requires Game Pass `2087955619`, then opens its own panel and equips or unequips only a mount Tool already in the player's Backpack or Character. The Tool must be named `Mount` / `MountTool` or have the `UtilityMount` attribute set to true. The actual mount behavior and assets belong to that Tool.
- **Size:** opens its own control panel with a 0.50×–5.00× adjustable slider and a 1.00× reset. The server strictly validates the requested range and applies values relative to the character's captured R15 baseline; out-of-range values are rejected and R6 avatars receive a clear unsupported message.
- **Clone Companion:** requires Game Pass `2088585676`, then opens its own panel and creates a temporary non-interactive character companion for 12 seconds. The server creates a non-interactive, non-colliding visual copy that follows beside the player and automatically removes it after 12 seconds. Repeated requests replace the player's previous clone.
- **Aura:** opens three style tabs (Teal Glow, Royal Gold, Tiki Tide) and three target tabs (Character, Tools, Accessories). Apply uses server-owned Highlights; Clear Aura removes the active effect. Newly equipped Tools and Accessories receive the selected aura while it remains active.

Mount requires an existing mount Tool; this update does not invent or import a third-party mount model. The extended actions are separate from ClubMusic and do not issue music, queue, catalog, or DJ requests.

### Security and lifecycle

- The server accepts only the explicit action names (`Mount`, `Size`, `Clone`, `Aura`, `ClearAura`, and `LightingControl`); clients cannot supply target players, asset IDs, or arbitrary instances, and size values are clamped server-side.
- Requests are throttled per player on the server.
- Size values outside 0.50×–5.00× are rejected and accepted values are based on each character's captured baseline.
- The Size action is self-only; the server derives the target from the invoking Player and registers the applied BodyScale with the shared server-local `TikiTideMovementAuthority` ledger when the Kohl's security add-on is installed.
- Clone scripts are removed and its parts cannot collide, touch, or be queried; clones expire automatically and are cleaned up when their owner leaves.
- Aura instances are tracked per player and cleared when the player clears the effect, changes character, or leaves.
- Refresh Outfit remains independently server-authoritative with its own cooldown.

## Shared SecurityCore integration

Install `RegularCommandsSecurityServer.lua` as a **ModuleScript** in `ServerScriptService > Kohl's Admin > Addons`. Keep the existing `KohlsAdmin_ClubMusic_Addon` installed separately. The new server-only add-on uses Kohl's `Process.addCommandFilter` enforcement API, checks the existing Tiki Tide server-side `GlobalModeration` / `GlobalConfig` permissions, and writes successful moderation/admin actions to the existing unified SecurityCore Audit API. It does not edit Kohl's core modules or create another MemoryStore map.

The integration covers the exported built-in ban/unban, kick, mute/unmute, punish/unpunish, kill/hurt/health, stun/unstun, blind/unblind, movement, teleport, server-lock, shutdown, and global-command paths. Kohl's native role checks, target-rank checks, ban storage, and request flow remain in place. The built-in `crash` and `loopkill` commands are blocked by the security filter.

The Utility Bar Size button remains an ordinary self-service feature; it does not require an admin role or a Game Pass. Its server-side size change registers with the same movement authority ledger so a future CharacterPhysicsGuard can distinguish authorized resizing from suspicious changes. The ledger is local to each server and creates no DataStore or MemoryStore records.

## Validation

The repository-side integration audit and static contract checks are complete. The checklist below is the remaining Roblox Studio runtime validation; GitHub edits cannot simulate live Roblox input, character physics, DataStore availability, or cross-device rendering, so do not treat unchecked items as runtime-tested.

- [ ] Install all four client LocalScripts and all three server Scripts once; verify nine buttons appear in the bottom utility rail. Open Inventory and verify Backpack/equipped Tools can be equipped and unequipped from the same list.
- [ ] Open Tool Shop; verify its separate panel appears, the coin balance loads from the server, and three Coming Soon placeholders display without purchase controls.
- [ ] Verify Mount, Clone Companion, Lighting Control, Size and Aura open their separate panels only for players who own the matching passes; verify the lighting presets affect only tagged stage/club fixtures.
- [ ] Open the full ClubMusic menu; verify the utility rail hides and returns on close.
- [ ] Open Tiki Tide Settings; verify the rail hides and returns on close.
- [ ] Test touch, mouse, keyboard, and D-pad / thumbstick navigation.
- [ ] Test narrow mobile viewport and landscape rotation; verify horizontal scrolling works without clipping and the Inventory, control-panel, and Tool Shop surfaces remain within the touch viewport.
- [ ] Confirm utility clicks fire the documented local event and do not issue music requests.
- [ ] Install both server Scripts and verify Refresh Outfit updates only the requesting player's avatar.
- [ ] Verify the Mount pass gate, then confirm Mount equips only a tagged/named mount Tool and reports clearly when none is installed.
- [ ] Verify Size applies only to the requesting player, accepts 0.50×–5.00×, rejects values outside that range, restores the captured baseline, registers BodyScale authority, and safely rejects R6.
- [ ] Install `RegularCommandsSecurityServer.lua` as a Kohl's Admin server add-on; verify unauthorized moderation commands are denied, authorized ban/kick/mute actions still use Kohl's native handlers, successful actions appear in the unified SecurityCore Audit, and `crash` / `loopkill` are blocked.
- [ ] Verify `:gravity`, `:starterspeed`, `:serverlock`, `:unserverlock`, `:shutdown`, and `:global` require the owner/co-owner SecurityCore permission.
- [ ] Verify the Island Companion pass gate, then confirm Clone Companion is non-interactive, expires after 12 seconds, and is cleaned up on leave.
- [ ] Verify Lighting Control requires its pass and its presets/restore action affect only StageClubLight-tagged fixtures.
- [ ] Verify Aura applies each style/target combination, Clear Aura removes it, and character respawn/leave cleans up effects.
- [ ] Verify repeated refresh requests are throttled and failed avatar lookups show a safe message.


### Tool Shop and Coins foundation

- **Tool Shop** is a separate utility-bar tab. It does not replace or modify Inventory. Inventory remains the only place for equipping and unequipping owned Tools.
- The shop intentionally displays three **COMING SOON** placeholder slots. No Tool assets, item names, prices, or purchase buttons have been invented or configured.
- `ToolShop.server.lua` creates `leaderstats.Coins` when it does not already exist as an IntValue and persists the balance in the `TikiTideCoins_v1` DataStore. The starting balance is deliberately `0` in the script's `STARTING_COINS` setting; change it only when the game's launch economy is decided.
- Enable **Game Settings → Security → Enable Studio Access to API Services** for Studio DataStore testing. Published experiences need DataStore access enabled. Test persistence in a separate test place before release.
- Server-side reward systems can award currency by changing the player's `leaderstats.Coins.Value` from server code. Never award Coins from a LocalScript or accept a client-supplied balance.
- When real stock is ready, place approved Tool assets in `ServerStorage.UtilityToolShop` and define server-owned prices/descriptions. A later shop-stock phase must add purchase validation, ownership persistence, and respawn re-granting before enabling Buy buttons; this placeholder phase does not sell anything.
- The shop RemoteFunction currently supports read-only `GetShop` requests. It exposes no client-side currency mutation or purchase operation.

### Pass-gated features and Stage/Club Lighting

- **Mount** is locked behind Island Mount Game Pass `2087955619`.
- **Clone Companion** is locked behind Island Companion Game Pass `2088585676`.
- **Lighting Control** replaces the former Accessories launcher and is locked behind Stage & Club Lighting Game Pass `2088315619`.
- The server independently checks the entitlement attributes set by the main server controller before executing these actions; a client-side prompt or UI state never grants access.
- Lighting Control only changes fixtures tagged with the CollectionService tag `StageClubLight`. Tag the intended club and stage PointLight, SpotLight, SurfaceLight, or Beam objects (or their containing fixture Models/Parts) in Studio. Untagged island, outdoor, and general Lighting service settings are not changed.
- Lighting presets: Ocean, Sunset, Royal Gold, Tiki, and Restore Original Lighting. If no fixtures are tagged, the panel reports the required tag instead of changing unrelated lights.
