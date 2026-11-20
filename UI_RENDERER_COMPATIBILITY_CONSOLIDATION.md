# Tiki Tide Unified UI, ClubMusic, Diagnostics & Security Consolidation

## Branch foundation

- Branch: `feature/ui-renderer-compatibility-consolidation`
- Renderer foundation: `UI_Renderer (2).lua` at `70fd8247cdf90d5d22cc942b158556d1fc0406cb`.
- This branch is based on the unified Tiki Tide UI/music/social snapshot. The source tree already contains the UI, modern audio, local/global diagnostics, security modules, and utility/settings scripts listed below.
- The older `phase0-33-performance-compatibility` and `audit/hardened-clubmusic-2026-11-08` lines are not blindly merged: they are separate historical lines with divergent versions. The current snapshot is retained as the integration baseline to avoid reverting newer UI/audio work.

## 1. UI renderer and compatibility

- `UI_Renderer (2).lua` → install as `ReplicatedStorage/UI_Renderer` (ModuleScript).
- `UI_Network.lua` → `ReplicatedStorage/UI_Network` (ModuleScript).
- `ClubMusicBootstrap.client.lua` → `StarterPlayer/StarterPlayerScripts` (LocalScript). This is the only direct `Renderer.Mount` caller found in the pinned snapshot.
- `UI_Server_Controller_server (1).lua` → `ServerScriptService/UI_Server_Controller` (Script); authoritative state, permissions, request validation, purchases, queue and audio control.
- `StarterPlayer/StarterPlayerScripts/TikiTideUnifiedLauncher.client.lua` → launcher bridge using `PlayerGui.TikiTideOpenMainUI`.
- `TikiTideSettings/TikiTideSettings.client.lua` and `TikiTideSettings/TikiTideSettingsService.server.lua` → settings client/server integration.
- `UtilityBar/UtilityBar.client.lua`, `UtilityBar/UtilityBarPanels.client.lua`, `UtilityBar/UtilityBarActions.client.lua`, `UtilityBar/UtilityBarActions.server.lua`, and `UtilityBar/UtilityBarExtendedActions.server.lua` → utility launcher, panels, dispatch, and server actions.
- `TikiTideSocialActions.client.lua`, `TikiTideSocialActions.server.lua`, and `TikiTideSocialActions/AnimationConfig.lua` → social action integration.

## 2. Modern ClubMusic audio

The modern audio implementation is present in this snapshot:

- `ClubMusicAudioBackend.luau` — controller-owned modern AudioPlayer graph.
- `ClubMusicAudioCrossfadeManager.luau` — crossfade transition support.
- `ClubMusicAudioQualityProfiles.luau` — audio quality profiles.
- `ClubMusicSpatialAudioGraph.luau` — spatial audio graph support.
- `ClubMusicDJSessionManager.luau` and `ClubMusicPlayerPreferences.luau` — DJ session and listener preference modules.
- `MusicCoreService.lua`, `MusicQueueManager.luau`, `MusicPlaylistService.lua`, `MusicGlobalPlaybackAuthority.lua`, and `MusicValidationService.luau` — music core, queue, playlists, global playback authority, and validation.
- `ClubMusicErrorHandler.lua` — audio error handling.
- `ClubMusic_Global_Service_server_1.lua`, `ClubMusic_Global_Config_Service.lua`, `ClubMusic_Global_Maintenance_Service.lua`, and `ClubMusic_Global_SafeCall_Service.lua` — global service/configuration/maintenance/safe-call components.

The server controller explicitly sets `UseModernAudioBackend = true`; the controller remains authoritative for track selection, queue state, and transitions. Do not remove legacy recovery or fallback paths until Studio/public-server tests confirm the modern path is stable.

## 3. Diagnostics and health

The snapshot includes:

- `ClubMusic_Client_Diagnostics_Bootstrap.client.lua`, `ClubMusic_Client_Diagnostics_Service.lua`, and `ClubMusic_Client_Diagnostics_Installer.lua`.
- `ClubMusic_Global_Diagnostics_Service.lua` — server-local observational diagnostics coordinator.
- `ClubMusic_Local_Service_Registry.lua` and `ClubMusic_Local_Watchdog_Service.lua` — local service/dependency registry and observational watchdog.
- `ClubMusic_Server_Health_Service.lua` — server health service.
- `ClientIntegrityTelemetry.client.lua` and `ClubMusicSecurityCore/ClientIntegrityTelemetry.lua` — client integrity telemetry components.
- `ClubMusic_SecuritySmokeTest.client.lua` — security smoke-test client.
- `ClubMusic_Studio_CommandBar_Installer.lua` — Studio installation helper.

Diagnostics are observational unless a separately documented owning service performs an action. Client-local measurements are untrusted and must not be treated as server authority.

## 4. Security and authorization

The snapshot includes the `ClubMusicSecurityCore/` module set:

- Authorization, sanity/message validation, security policy/monitoring, audit and event logging.
- Rate limiting, idempotency, receipt authority/hash/transaction services, entitlement authority, and storage/resource guards.
- Movement, teleport, avatar/accessory, character physics, and animation integrity validation.
- Honeypot, threat intelligence, incident response, account-risk, chat-abuse, moderation/punishment, and staff spectator services.
- `ClubMusicSecurityCore/Phase32ServiceBundle.lua` — server-only composition root for the Phase 32 services.
- `ClubMusic_Global_Security_Service.lua` and `ClubMusic_Security_Core_Installer.lua` — global security bundle and installer.
- `SecurityServer.server.lua`, `RegularCommandsSecurityServer.lua`, `StaffActions.server.lua`, `StarterPlayer/StarterPlayerScripts/SecurityClient.client.lua`, and `StarterPlayer/StarterPlayerScripts/SecurityConsole.client.lua` — security and staff-facing entry points.

Security remains server-authoritative. Client-side checks/telemetry are defense-in-depth only. Install only the server/client entry points intended for the experience; do not run duplicate copies of the same service.

## 5. Other included systems

- `UtilityBar/ToolShop.client.lua` and `UtilityBar/ToolShop.server.lua`.
- `TikiTideAdaptiveVisualQuality.client.lua`.
- `ClubMusic_Overhead_Title_Renderer_client.lua`.
- `KohlsAdmin_ClubMusic_Addon.lua` and `ClubMusicKohlsAuditServer.lua`.

## 6. Installation and integration order

1. Install the server-side authoritative controller and its required remotes/dependencies.
2. Install the required server security modules and only the intended security service entry points.
3. Install the modern audio modules and their controller-owned lifecycle dependencies.
4. Install diagnostics modules and their bootstrap/health/watchdog entry points.
5. Install `UI_Network` and `UI_Renderer` into ReplicatedStorage.
6. Install exactly one `ClubMusicBootstrap.client.lua` in StarterPlayerScripts.
7. Install the unified launcher, settings, utility, social and optional staff clients at their intended paths.
8. Verify every `require(script.Parent...)` / `WaitForChild` dependency against the actual Roblox hierarchy before publishing.

## 7. Validation status and known limitations

- Repository tree and source inspection confirm that UI, audio, diagnostics, security, settings, utility, and social source files are present on this branch.
- This is source-level consolidation and an installation/dependency map, not proof that every optional module is wired into the live place or that every subsystem is runtime healthy.
- Roblox Studio runtime, live DataStore/MemoryStore/MessagingService behavior, mobile/desktop UI behavior, audio playback/crossfade, and security enforcement have not been tested by this GitHub source operation.
- Do not delete legacy audio/recovery code or merge the older audit branch wholesale until runtime verification and a file-by-file compatibility review are complete.
