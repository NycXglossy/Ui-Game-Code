# ClubMusic Audio Module Installation Packages

Branch: `feature/sultan-settings-2026-11-10`

## Package files
- `ClubMusic_Audio_Server_Modules.rbxmx`: five separate server ModuleScripts.
- `ClubMusic_Audio_Client_Modules.rbxmx`: one separate client ModuleScript.

## Install
1. Download each RBXMX file using GitHub's **Raw** view / Download raw file.
2. In Roblox Studio, use **File → Insert from File...** and import the server package.
3. Move the resulting `ClubMusicAudioModules` Folder under `ServerStorage`.
4. Import the client package the same way.
5. Move `ClubMusicClientAudioModules` under `ReplicatedStorage`.
6. Confirm the six children are ModuleScripts with the exact names listed in this package.
7. Save a backup copy of the place before testing.

## Important
This package installs the modules as separate ModuleScripts. On the current integration branch, the server controller discovers `ClubMusicAudioBackend` and `ClubMusicAudioCrossfadeManager` in `ServerStorage.ClubMusicAudioModules` (or directly under `ServerStorage`). When both are present, it initializes the controller-owned crossfade coordinator; automatic queued-track transitions can then use an AudioPlayer incoming deck while the established legacy Sound remains the main playback source.

The main playback migration is still opt-in: `UseModernAudioBackend = false` keeps the canonical track source on the legacy Sound. Do not enable it until the full Studio validation checklist passes. The crossfade manager does not own a separate queue or playback timeline; the server controller remains authoritative for track selection, timing, and queue commits.

Keep `ServerMusicSound`, `MusicGroup`, and the existing playback path in place during validation. The server folder must stay in ServerStorage. Do not put server-only modules in ReplicatedStorage. Only `ClubMusicPlayerPreferences` is intended for client-side use.

This package and its source files are not a substitute for Roblox Studio runtime or multiplayer testing.


## Alternative: Command Bar installer (when RBXMX import is unavailable)

The repository also includes `ClubMusic_Studio_CommandBar_Installer.lua`. This avoids the RBXMX import UI:

1. In Studio, open **Game Settings → Security** and enable **Allow HTTP Requests**.
2. Open **View → Command Bar**.
3. Open the installer Lua file from this repository, copy its entire contents, and paste it into the Command Bar.
4. Run it once. It downloads the six source modules from pinned repository commits and creates the ModuleScripts in the required folders.
5. Confirm the folders and all six ModuleScripts appear in Explorer, then save the place.

The installer stages all six downloads before creating or replacing any ModuleScripts. It only replaces same-named ModuleScripts inside its two dedicated folders; it stops if a conflicting non-ModuleScript object is present. It does not modify the controller, renderer, live playback, `ServerMusicSound`, or `MusicGroup`.

**Important:** this is installation only, not activation. The modern shared playback backend, crossfade, DJ-session handoff UI, local listener routing, and spatial venue routing still require coordinated controller/client integration and Roblox Studio multi-client testing. Keep the legacy playback objects until that work is validated.
