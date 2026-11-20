# Tiki Tide Master Installer — Coverage Audit and Release Gate

**Status: NOT READY TO RUN.** The current `TikiTide_Master_Installer.lua` contains an intentional safety stop. Do not remove it until this audit is closed and the installer passes in a copied test place.

## Authoritative playback rule

- Cross-server playback synchronization is disabled.
- Each server owns its own Now Playing state, playback clock, request queue, playlist cursor, Auto DJ refill, skip votes, and request accounting.
- Do not install or activate `MusicGlobalPlaybackAuthority.lua`, a playback leader lease, shared playback snapshots, or a shared playback queue.
- Global moderation, announcements, catalog invalidation, receipts, security, and other explicitly retained global features are separate from playback.

## Confirmed runtime source groups

The current branch contains these relevant tracked text-source groups. The lists below are source inventory, not proof that every file is a runtime dependency.

### Core UI and music controller
- `UI_Server_Controller_server (1).lua` — Script, ServerScriptService.
- `UI_Renderer (2).lua` — ModuleScript, ReplicatedStorage as `UI_Renderer`.
- `UI_Network.lua` — inspect its require/call sites and existing place ownership before deciding whether it is a separate installed module.
- `ClubMusicBootstrap.client.lua` — LocalScript, StarterPlayerScripts.
- `ClubMusicErrorHandler.lua` — inspect controller requires and current installed parent before provisioning.
- `ClubMusic_Overhead_Title_Renderer_client.lua` — client runtime source; confirm exact current UI integration and avoid duplicate title renderers.

### Modern audio support
- `ClubMusicAudioBackend.luau`
- `ClubMusicAudioCrossfadeManager.luau`
- `ClubMusicAudioQualityProfiles.luau`
- `ClubMusicDJSessionManager.luau`
- `ClubMusicSpatialAudioGraph.luau`
- `ClubMusicPlayerPreferences.luau`
- `MusicCoreService.lua`
- `MusicPlaylistService.lua`
- `MusicQueueManager.luau`
- `MusicValidationService.luau`

The canonical placement and exact active dependencies must be reconciled against the matching controller source. The installation guide has older naming/count inconsistencies (for example, it describes both a five-module and six-module direct ServerStorage core set). Do not invent missing modules such as `MusicCatalogService` or `MusicQueueManagerService` without locating their authoritative source.

### Security Core
The tracked `ClubMusicSecurityCore/` folder contains:
- AccountRiskSignalService
- AdaptiveSecurityLoadManager
- AnimationIntegrityService
- Audit
- Authorization
- AvatarAccessoryValidationService
- CharacterPhysicsGuard
- ChatAbuseDetectionService
- ClientIntegrityTelemetry
- ConnectionJanitor
- EntitlementAuthority
- EventLog
- HoneypotManager
- Idempotency
- IncidentResponse
- MessageValidation
- ModerationPunishmentService
- MovementAuthority
- Phase32ServiceBundle
- RateLimit
- ReceiptAuthority
- ReceiptHash
- ReceiptTransactionService
- ResourceGuard
- SanityValidation
- SecurityMonitor
- SecurityPolicy
- SecurityReplayService
- SecurityThreatIntelligence
- StaffSpectatorService
- StorageGuard
- TeleportValidationService

The existing `ClubMusic_Security_Core_Installer.lua` is the authority for the separately pinned SecurityCore, Threat Intelligence, and Phase 32 snapshots. The master installer must not flatten these modules into an arbitrary release snapshot or replace their release manifest with unverified versions.

### Security and staff runtime scripts
- `SecurityServer.server.lua`
- `StaffActions.server.lua`
- `RegularCommandsSecurityServer.lua`
- `KohlsAdmin_ClubMusic_Addon.lua`
- `StaffSpectatorCamera.client.lua`
- `ClientIntegrityTelemetry.client.lua`
- `TikiTideAdaptiveVisualQuality.client.lua`
- `StarterPlayer/StarterPlayerScripts/SecurityClient.client.lua`
- `StarterPlayer/StarterPlayerScripts/SecurityConsole.client.lua`

The repository documentation disagrees on the class/placement of `RegularCommandsSecurityServer.lua` (Script versus ModuleScript/Kohl's Admin Addon). The actual target place and Kohl's Admin package contract must settle this before installation. Do not create a guessed "Kohls Admin" folder or move the adapter into it automatically.

### Global operational services
- `ClubMusic_Global_Service_server_1.lua`
- `ClubMusic_Global_Config_Service.lua`
- `ClubMusic_Global_Diagnostics_Service.lua`
- `ClubMusic_Global_Maintenance_Service.lua`
- `ClubMusic_Global_SafeCall_Service.lua`
- `ClubMusic_Global_Security_Service.lua`
- `ClubMusic_Local_Service_Registry.lua`
- `ClubMusic_Local_Watchdog_Service.lua`
- `ClubMusic_Server_Health_Service.lua`

Several optional service modules are embedded in `ClubMusic_Global_Optional_Services.rbxmx`; the exact embedded names/classes/parents must be extracted and compared with the standalone text sources. The previously committed installer guessed a nonexistent `ClubMusic_Global_Event_Log_Service.lua` path. That entry must not be used as evidence of a complete global-service install.

### Tiki Tide Settings and social actions
- `TikiTideSettings/TikiTideSettings.client.lua`
- `TikiTideSettings/TikiTideSettingsService.server.lua`
- `TikiTideSocialActions.client.lua`
- `TikiTideSocialActions.server.lua`
- `TikiTideSocialActions/AnimationConfig.lua`
- `StarterPlayer/StarterPlayerScripts/TikiTideUnifiedLauncher.client.lua`

The documented social animation config is a ModuleScript child of the Social Actions server Script, not a loose ServerScriptService child. The master installer must preserve this nesting.

### Utility Bar
Client LocalScripts documented for StarterPlayerScripts:
- `UtilityBar/UtilityBar.client.lua`
- `UtilityBar/UtilityBarActions.client.lua`
- `UtilityBar/UtilityBarPanels.client.lua`
- `UtilityBar/ToolShop.client.lua`

Server Scripts documented for ServerScriptService:
- `UtilityBar/UtilityBarActions.server.lua`
- `UtilityBar/UtilityBarExtendedActions.server.lua`
- `UtilityBar/ToolShop.server.lua`

These scripts are separate from ClubMusic playback and must not be placed into invented subfolders unless the source requires those folders.

## Tracked assets and packages requiring explicit treatment

The branch also contains binary/model or XML packages and legacy references:
- `ClubMusic_Audio_Client_Modules.rbxmx`
- `ClubMusic_Audio_Server_Modules.rbxmx`
- `ClubMusic_Global_Optional_Services.rbxmx`
- `ClubMusic_ServerStorage_Modules.rbxmx`
- `Music Remote 1.rbxm` through `Music Remote 5.rbxm`
- `Music Role System`
- `Music Storage Handle`
- `building tools`
- `building tools explorer code`
- `diag`
- legacy/rollback sources documented in the audio installation guide, including MusicPlaybackManager and older Sound/MusicGroup consumers.

These cannot be blindly installed. Some are reference-only, some may contain remotes or scripts, and some may be third-party/native packages. The master installer must inventory package descendants and classify each as active, reference-only, excluded third-party, or rollback-only before changing the place. No legacy music remotes, second controller, old shared playback authority, or duplicate Kohl's Admin package may be installed.

## Runtime-created instances

The source creates several runtime endpoints and folders itself. The master installer should validate their class/ownership after startup rather than pre-create duplicates:
- Settings remotes under `ReplicatedStorage/TikiTideSettingsRemotes`.
- Social remotes under `ReplicatedStorage/TikiTideSocialRemotes`.
- Security remotes under `ReplicatedStorage/SecuritySystem`.
- Global API and server-only BindableFunctions under `ServerStorage/ClubMusicGlobalAPI`.
- Utility Bar remotes under `ReplicatedStorage/UtilityBarRemotes`.
- Server-owned modern AudioPlayer graph under `SoundService`.

Exact endpoint names and ownership must be checked against each current source before any optional pre-provisioning. Do not expose server-only BindableFunctions to clients.

## Required closure before removing the safety stop

1. Obtain the current target place export (`.rbxl`, `.rbxlx`, or Explorer hierarchy `.rbxmx`) and inventory every Script, LocalScript, ModuleScript, RemoteEvent, RemoteFunction, BindableEvent, BindableFunction, Folder, and package descendant.
2. Fetch and statically inspect every runtime candidate's `require`, `WaitForChild`, `FindFirstChild`, remote creation, attribute, and service references. Resolve every dependency to one authoritative source and destination.
3. Reconcile the master manifest with the separate audio, SecurityCore, diagnostics, Utility Bar, Settings, social, Kohl's Admin, and global-service installation contracts. Preserve independent immutable release pins where required.
4. Classify every tracked file as installed runtime, embedded package source, reference-only, legacy rollback, documentation, screenshot, or third-party asset. Do not equate repository file count with runtime script count.
5. Make installation transactional: stage all sources; validate classes, parents, duplicate owners, dependencies, source sizes, and release manifests; create verified backups; then promote. On failure, restore the exact previous active instances. Keep the prior release until post-install checks pass.
6. Run in a copied unpublished place. Verify Studio compilation, clean startup/shutdown, all UI surfaces, audio controls, per-client volume, local queue isolation, purchases/profile persistence, moderation/security, remotes, staff tools, mobile and desktop behavior, and two published test servers with playback sync still disabled.
7. Record the exact installed manifest and test results. Only then remove the safety stop and label the master installer ready.

**Current result:** source audit identified missing/guessed destinations, release-pin conflicts, a stale documentation conflict about playback sync, and binary package/live-place gaps. The master installer is therefore intentionally blocked rather than falsely advertised as “every script.”
