# Club Neon Master Installer — Build Plan

Target: Club Neon
Repository: NycXglossy/Ui-Game-Code
Branch: integration/tiki-tide-system-consolidation
Current installer: ClubNeon_Master_Installer.lua (v0.1.0)
Current mode: read-only preflight only

## 1. Verified target-place inventory

The v0.1.0 Studio preflight completed without errors and made no changes.

Place-owned service inventory:
- Workspace: 5,999 descendants; 18 Script instances, 6 LocalScript instances, 333 ModuleScript instances as reported by the current class scan.
- ReplicatedStorage: 6,939 descendants; no Script, LocalScript, or ModuleScript instances.
- ServerScriptService: 8 Script instances; no ModuleScripts reported.
- ServerStorage: empty.
- StarterPlayer: 9 descendants. The v0.1.0 helper uses IsA checks that can overlap class buckets; do not treat its Script and LocalScript subtotals as mutually exclusive.
- StarterGui: 6 descendants, including 2 ScreenGuis and 1 LocalScript.
- Lighting: 12 descendants, including 7 Sky instances and post-processing effects.
- SoundService, Teams, StarterPack: empty.
- TextChatService: 8 descendants.

The listed game-service roots are disjoint. Their combined descendant count is 12,981. This is not directly comparable to the earlier 15,681 total, which included Studio/plugin/runtime services such as Stats, StylingService, DebuggerManager, MemStorageService, CoreGui, PluginGuiService, and VisualizationModeService.

## 2. Existing assets and third-party content

- Kohl's Admin exists at Workspace.Kohl's Admin.
- Its loader is at Workspace.Kohl's Admin.Loader.MainModule.
- Config is at Workspace.Kohl's Admin.Config and Addons is under that configuration.
- Do not move, replace, patch, or delete Kohl's Admin as part of the first Club Neon install.
- Two placeholder scripts contain the literal text "Hello world!":
  - Workspace.Part.Script
  - Workspace.Part.Script.Script
  These require owner review before any removal.
- ReplicatedStorage.InteractionAnims contains three KeyframeSequence assets:
  - CarryHolder: 90 Keyframes, 1,980 Poses
  - Hug: 120 Keyframes, 2,640 Poses
  - CarryHeld: 90 Keyframes, 1,980 Poses
  Preserve these animation assets. Their size alone is not evidence of a performance problem.

## 3. Shared system availability

The v0.1.0 candidate scan did not find the shared Tiki Tide/ClubMusic modules in the target place. In particular, the controller, renderer, UI network, bootstrap, modern audio modules, server music core, playlist service, and global service are absent by the scanned names.

The target therefore appears to be a fresh integration of the shared platform rather than an update to an existing ClubMusic installation.

## 4. Source compatibility blockers — do not blindly clone Tiki Tide

The current Tiki Tide source is not a neutral drop-in package:
- UI_Server_Controller contains Tiki Tide's group ID, pass IDs, developer-product IDs, datastore name, feature names, and a global-playback-sync setting.
- UI_Renderer contains hard-coded Tiki Tide pass/product IDs and Tiki Tide-specific UI attributes, labels, and settings.
- ClubMusic_Global_Service contains Tiki Tide-specific security endpoint names and diagnostics integration.
- The Tiki Tide installer intentionally enforces that project's retired cross-server playback-sync policy.

For Club Neon, these must be handled as explicit target configuration and compatibility decisions. Do not carry over Tiki Tide group IDs, monetization IDs, datastore keys, labels, or playback-sync policy by default.

## 5. Proposed Club Neon install stages

### Stage A — Configuration intake (required before a live installer)
Create a ClubNeon_Config module containing:
- Project display name and product branding.
- Owner/staff UserIds and optional Roblox group ID.
- Game pass IDs and developer product IDs, or explicit false/disabled values.
- DataStore namespace prefix unique to Club Neon.
- Feature flags for requests, DJ controls, Auto DJ, playlists, cross-server moderation, announcements, security, staff tools, and optional utility UI.
- Explicit playback architecture choice: server-local playback/queue by default; cross-server playback sync remains disabled unless the owner explicitly requests a separate design review.

### Stage B — Source normalization
Build Club Neon variants of the controller, renderer, bootstrap, and global service. Replace Tiki Tide-specific references only through reviewed, deterministic transformations or maintained Club Neon source files. Never do broad blind string replacement.

### Stage C — Read-only install plan
Fetch all pinned sources, validate hashes/size and expected source markers, validate destination class/path conflicts, and print a complete plan. No promotion.

### Stage D — Backed-up installation
Only after explicit approval and a backup:
- Stage source instances in an isolated ServerStorage folder.
- Validate all required sources and destination classes before promotion.
- Preserve pre-existing objects with collision-safe backups.
- Install shared core, modern audio, UI, and selected optional services to their exact target paths.
- Do not touch Workspace map assets, InteractionAnims, Kohl's Admin, or unrelated scripts.

### Stage E — Runtime verification
Test server startup, UI open/close, request/queue controls, playback transitions, skip, staff permissions, purchase processing (if enabled), datastore failure behavior, and multi-server global services (if enabled). No legacy audio removal until the modern system is stable.

## 6. Required owner decisions before enabling installation

1. Confirm whether Club Neon should receive the same broad feature set as Tiki Tide or a smaller subset.
2. Supply the Club Neon owner/staff UserIds and group ID, if group rank features are wanted.
3. Supply Club Neon game pass and developer product IDs, or confirm monetization stays disabled for the first release.
4. Confirm whether cross-server moderation/announcements are wanted. Playback sync is a separate decision and remains disabled by default.
5. Confirm the preferred branding labels for the UI and DJ experience.

Until these are known, keep the Club Neon installer in read-only/dry-run mode.