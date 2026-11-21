# Club Neon Full-Feature Integration — Compatibility Audit

**Decision:** Owner selected the full feature set on 2026-11-20.
**Target:** Club Neon | **Branch:** integration/tiki-tide-system-consolidation
**Status:** project-specific runtime variants and installer v0.3.0 committed; live installation remains gated on owner configuration and Studio regression testing.

## Approved feature scope
- ClubMusic requests, per-server queue, Auto DJ, playlists, DJ booth and playback controls.
- Modern Roblox AudioPlayer backend, crossfade, quality profiles, player preferences, and audio diagnostics.
- Full staff/security layer: Security Core, threat intelligence, moderation, staff actions, spectator tools, client integrity telemetry, audit/event history, rate limiting, and health/watchdog diagnostics.
- UI renderer, bootstrap, overhead titles, settings, social actions, utility bar, tool shop, mounts, companions, lighting controls, and staff console.
- Global moderation, announcements, catalog invalidation, and receipt coordination where services are enabled and configured.
- Project-specific monetization hooks, initially disabled until Club Neon-owned pass/product IDs are provided.
- Existing map, InteractionAnims, and Kohl's Admin remain preserved.

## Isolation contract
ClubNeon_Config.lua is the only approved source of target-specific identity and policy. All Club Neon runtime variants must read the config or be generated from an explicit reviewed transformation manifest. Do not copy Tiki Tide IDs, names, datastore keys, endpoints, or permissions.

Safe defaults:
- GroupId = 0; group integration disabled.
- Owner/staff UserId arrays empty; live installation must stop until owner list is configured.
- Monetization disabled; every pass/product ID is zero and cannot be prompted.
- Unique ClubNeon_v1 datastore namespace.
- Global moderation/announcements/catalog invalidation/receipt coordination enabled in the feature contract, subject to adaptation and runtime verification.
- Playback is server-local: queue, playback clock, Auto DJ cursor, and skip votes are per-server. Cross-server playback sync is explicitly false.
- Studio owner bypass is false; no broad everyone-is-owner testing mode.

## Source-level blockers verified

### Controller
UI_Server_Controller_server (1).lua embeds Tiki Tide group ID 500470662; passes 2089785323, 2089263330, 2087955353; XP passes 2088891595, 2089053637; products 3731386650, 3731387153, 3731392651, 3731394060; project-scoped DataStoreName; EnableGlobalPlaybackSync = true; Tiki Tide permission attributes, endpoint names, labels, dance-floor tag, and pass-tier labels.
A Club Neon controller variant must use ClubNeon_Config, replace the playback-sync surface with a hard local-only implementation, and use Club Neon-specific namespaced endpoints/attributes. A false default is insufficient if stale persisted config or dormant leader-election code can still activate.

### UI renderer
UI_Renderer (2).lua hardcodes Tiki Tide pass/product IDs, donation items, pass descriptions, tier names, settings-open attributes, utility actions, and UI labels. It must become config-driven; no Tiki Tide pass/product IDs or donation catalog may survive. Zero/unconfigured IDs must hide or disable purchase actions.

### Global service
ClubMusic_Global_Service_server_1.lua contains Tiki Tide-specific security endpoint names, group authorization context, diagnostics labels, and a separate global-config store. The Club Neon variant must use ClubNeon_Config and ClubNeon_v1 stores; register only Club Neon-specific API names; bind global moderation/announcement/catalog/receipt functions to Club Neon authorization; keep playback sync hard-disabled and omit/neutralize leader/lease/snapshot writes; never share Tiki Tide stores.

### Settings, social actions, utility bar
Settings client/server, social actions, and utility bar use TikiTide* names for remotes, attributes, endpoints, entitlement attributes, and UI text. They require an explicit project namespace migration (for example ClubNeon*) updating producers and consumers together. Utility bar features must retain server-authoritative entitlement and movement checks.

### Tool shop
UtilityBar/ToolShop.server.lua currently opens TikiTideCoins_v1; migrate to ClubNeon_v1_ToolShopCoins and the same player identity/profile isolation contract.

## Runtime source inventory
Candidates include core controller/renderer/network/bootstrap/error handler/overhead renderer; five modern audio modules plus player preferences and MusicCoreService/MusicPlaylistService; ClubMusicSecurityCore modules and SecurityServer/StaffActions/client telemetry/Kohl's adapters; global service/config/diagnostics/maintenance/safe-call/security/registry/watchdog/health plus allowlisted embedded services; settings, social actions and nested AnimationConfig; UtilityBar client/actions/panels/extended server actions/ToolShop; staff spectator and diagnostics clients.
This list is not a complete dependency graph. Exact source pins, package extraction allowlist, class/parent placement, nested children, and requires/remote ownership must be reconciled before installer manifest generation.

## Preserve / exclude
- Preserve Workspace.Kohl's Admin and all descendants. Add reviewed adapters only into already-existing documented addon folders after package contract validation; never fabricate or replace Kohl's Admin.
- Preserve ReplicatedStorage.InteractionAnims and all three KeyframeSequence assets.
- Preserve map, lighting, audio, and unrelated game scripts.
- Do not delete or overwrite the two Hello world scripts until owner confirms they are disposable.
- Never install MusicGlobalPlaybackAuthority, playback leader leases, shared playback snapshots, or shared playback queue.
- Do not install rollback-only legacy audio modules or guessed source paths.

## Required owner configuration before live install
1. Owner UserId(s), plus any Co-owner/Admin/Moderator/DJ UserId(s).
2. Optional Club Neon Roblox group ID and intended rank thresholds.
3. Club Neon-owned pass and developer-product IDs, or explicit confirmation to keep monetization disabled.
4. Final display brand and tier labels if different from defaults.
5. Confirm global moderation and announcements for production (currently selected in the config contract).

## Release gates
1. Complete source dependency and exact placement audit.
2. Produce reviewed Club Neon variants for controller, renderer, global service, settings, social actions, utility bar, and tool shop.
3. Add deterministic manifest with immutable source pins and per-file SHA-256 checks.
4. Keep installer read-only by default; stage all sources and validate every target path/class before promotion.
5. Preserve/backup conflicting repository-owned scripts; stop on ambiguous or third-party-owned paths.
6. Test in unpublished copy: compile, startup/shutdown, audio transitions and controls, queue isolation, UI, staff authorization, security failure modes, global operations, datastore isolation, mobile/desktop behavior.
7. Only then enable transactional install; never remove legacy audio until modern playback is stable.

**Current release state:** configuration contract and compatibility audit are committed artifacts; this does not install runtime scripts or modify the Club Neon place.

## Runtime adaptation delivered

The full-feature source variants are now committed, without overwriting the Tiki Tide originals:

- Core UI: `ClubNeon_UI_Server_Controller.server.lua`, `ClubNeon_UI_Renderer.lua`, `ClubNeon_UI_Network.lua`, and `ClubNeonBootstrap.client.lua`.
- Modern audio: the pinned shared AudioPlayer/crossfade modules, MusicCoreService, MusicPlaylistService, and client preferences.
- Security: a dedicated `ClubNeonSecurityCore/` package (32 runtime modules), Club Neon security server/staff scripts, client telemetry, security console, spectator camera, adaptive visual client, and a dedicated staged Security Core installer.
- Global operations: `ClubNeon_Global_Service.server.lua` and the shared operational modules, using Club Neon-specific stores/topics and the Club Neon Security Core authorization singleton.
- Settings/social: Club Neon settings client/server, social actions client/server plus its nested AnimationConfig, and the unified launcher.
- Utility bar: Club Neon client/server variants, including dynamic server-configured pass IDs and a Club Neon Tool Shop DataStore.
- Optional Kohl's Admin adapters: separate Club Neon variants only. The installer will add them only if the expected add-on folders exist; it never creates or replaces Kohl's Admin.

## Isolation and safety checks in the current source

- Controller and global services load `ServerStorage.ClubNeon_Config`; missing or malformed configuration stops startup.
- Controller purchase IDs are zero unless `Monetization.Enabled = true`; pass/product IDs are then read from the Club Neon config. The renderer and utility bar receive server-configured IDs instead of embedding Tiki Tide IDs.
- Owner, co-owner, admin, moderator, and DJ UserId lists are supported by the Club Neon Authorization module. Studio owner bypass defaults off.
- Global authorization, settings, staff actions, and the optional Kohl's adapter use the same role lists and rank thresholds.
- Playback sync is hard-disabled in the controller and global service. Queue, playback clock, Auto DJ cursor, and skip votes remain per-server.
- The master installer checks for inherited Tiki Tide product/group IDs, checks the local-only playback marker and remote folder contract, and pins all runtime source fetches to immutable commits.
- The master installer is v0.3.0, source-based, transactional, and defaults to `DRY_RUN = true`. It backs up replaced repository-owned instances and preserves unknown descendants. It does not require an .rbxl export.

## Remaining release blockers

1. Populate `OwnerUserIds` with the actual Club Neon owner UserId(s). Optional direct staff lists and GroupId can be added at the same time.
2. Keep monetization disabled, or add verified Club Neon pass/product IDs and explicitly set `Monetization.Enabled = true`.
3. Run installer v0.3.0 in Club Neon Studio with `DRY_RUN = true`; review every planned destination and skipped optional adapter.
4. Only after review, use a backed-up unpublished copy and set `DRY_RUN = false` for transactional promotion.
5. Run the complete compile/startup, UI, modern playback/crossfade, queue, staff/security, purchase, DataStore isolation, global moderation/announcement, and mobile/desktop regression suite.

The audited Kohl's Admin package is under `Workspace` in the supplied inventory, while the installer checks the documented server-side add-on locations under `ServerScriptService`. Therefore the optional adapters will be skipped unless a supported add-on path is verified; the existing package remains untouched.

**Current release state:** source variants and installer are committed to the repository. No Club Neon place has been modified, and runtime behavior has not yet been verified in Roblox Studio.
