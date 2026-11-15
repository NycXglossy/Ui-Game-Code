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

The main playback migration is enabled: `UseModernAudioBackend = true` makes the controller attempt to adopt the modern AudioPlayer as its canonical source. The reported Studio log `[ClubMusic][AudioBackend] Modern AudioPlayer is now the controller-owned main source.` confirms that the guarded handoff completed. The controller still retains the legacy Sound path as a bounded fallback/recovery route. Keep `ServerMusicSound` and its compatibility wiring until fallback failure recovery has been deliberately tested and retired. The crossfade manager does not own a separate queue or playback timeline; the server controller remains authoritative for track selection, timing, and queue commits.

Keep `ServerMusicSound` as the guarded recovery source and `MusicGroup` for per-player volume preferences. The modern backend is now the primary source, but these compatibility objects are not obsolete while recovery and client gain paths still reference them. The server folder must stay in ServerStorage. Do not put server-only modules in ReplicatedStorage. Only `ClubMusicPlayerPreferences` is intended for client-side use.

This package and its source files are not a substitute for Roblox Studio runtime or multiplayer testing.


## Alternative: Command Bar installer (when RBXMX import is unavailable)

The repository also includes `ClubMusic_Studio_CommandBar_Installer.lua`. This avoids the RBXMX import UI:

1. In Studio, open **Game Settings → Security** and enable **Allow HTTP Requests**.
2. Open **View → Command Bar**.
3. Open the installer Lua file from this repository, copy its entire contents, and paste it into the Command Bar.
4. Run it once. It downloads the six source modules from pinned repository commits and creates the ModuleScripts in the required folders.
5. Confirm the folders and all six ModuleScripts appear in Explorer, then save the place.

The installer stages all six downloads before creating or replacing any ModuleScripts. It only replaces same-named ModuleScripts inside its two dedicated folders; it stops if a conflicting non-ModuleScript object is present. It does not modify the controller, renderer, live playback, `ServerMusicSound`, or `MusicGroup`.

**Important:** the modern shared playback backend and crossfade are integrated, and the reported controller-owned-source log confirms successful handoff in Studio. This does not by itself prove every multi-client, failure-recovery, or device-routing regression gate. Do not remove the legacy fallback objects yet: `ServerMusicSound` remains in the controller's recovery and transition fallback paths, while `MusicGroup` remains in the client volume-preference path. DJ-session handoff UI, local listener routing, and spatial venue routing remain separate future integration work.
