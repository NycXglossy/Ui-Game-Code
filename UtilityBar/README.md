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
- Accessories

The bar uses the ClubMusic dark-surface / muted-gold / teal visual language, fully rounded surfaces, viewport-aware sizing, horizontal scrolling on narrow screens, and controller focus navigation. It hides while the full ClubMusic menu or Tiki Tide Settings is open, then returns when those surfaces close. The Tiki Tide Settings panel uses the shared `TikiTideSettingsOpen` state attribute.

## Independent utility action contract

For actions other than Tiki Tide Settings, the bar fires the local BindableEvent:

`PlayerGui.UtilityBarAction:Fire(actionName)`

Action names are `RefreshOutfit`, `Mount`, `Size`, `Clone`, `Aura`, `Inventory`, and `Accessories`. Legacy `Tools` requests are routed to the unified Inventory view.

### Implemented: Inventory, Tools, and Accessories

- **Inventory:** includes every Tool in the Backpack and currently equipped Tools in one list. Selecting a Tool equips it; selecting an equipped Tool unequips it. The separate Tools launcher button has been removed so Tool management lives in one place.
- **Accessories:** opens a dedicated list of currently equipped character Accessories. This is a view panel; Roblox character Accessories are shown as worn items and are not moved or removed by this panel.

### Implemented: Refresh Outfit

The `UtilityBarActions.client.lua` module listens for `RefreshOutfit` and invokes the server-owned `ReplicatedStorage.UtilityBarRemotes.RefreshOwnAvatar` RemoteFunction. The server fetches the requesting player's own current Roblox avatar description and applies it to that player's current Humanoid. Requests are rate-limited per player and the server does not accept a target UserId or arbitrary appearance payload from the client.

This refreshes the player's current Roblox account avatar; it is not an outfit catalog or saved-outfit picker. Changing to a different outfit requires a separate approved outfit-selection flow.

### Implemented: Mount, Size, Clone, and Aura

The `UtilityBarExtendedActions.server.lua` script owns these actions through the allowlisted `UtilityBarRemotes.ExecuteUtility` RemoteFunction. The client sends only an action name; the server validates the action, applies a per-player cooldown, and operates only on the requesting player's character.

- **Mount:** equips or unequips a mount Tool already in the player's Backpack or Character. The Tool must be named `Mount` / `MountTool` or have the `UtilityMount` attribute set to true. The actual mount behavior and assets belong to that Tool.
- **Size:** opens its own control panel with a 0.50×–5.00× adjustable slider and a 1.00× reset. The server clamps values and applies them relative to the character's captured R15 baseline; R6 avatars receive a clear unsupported message.
- **Clone:** opens its own single-tab panel with a Create Clone action. The server creates a non-interactive, non-colliding visual copy beside the player and automatically removes it after 12 seconds. Repeated requests replace the player's previous clone.
- **Mount:** opens its own single-tab panel with an Equip / Unequip action for the tagged or named mount Tool.
- **Aura:** opens a three-tab style panel: Teal Glow, Royal Gold, and Tiki Tide. Selecting Apply sends the chosen preset to the server, which highlights the character and equipped Tool and Accessory handles. Newly equipped Tools and Accessories receive the active aura automatically.

Mount requires an existing mount Tool; this update does not invent or import a third-party mount model. The extended actions are separate from ClubMusic and do not issue music, queue, catalog, or DJ requests.

### Security and lifecycle

- The server accepts only the four explicit action names; clients cannot supply target players, asset IDs, scale values, or arbitrary instances.
- Requests are throttled per player on the server.
- Size values are clamped to 0.50×–5.00× and based on each character's captured baseline.
- Clone scripts are removed and its parts cannot collide, touch, or be queried; clones expire automatically and are cleaned up when their owner leaves.
- Aura instances are tracked per player and cleaned up when the player leaves.
- Refresh Outfit remains independently server-authoritative with its own cooldown.

## Validation

- [ ] Install all four client LocalScripts and all three server Scripts once; verify nine buttons appear in the bottom utility rail. Open Inventory and verify Backpack/equipped Tools can be equipped and unequipped from the same list.
- [ ] Open Tool Shop; verify its separate panel appears, the coin balance loads from the server, and three Coming Soon placeholders display without purchase controls.
- [ ] Verify Mount, Clone, Size and Aura each open their own separate control panel; verify Aura has three style tabs and three target tabs (Character, Tools, Accessories), and Size has a working 0.50×–5.00× slider with a 1.00× reset.
- [ ] Open the full ClubMusic menu; verify the utility rail hides and returns on close.
- [ ] Open Tiki Tide Settings; verify the rail hides and returns on close.
- [ ] Test touch, mouse, keyboard, and D-pad / thumbstick navigation.
- [ ] Test narrow mobile viewport and landscape rotation; verify horizontal scrolling works without clipping.
- [ ] Confirm utility clicks fire the documented local event and do not issue music requests.
- [ ] Install both server Scripts and verify Refresh Outfit updates only the requesting player's avatar.
- [ ] Verify Mount equips only a tagged/named mount Tool and reports clearly when none is installed.
- [ ] Verify Size cycles on R15, restores the captured baseline, and safely rejects R6.
- [ ] Verify Clone is non-interactive, expires after 12 seconds, and is cleaned up on leave.
- [ ] Verify Aura toggles off and cleans up on leave.
- [ ] Verify repeated refresh requests are throttled and failed avatar lookups show a safe message.


### Tool Shop and Coins foundation

- **Tool Shop** is a separate ninth utility-bar tab. It does not replace or modify Inventory. Inventory remains the only place for equipping and unequipping owned Tools.
- The shop intentionally displays three **COMING SOON** placeholder slots. No Tool assets, item names, prices, or purchase buttons have been invented or configured.
- `ToolShop.server.lua` creates `leaderstats.Coins` when it does not already exist as an IntValue and persists the balance in the `TikiTideCoins_v1` DataStore. The starting balance is deliberately `0` in the script's `STARTING_COINS` setting; change it only when the game's launch economy is decided.
- Enable **Game Settings → Security → Enable Studio Access to API Services** for Studio DataStore testing. Published experiences need DataStore access enabled. Test persistence in a separate test place before release.
- Server-side reward systems can award currency by changing the player's `leaderstats.Coins.Value` from server code. Never award Coins from a LocalScript or accept a client-supplied balance.
- When real stock is ready, place approved Tool assets in `ServerStorage.UtilityToolShop` and define server-owned prices/descriptions. A later shop-stock phase must add purchase validation, ownership persistence, and respawn re-granting before enabling Buy buttons; this placeholder phase does not sell anything.
- The shop RemoteFunction currently supports read-only `GetShop` requests. It exposes no client-side currency mutation or purchase operation.
