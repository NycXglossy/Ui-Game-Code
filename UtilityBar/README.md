# Utility Bar — Phase 1

A standalone, responsive utility launcher for the experience. It is intentionally separate from ClubMusic playback, queue, DJ, catalog, and music networking.

## Install

1. Add `UtilityBar.client.lua` as a **LocalScript** under `StarterPlayer > StarterPlayerScripts`.
2. Add `UtilityBarActions.client.lua` as a second **LocalScript** under `StarterPlayer > StarterPlayerScripts`.
3. Add `UtilityBarActions.server.lua` as a **Script** under `ServerScriptService`.
4. Keep exactly one copy of each Utility Bar script.
5. Keep the existing ClubMusic renderer and compact HUD as the owners of their current UI state.
6. Keep the Tiki Tide Settings client installed separately. The Tiki Tide button requests its panel through the existing settings-open request attribute (legacy internal name retained for compatibility).

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

### Still dispatch-only

`Mount`, `Size`, `Clone`, `Aura`, and `Inventory` remain dispatch-only until their independent modules and any required assets or server validation are added.

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

The launcher remains separate from ClubMusic. Refresh Outfit is now connected to its own server-validated avatar refresh service; the five listed dispatch-only actions still need their own modules. The bar itself does not call ClubMusic playback APIs.

## Validation

- [ ] Install once and verify seven buttons appear in the bottom utility rail.
- [ ] Open the full ClubMusic menu; verify the utility rail hides and returns on close.
- [ ] Open Tiki Tide Settings; verify the rail hides and returns on close.
- [ ] Test touch, mouse, keyboard, and D-pad / thumbstick navigation.
- [ ] Test narrow mobile viewport and landscape rotation; verify horizontal scrolling works without clipping.
- [ ] Confirm utility clicks fire the documented local event and do not issue music requests.
- [ ] Install the server Script and verify Refresh Outfit updates only the requesting player's avatar.
- [ ] Verify repeated refresh requests are throttled and failed avatar lookups show a safe message.
