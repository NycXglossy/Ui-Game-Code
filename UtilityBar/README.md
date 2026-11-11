# Utility Bar — Phase 1

A standalone, responsive utility launcher for the experience. It is intentionally separate from ClubMusic playback, queue, DJ, catalog, and music networking.

## Install

1. Add `UtilityBar.client.lua` as a **LocalScript** under `StarterPlayer > StarterPlayerScripts`.
2. Keep exactly one copy of this LocalScript.
3. Keep the existing ClubMusic renderer and compact HUD as the owners of their current UI state.
4. Keep the Sultan Settings client installed separately. The Sultan button requests its panel through the `SultanSettingsOpenRequest` PlayerGui attribute.

## Included buttons

- Refresh Outfit
- Sultan Settings
- Mount
- Size
- Clone
- Aura
- Inventory

The bar uses the ClubMusic dark-surface / muted-gold / teal visual language, fully rounded surfaces, viewport-aware sizing, horizontal scrolling on narrow screens, and controller focus navigation. It hides while `PlayerGui.ClubMusicMenuExpanded` or `PlayerGui.SultanSettingsOpen` is true, then returns when those surfaces close.

## Independent utility action contract

For actions other than Sultan Settings, the bar fires the local BindableEvent:

`PlayerGui.UtilityBarAction:Fire(actionName)`

Action names are `RefreshOutfit`, `Mount`, `Size`, `Clone`, `Aura`, and `Inventory`.

A separate client utility module can subscribe with:

```lua
local player = game:GetService("Players").LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local actionEvent = playerGui:WaitForChild("UtilityBarAction")

actionEvent.Event:Connect(function(actionName)
	if actionName == "Mount" then
		-- Open or toggle the independent Mount utility.
	end
end)
```

Phase 1 provides the launcher and dispatch contract only. It does not pretend that the six non-Sultan utilities are implemented: their independent modules must subscribe to the event before those buttons perform their respective game actions. The bar itself does not create remotes, alter server permissions, or call ClubMusic playback APIs.

## Validation

- [ ] Install once and verify seven buttons appear in the bottom utility rail.
- [ ] Open the full ClubMusic menu; verify the utility rail hides and returns on close.
- [ ] Open Sultan Settings; verify the rail hides and returns on close.
- [ ] Test touch, mouse, keyboard, and D-pad / thumbstick navigation.
- [ ] Test narrow mobile viewport and landscape rotation; verify horizontal scrolling works without clipping.
- [ ] Confirm utility clicks fire the documented local event and do not issue music requests.
