# UI Renderer Compatibility & Integration Consolidation

Base: `UI_Renderer (2).lua` at commit `70fd8247cdf90d5d22cc942b158556d1fc0406cb`.

This branch is a consolidated snapshot of the unified Tiki Tide branch, with an integration inventory for the renderer and its compatibility/bridge scripts. It does not merge the older `phase0-33-performance-compatibility` branch because that branch is 35 commits behind and would risk reverting newer UI and project work.

## Renderer placement and direct entry point

- **Module:** `UI_Renderer (2).lua` → `ReplicatedStorage/UI_Renderer` (ModuleScript).
- **Direct mount caller:** `ClubMusicBootstrap.client.lua` → StarterPlayerScripts. It waits for `ReplicatedStorage.UI_Renderer`, requires it, validates `Renderer.Mount`, and calls `Renderer.Mount(player, Network)`.
- **Network adapter:** `UI_Network.lua` → the bootstrap's network adapter passed to `Renderer.Mount`. It supplies state/actions expected by the renderer and aligns action payloads with server handling.
- **Server authority:** `UI_Server_Controller_server (1).lua` → ServerScriptService. Handles authoritative requests, state, permissions, and attributes used by the renderer. Client UI is not authority.

## Related caller / bridge / compatibility scripts in this branch

### Main-menu bridge
- `StarterPlayer/StarterPlayerScripts/TikiTideUnifiedLauncher.client.lua`: creates `PlayerGui.TikiTideOpenMainUI` BindableEvent before renderer startup; the renderer binds its `Open` callback and marks the bridge Ready. Launcher uses the bridge to open the main renderer and waits for startup readiness.

### UI visibility and foreground compatibility
- `TikiTideSettings/TikiTideSettings.client.lua`: settings UI publishes its open state through PlayerGui attributes; compatible UI surfaces coordinate visibility/restore state.
- `TikiTideSettings/TikiTideSettingsService.server.lua`: server-side settings requests/remotes and access enforcement; not a renderer mount caller.
- `UtilityBar/UtilityBar.client.lua`: utility launcher and settings entry point; requests Settings via PlayerGui request attributes and coordinates its own visibility. It does not directly require or mount the renderer.
- `UtilityBar/UtilityBarPanels.client.lua`: panel/foreground ownership compatibility for utility panels; does not directly mount renderer.
- `UtilityBar/UtilityBarActions.client.lua`: utility action dispatch and client action bridges; does not directly mount renderer.
- Renderer itself observes the Settings-open state and suppresses/restores compact HUD/menu launcher surfaces as appropriate.

### Other UI-adjacent scripts (not direct renderer callers)
- `TikiTideSocialActions.client.lua` and `TikiTideSocialActions.server.lua`: unified launcher social-action feature, separate from renderer mount.
- `ClubMusic_Client_Diagnostics_Bootstrap.client.lua` and diagnostics scripts: diagnostics/telemetry compatibility; not renderer mount callers.

## Direct-call audit result

At the pinned base revision, the only script that requires and calls `Renderer.Mount` is `ClubMusicBootstrap.client.lua`. The unified launcher calls the renderer through the `TikiTideOpenMainUI` BindableEvent bridge, rather than requiring the module itself. `UI_Network.lua` is the renderer's adapter dependency, not a mount caller.

## Install / dependency checklist

1. Put `UI_Renderer (2).lua` in `ReplicatedStorage` as a ModuleScript named exactly `UI_Renderer`.
2. Install `UI_Network.lua` in the location expected by `ClubMusicBootstrap.client.lua` (the bootstrap resolves its network module).
3. Install `ClubMusicBootstrap.client.lua` in `StarterPlayer/StarterPlayerScripts`.
4. Install the unified launcher and the Settings/Utility compatibility scripts at their documented paths if those UI entry points are wanted.
5. Install `UI_Server_Controller_server (1).lua` in `ServerScriptService` and the renderer's server-side dependencies/remotes.
6. Ensure only one active renderer bootstrap/mount script exists per player. The renderer has mount reuse logic, but duplicate bootstraps can still create duplicate listeners or competing integrations.

## Scope note

This is a source/branch consolidation and integration inventory. Roblox Studio runtime, mobile/desktop foreground behavior, permissions, and live audio were not tested here.
