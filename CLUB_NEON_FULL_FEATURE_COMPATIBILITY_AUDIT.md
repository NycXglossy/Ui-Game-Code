# Club Neon Full-Feature Integration — Compatibility Audit

**Decision:** Owner selected the full feature set on 2026-11-20.
**Target:** Club Neon | **Branch:** integration/tiki-tide-system-consolidation
**Status:** configuration contract created; runtime adaptation and installation remain gated.

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