# Tiki Tide Master Installer — Coverage Audit and Release Gate

**Status: SOURCE MANIFEST REBUILT; DRY-RUN DEFAULT; NOT YET RUNTIME-VALIDATED.** The installer no longer requires a place export to build the documented hierarchy, but it must still be tested in an unpublished copy before publication. The current `TikiTide_Master_Installer.lua` contains an intentional safety stop. Do not remove it until this audit is closed and the installer passes in a copied test place.

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

1. The user elected to proceed without a target place export. Use the installer's exact-path class preflight and backups; treat unknown existing descendants and external package contents as out of scope, preserve them, and report conflicts instead of guessing.
2. Fetch and statically inspect every runtime candidate's `require`, `WaitForChild`, `FindFirstChild`, remote creation, attribute, and service references. Resolve every dependency to one authoritative source and destination.
3. Reconcile the master manifest with the separate audio, SecurityCore, diagnostics, Utility Bar, Settings, social, Kohl's Admin, and global-service installation contracts. Preserve independent immutable release pins where required.
4. Classify every tracked file as installed runtime, embedded package source, reference-only, legacy rollback, documentation, screenshot, or third-party asset. Do not equate repository file count with runtime script count.
5. Make installation transactional: stage all sources; validate classes, parents, duplicate owners, dependencies, source sizes, and release manifests; create verified backups; then promote. On failure, restore the exact previous active instances. Keep the prior release until post-install checks pass.
6. Run in a copied unpublished place. Verify Studio compilation, clean startup/shutdown, all UI surfaces, audio controls, per-client volume, local queue isolation, purchases/profile persistence, moderation/security, remotes, staff tools, mobile and desktop behavior, and two published test servers with playback sync still disabled.
7. Record the exact installed manifest and test results. Only then remove the safety stop and label the master installer ready.

**Current result:** source audit identified missing/guessed destinations, release-pin conflicts, a stale documentation conflict about playback sync, and binary package/live-place gaps. The master installer is therefore intentionally blocked rather than falsely advertised as “every script.”


## Source-based audit updates (place export unavailable)

The user has elected to finish the installer without attaching the target `.rbxl` place. The release can therefore be built around documented, deterministic Roblox service paths, but it cannot claim to reconcile unknown pre-existing live-place instances or external package descendants. The installer must preflight every destination and stop on conflicting classes or ambiguous third-party ownership.

### Verified package contents

The current integration branch's XML packages were inspected at the item/class/name level:

- `ClubMusic_Audio_Server_Modules.rbxmx` contains one Folder and exactly five ModuleScripts: `ClubMusicAudioBackend`, `ClubMusicAudioCrossfadeManager`, `ClubMusicAudioQualityProfiles`, `ClubMusicDJSessionManager`, and `ClubMusicSpatialAudioGraph`.
- `ClubMusic_ServerStorage_Modules.rbxmx` contains one Folder and exactly two ModuleScripts: `MusicCoreService` and `MusicPlaylistService`.
- `ClubMusic_Global_Optional_Services.rbxmx` contains `ClubMusic_Global_Event_Log_Service`, `ClubMusic_Global_RateLimit_Service`, `ClubMusic_Global_Authorization_Service`, `ClubMusic_Global_SafeCall_Service`, and `MusicGlobalPlaybackAuthority`.
- `MusicGlobalPlaybackAuthority` is retired and must be excluded, even though it remains embedded in the package. The other four optional modules may be extracted from the package allowlist; there are no standalone Lua files for Event Log, Rate Limit, or Authorization at the master installer's current source snapshot.

### Corrected source/placement findings

- `ClubMusicErrorHandler.lua` is an optional ModuleScript under **ServerStorage**, not ReplicatedStorage. Both the controller and Global Service look for it there.
- The controller requires `MusicCoreService` and `MusicPlaylistService`. The former exports Catalog, Validation, and Queue. Do not separately provision `MusicQueueManager.luau` or `MusicValidationService.luau` as direct dependencies; the audio guide identifies these as rollback/unreferenced artifacts in the current controller path.
- The audio installer has an independent immutable pin, `6ec3766ef48f38eb2893f3385e4b4370ec0b7112`, for five audio support modules and the two direct ServerStorage core modules. Preserve this pin rather than sourcing them from the general runtime snapshot.
- The Global Service expects Security Core release `7ebc71e3a6fa9ef04e80d5f332e5f72617c8d288`. The Security Core installer also pins Threat Intelligence separately to `5790cd0c61d2f1bd38fe8aab92f5a234e7ec7e87` and Phase 32 modules to `6ae4883c2c260df61bf760b8637dd339bda33d7b`. These three pins must remain intact in the master installer.
- Client diagnostics are separately pinned to `a486f1f046fc187da8c59d46d91d64e96f3e710c`; the module belongs in ReplicatedStorage and its bootstrap LocalScript in StarterPlayerScripts.
- `TikiTideSocialActions.server.lua` expects an `AnimationConfig` ModuleScript inside a child Folder named `TikiTideSocialActions` parented under the server Script (the script supports this documented nested layout). A loose ModuleScript directly under ServerScriptService is incorrect.
- `RegularCommandsSecurityServer.lua` is a Kohl's Admin addon ModuleScript that returns a function, not a standalone ServerScriptService Script. Its documented destination is under the external Kohl's Admin package. `KohlsAdmin_ClubMusic_Addon.lua` also belongs inside Kohl's Admin's Addons configuration. These must be installed only when the expected external package folders exist; the master installer must not fabricate or replace Kohl's Admin itself.
- The current master installer includes a guessed `ClubMusic_Global_Event_Log_Service.lua` URL that does not exist, and it omits the package extraction required for Event Log, Rate Limit, and Authorization. This is a release blocker.
- The current master installer incorrectly places `ClubMusicErrorHandler` in ReplicatedStorage, installs rollback-only queue/validation adapters as live dependencies, and creates the social animation config as a loose ServerScriptService ModuleScript. These entries must be corrected before release.

### Playback isolation hardening

The general Global Service source still contains dormant playback-sync toggle/lease code, despite the installation guide describing playback sync as retired and the default shared config being `playbackSyncEnabled=false`. The master release must not install the embedded `MusicGlobalPlaybackAuthority`, must initialize the shared setting to false, and must ensure the global status remains LocalOnly. A stale persisted true value must not activate a leader lease or shared playback state. This code/config mismatch must be resolved explicitly; a false default alone is not sufficient proof.

### Release limitations without the place export

The installer can create documented destination folders and provision the repository-owned scripts/modules in a clean or compatible place. It cannot prove whether the user's current place already contains duplicate legacy scripts, remotes, third-party packages, custom children, or non-Archivable objects. Therefore:

1. Never recursively delete unknown place contents.
2. Never replace Kohl's Admin or other third-party packages.
3. Before promotion, detect same-name objects at each exact destination and validate their class.
4. Back up exact replaced instances before changing them.
5. If a target path is owned by an external package or is ambiguous, stop that entry and report it rather than guessing.
6. Report the Kohl's Admin adapters as pending if the expected package hierarchy is absent.
7. Keep the safety hold until the corrected source manifest, transactional promotion/rollback, and source-level consistency checks are complete. Runtime verification in a copied Studio place is still required before publication.


## Master installer rebuild committed

The single installer was rebuilt and committed on `integration/tiki-tide-system-consolidation`:

- Installer: `TikiTide_Master_Installer.lua`
- Rebuild commit: `0557f7a550231c4792d27f263c024050389dbf70`
- Follow-up parser/dry-run fix: `e3d25e4459a9707dd4172ac43865d9dbb9d5640b`
- Social config preflight fix: `e0cef38fabbcf695e25a1fe60cc9f9ab7e743fdd`
- Startup ordering update: `b15af8b746724cc5547e230cd4b73237c832e685`

The installer now:
- Uses separate immutable pins for the general runtime, modern audio, Security Core, Threat Intelligence, Phase 32, client diagnostics, and the hard-disabled Global Service.
- Extracts only the three active embedded global modules (Event Log, Rate Limit, Authorization) from the XML package. It does not extract the retired playback authority.
- Extracts the exact CharacterPhysicsGuard bootstrap source from the certified Security Core installer instead of maintaining a divergent copy.
- Places `ClubMusicErrorHandler` in ServerStorage, keeps `MusicCoreService` and `MusicPlaylistService` as direct ServerStorage children, and does not install rollback-only queue/validation adapters.
- Nests `AnimationConfig` under the Social Actions server Script's `TikiTideSocialActions` folder.
- Installs client diagnostics separately from server error-history diagnostics.
- Installs Kohl's Admin adapters only when the documented external Addons folders already exist; it never creates or replaces Kohl's Admin.
- Preflights exact destination classes, preserves replaced instances under a timestamped backup folder, and restores moved instances if promotion fails.
- Archives any existing `MusicGlobalPlaybackAuthority` ModuleScripts found under ServerStorage.
- Defaults to `DRY_RUN = true`; a dry run stages all pinned sources and checks destinations without creating folders or replacing scripts.

## Playback synchronization hard-disable

The Global Service itself was patched and committed at `03982721949665c4fc0fa7a29c54a70bce749339`:
- It no longer loads or references `MusicGlobalPlaybackAuthority`.
- Global playback status is always `LocalOnly`.
- Snapshot, leadership, and commit endpoints return disabled.
- Attempts to enable playback synchronization are rejected.
- Retained legacy Playback-topic messages are ignored.
- MemoryStore diagnostics report no playback lease.
The master installer fetches this exact commit and checks the hard-disable marker before proceeding.

## Remaining release gates

1. Run the installer with `DRY_RUN = true` in Studio and resolve any exact-path class conflicts.
2. Review the printed manifest and confirm the optional Kohl's Admin adapters are either installed into the existing expected folders or clearly reported as pending.
3. In a backed-up unpublished copy, set `DRY_RUN = false` and perform the installation.
4. Verify Studio output and all regression items in the original audit, especially startup order, standard playback controls, queue operations, watchdog/registry health, purchase receipts, Security Core manifest alignment, desktop/mobile UI, and two-server local playback isolation.
5. Confirm the Global Service reports `LocalOnly` even if an old shared config value exists, and confirm no `MusicGlobalPlaybackAuthority` remains under ServerStorage.
6. Only after those runtime tests pass should the release be called ready for publishing.

**Current safety posture:** source staging and static package parsing were verified against the pinned GitHub files. No Roblox Studio execution or published-server runtime test has been performed or claimed.


## Studio log follow-up: read-only runtime audit

Added `TikiTide_Studio_Runtime_Audit.lua` in commit `682b4f3ae2da8456310a408294df6a5548b2cd19`.

Paste this read-only script into Studio's Command Bar while not playing. It reports:
- Descendant totals by top-level service, including BaseParts, MeshParts, unions, Models, GUI objects, and scripts.
- The largest instance classes across the DataModel.
- Every object named exactly `Theme`.
- Readable scripts containing the literal `Hello world!`.
- Duplicate instance-name groups by class and name.

It makes no changes. This will distinguish whether the approximately 69,500 instances are primarily in Workspace/map content, UI, or another service, and locate the two generic Hello World scripts. It is a diagnostic inventory, not an automatic cleanup tool.

The duplicate-theme warning originates from an external Kohl's Admin script path (`Kohl's Admin.Loader.MainModuleLegacy.D.Extras.Explorer.Explorer`) in the supplied Studio log. The repository's Tiki Tide UI/controller source contains no theme registration calls, so no speculative theme rename was made. The Kohl's Admin package's Explorer and Building Tools errors likewise cannot be safely patched from repository sources; they require inspection of the exact installed package hierarchy/source.

The memory values (812 MB peak in this log) are global Roblox runtime measurements, not per-script attribution. No memory threshold or automatic cleanup was added. The service/class audit is the next evidence-gathering step before any deletion or optimization.
