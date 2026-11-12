# Utility Bar — Phase 1

A standalone, responsive utility launcher for the experience. It is intentionally separate from ClubMusic playback, queue, DJ, catalog, and music networking.

## Install

1. Add `UtilityBar.client.lua` as a **LocalScript** under `StarterPlayer > StarterPlayerScripts`.
2. Add `UtilityBarActions.client.lua` as a second **LocalScript** under `StarterPlayer > StarterPlayerScripts`.
3. Add `UtilityBarActions.server.lua` as a **Script** under `ServerScriptService`.
4. Add `UtilityBarExtendedActions.server.lua` as a second **Script** under `ServerScriptService`.
5. Keep exactly one copy of each Utility Bar script.
6. Keep the existing ClubMusic renderer and compact HUD as the owners of their current UI state.
7. Keep the Tiki Tide Settings client installed separately. The Tiki Tide button requests its panel through the existing settings-open request attribute.

## Included buttons

- Refresh Outfit
- Tiki Tide Settings
- Mount
- Size
- Clone
- Aura
- Inventory

The bar uses the ClubMusic dark-surface / muted-gold / teal visual language, fully rounded surfaces, viewport-aware sizing, horizontal scrolling on narrow screens, and controller focus navigation. It hides while the full ClubMusic menu or Tiki Tide Settings is open, then returns when those surfaces close. The Tiki Tide Settings panel uses the shared `TikiTideSettingsOpen` state attribute.

## Independent utility action contract

For actions other than Tiki Tide Settings, the bar fires the local BindableEvent:

`PlayerGui.UtilityBarAction:Fire(actionName)`

Action names are `RefreshOutfit`, `Mount`, `Size`, `Clone`, `Aura`, and `Inventory`.

### Implemented: Refresh Outfit

The `UtilityBarActions.client.lua` module listens for `RefreshOutfit` and invokes the server-owned `ReplicatedStorage.UtilityBarRemotes.RefreshOwnAvatar` RemoteFunction. The server fetches the requesting player's own current Roblox avatar description and applies it to that player's current Humanoid. Requests are rate-limited per player and the server does not accept a target UserId or arbitrary appearance payload from the client.

This refreshes the player's current Roblox account avatar; it is not an outfit catalog or saved-outfit picker. Changing to a different outfit requires a separate approved outfit-selection flow.

### Implemented: Mount, Size, Clone, and Aura

The `UtilityBarExtendedActions.server.lua` script owns these actions through the allowlisted `UtilityBarRemotes.ExecuteUtility` RemoteFunction. The client sends only an action name; the server validates the action, applies a per-player cooldown, and operates only on the requesting player's character.

- **Mount:** equips or unequips a mount Tool already in the player's Backpack or Character. The Tool must be named `Mount` / `MountTool` or have the `UtilityMount` attribute set to true. The actual mount behavior and assets belong to that Tool.
- **Size:** cycles Small, Large, and Default on R15 avatars. Original body scale values are captured per character and restored for the Default preset. R6 avatars receive a clear unsupported message.
- **Clone:** creates a non-interactive, non-colliding visual copy beside the player and automatically removes it after 12 seconds. Repeated requests replace the player's previous clone.
- **Aura:** toggles a server-created teal-and-gold Highlight on the requesting player's character.

Mount requires an existing mount Tool; this update does not invent or import a third-party mount model. The extended actions are separate from ClubMusic and do not issue music, queue, catalog, or DJ requests.

### Security and lifecycle

- The server accepts only the four explicit action names; clients cannot supply target players, asset IDs, scale values, or arbitrary instances.
- Requests are throttled per player on the server.
- Size values are clamped and based on each character's captured baseline.
- Clone scripts are removed and its parts cannot collide, touch, or be queried; clones expire automatically and are cleaned up when their owner leaves.
- Aura instances are tracked per player and cleaned up when the player leaves.
- Refresh Outfit remains independently server-authoritative with its own cooldown.

## Validation

- [ ] Install once and verify seven buttons appear in the bottom utility rail.
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
