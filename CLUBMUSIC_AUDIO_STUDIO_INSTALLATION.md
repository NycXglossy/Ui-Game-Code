# ClubMusic Audio Module Installation Packages

Branch: `audit/hardened-clubmusic-2026-11-08`

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
This package installs the modules as separate ModuleScripts. It does not enable the modern shared playback backend or complete the controller/client wiring. Keep `ServerMusicSound`, `MusicGroup`, and the existing playback path unchanged. Do not require or activate crossfade, spatial routing, DJ handoffs, quality profiles, or local preferences until the controller integration and Studio/multiplayer validation are completed.

The server folder must stay in ServerStorage. Do not put server-only modules in ReplicatedStorage. Only `ClubMusicPlayerPreferences` is intended for client-side use.

No Roblox Studio runtime or multiplayer test is represented by this package.
