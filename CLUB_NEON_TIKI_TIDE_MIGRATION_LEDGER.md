# Tiki Tide → Club Neon Migration Ledger

**Branch:** `integration/tiki-tide-system-consolidation`  
**Installer audited:** `ClubNeon_Master_Installer.lua` v0.3.4  
**Audit basis:** tracked source files and packages in this repository, plus the Tiki Tide and Club Neon master installers and compatibility audit.  
**Safety:** audit only. No Roblox place was modified. Installer remains `DRY_RUN = true`.

## Executive result

The v0.3.3 installer contains the main source-based Tiki Tide runtime feature groups in Club Neon-adapted form. The audit did **not** find a missing top-level feature group among the systems explicitly enumerated by the Tiki Tide master installer. That is not proof that every original Tiki Tide place script, asset, remote, or runtime-created instance is represented: this repository does not contain an authoritative export of the original Tiki Tide place hierarchy.

The important gaps are not all the same kind:
- **Intentionally excluded:** retired cross-server playback authority, old audio/role/storage implementations, test and installer utilities, and binary packages that duplicate individually staged modules.
- **Adapted:** UI/controller/network, security, global services, settings, social actions, utility bar, and Kohl's adapters.
- **Conditional / external:** Kohl's Admin integration, mount models, social animation assets, map tags/fixtures, owner/staff IDs, and Club Neon-owned monetization IDs.
- **Unverified:** opaque legacy `.rbxm` packages and anything that exists only in the original Tiki Tide place file rather than tracked source.

## 1. Runtime feature migration

| Tiki Tide system | Club Neon destination/source | Classification | Notes |
|---|---|---|---|
| Main server UI/music controller | `ClubNeon_UI_Server_Controller.server.lua` → `ServerScriptService/UI_Server_Controller` | Adapted | Reads `ClubNeon_Config`; Tiki Tide IDs and datastore identity are not carried over. |
| UI renderer | `ClubNeon_UI_Renderer.lua` → `ReplicatedStorage/ClubNeon_UI_Renderer` | Adapted | Club Neon-specific UI and purchase configuration. |
| UI network bridge | `ClubNeon_UI_Network.lua` → `ReplicatedStorage/ClubNeon_UI_Network` | Adapted | Uses the Club Neon controller's remote-folder contract. |
| Client bootstrap | `ClubNeonBootstrap.client.lua` | Adapted | Club Neon startup path. |
| Overhead title renderer | `ClubMusic_Overhead_Title_Renderer_client.lua` | Shared / included | Shared source; confirm UI runtime behavior in Studio. |
| Error handler | `ClubMusicErrorHandler.lua` | Shared / included | Staged in ServerStorage. |
| Modern AudioPlayer backend | `ClubMusicAudioBackend.luau` | Included | Server-owned modern audio architecture. |
| Crossfade manager | `ClubMusicAudioCrossfadeManager.luau` | Included | Modern crossfade. |
| Audio quality profiles | `ClubMusicAudioQualityProfiles.luau` | Included | Modern quality profiles. |
| DJ session manager | `ClubMusicDJSessionManager.luau` | Included | Shared modern DJ session module. |
| Spatial audio graph | `ClubMusicSpatialAudioGraph.luau` | Included | Modern spatial audio module. |
| Player audio preferences | `ClubMusicPlayerPreferences.luau` | Included | Staged in the client audio modules folder. |
| Music core and playlist services | `MusicCoreService.lua`, `MusicPlaylistService.lua` | Included | Staged directly in ServerStorage as expected by the controller. |
| Security Core (32 runtime modules) | `ClubNeonSecurityCore/` | Adapted | Separate Club Neon-namespaced folder and independently pinned release groups. |
| Physics guard bootstrap | Extracted from `ClubNeon_Security_Core_Installer.lua` | Adapted | Embedded bootstrap is staged as a Script; installer itself is not installed as runtime. |
| Security server and staff actions | `ClubNeonSecurityServer.server.lua`, `ClubNeonStaffActions.server.lua` | Adapted | Club Neon-specific service names and authorization. |
| Security client and console | `ClubNeon_SecurityClient.client.lua`, `ClubNeon_SecurityConsole.client.lua` | Adapted | Client presentation; server remains authority. |
| Staff spectator camera | `ClubNeon_StaffSpectatorCamera.client.lua` | Adapted | Club Neon endpoint names. |
| Client integrity telemetry | `ClubNeonClientIntegrityTelemetry.client.lua` | Adapted | Separately pinned; v0.3.3 checks the staged Club Neon UI module names. |
| Adaptive visual quality | `ClubNeonAdaptiveVisualQuality.client.lua` | Adapted | Club Neon-specific service/attribute names. |
| Client diagnostics | `ClubMusic_Client_Diagnostics_Service.lua`, `ClubMusic_Client_Diagnostics_Bootstrap.client.lua` | Included | Independently pinned client diagnostics. |
| Global operational service | `ClubNeon_Global_Service.server.lua` | Adapted | Club Neon stores, config and authorization. Playback synchronization endpoints return disabled responses. |
| Global config/diagnostics/maintenance/safe-call/security | Corresponding `ClubMusic_Global_*` modules | Included / adapted at use sites | Club Neon global service consumes these optional modules. |
| Local service registry, watchdog, server health | Corresponding `ClubMusic_Local_*` and `ClubMusic_Server_Health_Service.lua` | Included | Staged in ServerStorage. |
| Global event log, rate limit, authorization | Extracted from `ClubMusic_Global_Optional_Services.rbxmx` | Included / adapted | Explicit three-module allowlist; embedded sources are project-name/group-ID transformed. |
| Settings server/client | `ClubNeonSettings/` | Adapted | Uses Club Neon settings remotes and UI state. |
| Social actions server/client/config | `ClubNeonSocialActions*` | Adapted | AnimationConfig remains nested under the Social Actions server Script. |
| Unified launcher | `ClubNeonUnifiedLauncher.client.lua` | Adapted | Club Neon entry points. |
| Utility Bar (4 clients, 3 servers) | `ClubNeonUtilityBar/` | Adapted | Includes Inventory, Tool Shop, Mount, Size, Clone, Aura, Lighting and outfit refresh code. |
| Kohl's Admin config addon | `KohlsAdmin_ClubNeon_Addon.lua` | Adapted / conditional | Installed when a unique Kohl's Admin container is discovered anywhere in the place and its Config/Addons folder is present. |
| Kohl's Admin regular-command security addon | `ClubNeonRegularCommandsSecurityServer.lua` | Adapted / conditional | Installed when a unique Kohl's Admin container is discovered anywhere in the place and its root Addons folder is present. |

## 2. Deliberate exclusions and replacements

| Source candidate / package | Status | Reason / replacement |
|---|---|---|
| `MusicGlobalPlaybackAuthority.lua` and the same-named ModuleScript embedded in `ClubMusic_Global_Optional_Services.rbxmx` | **Intentionally excluded** | Retired shared playback authority. Club Neon keeps per-server queue, playback clock, Auto DJ cursor and Now Playing. The global service exposes disabled playback API responses; it must not stage a leader lease or shared snapshots. |
| `MusicQueueManager.luau` | Not staged as a separate ModuleScript | Its queue implementation is bundled inside `MusicCoreService.lua` and exposed as `MusicCoreService.Queue`. |
| `MusicValidationService.luau` | Not staged as a separate ModuleScript | Its validation implementation is bundled inside `MusicCoreService.lua` and exposed as `MusicCoreService.Validation`. The standalone older source also depends on `ServerStorage.Modules.RoleSystem`, which is not part of the modern bundled contract. |
| `Music Role System` | **Excluded / legacy** | Separate legacy pass-role and datastore implementation with placeholder pass IDs and a separate owner ID. Club Neon uses `ClubNeon_Config` and the shared Security Core authorization/entitlement path instead. |
| `Music Storage Handle` | **Excluded / legacy candidate** | Older Sound-object cache/storage implementation. The current installer stages the modern AudioPlayer backend. No dependency from the current controller was identified in this source review. Keep the old file for reference; do not install alongside modern playback without a separate dependency review. |
| `ClubMusic_Audio_Client_Modules.rbxmx` | Package not installed | Contains the same client preferences ModuleScript staged from its individually pinned source. |
| `ClubMusic_Audio_Server_Modules.rbxmx` | Package not installed | Contains the five modern audio modules staged individually from the pinned audio release. |
| `ClubMusic_ServerStorage_Modules.rbxmx` | Package not installed | Contains MusicCoreService and MusicPlaylistService, which the master installer stages individually at the controller-required direct ServerStorage paths. |
| `ClubMusic_Global_Optional_Services.rbxmx` as a complete Folder | Not installed wholesale | The installer extracts only the three approved active optional modules. It separately stages the standalone SafeCall module. The playback authority is not extracted. |
| `ClubMusic_Security_Core_Installer.lua` / `ClubNeon_Security_Core_Installer.lua` | Installer utility not staged as runtime | The master installer stages the pinned Security Core modules and extracts only the required physics-guard bootstrap. |
| `ClubMusic_Client_Diagnostics_Installer.lua` | Installer utility not staged as runtime | The master installer stages the diagnostics module and client bootstrap directly. |
| `TikiTide_Master_Installer.lua` | Installer utility not staged as runtime | It is the source project's installer, not a game runtime service. |
| `TikiTide_Studio_Runtime_Audit.lua` | Audit utility not staged as runtime | Read-only Studio inspection tool. |
| `ClubMusic_SecuritySmokeTest.client.lua` | Test-only; not staged | Temporary Studio test script, not production client runtime. |
| `ClubMusicSecurityCore/SecurityThreatIntelligence.spec.lua` | Test spec; not staged | Test source, not a runtime ModuleScript. |
| `ClubMusicKohlsAuditServer.lua` | Not staged | Observational/audit addon, distinct from the two permission-enforcement adapters. |
| `Music Remote 1.rbxm` through `Music Remote 5.rbxm` | **Unverified legacy/opaque packages; not staged** | Binary model packages are not part of the source-based installer manifest. Inspect package contents and references before deciding whether any endpoint/asset is still required. Do not insert blindly. |
| `building tools`, `building tools explorer code` | **Third-party / editor-tool content; not staged** | These are not Tiki Tide runtime music/UI modules and may contain third-party tool code. Preserve existing game/admin packages; do not install these from the repository as part of this migration. |

## 3. External assets and configuration still required

These are not missing scripts, but the corresponding features are not fully operational until their target-game resources/configuration are supplied and tested:

| Feature | Required item | Current state |
|---|---|---|
| Ownership and staff authorization | Club Neon owner/staff UserIds; optional group ID/rank thresholds | Safe defaults are empty / disabled. Live install is blocked until at least one owner UserId is configured. |
| Monetization and entitlement tiers | Club Neon-owned VIP/VVIP/Elite and utility pass IDs; developer product IDs | Monetization is disabled and IDs are zero by default. Tiki Tide IDs are intentionally not imported. |
| Donation products | Club Neon-owned donation product IDs and approved labels | Config-driven placeholders; not purchasable until configured. |
| Mount | Approved rideable Model under `ServerStorage.ClubNeonMounts` | Code is present; model asset is not bundled. |
| Social actions | Experience/group-owned animation IDs in Club Neon AnimationConfig | Config values must be supplied; zero IDs fail closed. |
| Utility lighting | Club Neon stage/club fixtures tagged/configured for the lighting action | Code is present; actual map fixtures require target-place configuration. |
| Dance-floor rewards | Approved Club Neon dance-floor zone tag(s) | Controller expects Club Neon-tagged zone parts; map tagging is not supplied by the script installer. |
| Tool Shop | Approved catalog entries/assets | Storefront code is present; catalog intentionally remains empty until configured. |
| Kohl's Admin | Supported addon folders at the installer-expected locations | Adapters are conditional. The v0.3.4 installer scans the full place hierarchy for a uniquely named Kohl's Admin container and resolves its existing Config/Addons and root Addons folders. It never moves or modifies the third-party package; ambiguous or incomplete discovery safely skips the affected adapter. |

## 4. Repository candidates that need special treatment

- `ClubMusic_Global_Optional_Services.rbxmx` contains five ModuleScripts: Event Log, Rate Limit, Authorization, SafeCall, and MusicGlobalPlaybackAuthority. The installer allowlist extracts only Event Log, Rate Limit and Authorization; SafeCall is staged from its standalone source; playback authority is excluded.
- The audio and ServerStorage RBXMX packages duplicate modules that are staged as individual source files. Installing both forms would risk duplicate module ownership and ambiguous require paths.
- The repository contains no authoritative original Tiki Tide `.rbxl` / full place hierarchy in this audit. The tracked `Club Neon.rbxl` is the target place, not an original Tiki Tide source export. Therefore this ledger covers tracked source candidates and installer-defined runtime, not every script or asset that may exist only inside the original Tiki Tide place.
- Runtime-created remotes, folders, BindableFunctions and AudioPlayer instances are created by their owning server scripts. The installer should not create duplicate copies in advance.

## 5. Release and validation findings

1. The source-based runtime groups in the Tiki Tide master installer have corresponding Club Neon installer entries, with project-specific variants where needed.
2. The Security Core is staged as 32 runtime modules from the dedicated Club Neon folder and three independently pinned release groups; the spec file is not runtime.
3. The five modern server audio modules, client preferences and two server music core modules are staged individually. Queue and validation implementations are bundled in MusicCoreService.
4. The global optional package is selectively extracted; MusicGlobalPlaybackAuthority is intentionally omitted.
5. Kohl's Admin adapters are conditional on successful hierarchy discovery and the expected Addons folder contract; verify the discovered full paths in the Studio dry-run output.
6. Source retrieval, pinning and static path checks do not prove Luau compilation or Roblox Studio runtime correctness.
7. The v0.3.2 Studio dry-run output in the prior audit is not a v0.3.3 test. A fresh v0.3.3 Studio dry run and copied-place regression run are still required.
8. Do not set `DRY_RUN = false`, publish, remove legacy systems, or alter the live place until configuration, package contracts, exact dependencies and the full regression plan are closed.

## 6. Closure checklist

- [ ] Obtain an authoritative Tiki Tide `.rbxl` or exported hierarchy if a literal all-instance inventory is required.
- [ ] Inspect the five legacy Music Remote `.rbxm` packages and identify their contents/owners before any migration decision.
- [ ] Confirm whether any active Tiki Tide scripts outside the master installer depend on Music Role System or Music Storage Handle.
- [ ] Confirm Club Neon owner/staff IDs, optional group configuration and monetization decision.
- [ ] Supply/approve mount and social animation assets; configure map tags/lighting fixtures and Tool Shop catalog.
- [ ] Resolve the Kohl's Admin package location/adapter contract without moving or modifying the third-party package automatically.
- [ ] Run v0.3.3 dry run in Studio and review every destination and skipped optional adapter.
- [ ] Run the complete unpublished-copy compile/startup, UI, audio, local queue, security, staff, persistence, monetization (if enabled), global operations and desktop/mobile regression suite.
- [ ] Record the exact installed manifest and test results before any production rollout.

**Conclusion:** The current installer is a broad source-level migration of the original Tiki Tide installer's runtime manifest, not a byte-for-byte copy of the original game. Its major intentional exclusions are the retired shared playback authority and legacy/duplicate/test packages. Its outstanding work is configuration, external assets, optional Kohl's integration, opaque package inspection, and runtime verification—not an identified missing core runtime feature group.
