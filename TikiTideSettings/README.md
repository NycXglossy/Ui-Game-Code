# Tiki Tide Settings, Social Actions, and Unified Launcher

## Scope

This add-on is installed alongside the existing ClubMusic UI and Security Core. It does not replace the ClubMusic renderer, title renderer, audio system, or server controller. Install the updated renderer below as a replacement for the existing renderer ModuleScript; do not run two renderer copies.

## Required scripts and placement

| File | Roblox placement | Purpose |
|---|---|---|
| `UI_Renderer (2).lua` | ModuleScript: `ReplicatedStorage/UI_Renderer` | Existing ClubMusic UI plus the main-menu open bridge used by the unified launcher |
| `UI_Server_Controller_server (1).lua` | Script: `ServerScriptService` | Existing server-authoritative ClubMusic controller and Tiki Tide entitlement source |
| `ClubMusic_Security_Core_Installer.lua` | Script: `ServerScriptService` | Installs the pinned Security Core modules and staff spectator adapter |
| `ClubMusic_Global_Service_server_1.lua` | Script: `ServerScriptService` | Global service; its expected Security Core release must match the installer |
| `TikiTideSettings/TikiTideSettingsService.server.lua` | Script: `ServerScriptService` | Server-side Settings, Players, and Message actions |
| `TikiTideSettings/TikiTideSettings.client.lua` | LocalScript: `StarterPlayer/StarterPlayerScripts` | Settings UI |
| `TikiTideSocialActions.server.lua` | Script: `ServerScriptService` | Server-authoritative dances and consent-based duo actions |
| `TikiTideSocialActions/AnimationConfig.lua` | ModuleScript: child folder `TikiTideSocialActions` under the Social Actions server Script | Owned animation asset IDs |
| `TikiTideSocialActions.client.lua` | LocalScript: `StarterPlayer/StarterPlayerScripts` | Social Actions UI and invitation prompts |
| `TikiTideUnifiedLauncher.client.lua` | LocalScript: `StarterPlayer/StarterPlayerScripts` | Single entry point for Main UI, Social Actions, Settings, and Staff Console |
| `SecurityServer.server.lua` | Script: `ServerScriptService` | Creates security remotes, applies server authorization, and dispatches staff alerts |
| `SecurityClient.client.lua` | LocalScript: `StarterPlayer/StarterPlayerScripts` | Displays staff alerts and submits player reports |
| `SecurityConsole.client.lua` | LocalScript: `StarterPlayer/StarterPlayerScripts` | Staff Console presentation; it does not authorize staff |
| `StaffActions.server.lua` | Script: `ServerScriptService` | Server-side staff action adapter |
| `RegularCommandsSecurityServer.lua` | Script: `ServerScriptService` | Server-side protected command adapter |

The SecurityClient, SecurityServer, SecurityConsole, Settings server service, and other listed base scripts already exist in the selected integration base. Keep exactly one copy of each. The social scripts and unified launcher are additional scripts.

## Release alignment

The Security Core installer pins its main module release to:

`7ebc71e3a6fa9ef04e80d5f332e5f72617c8d288`

The Global Service's `EXPECTED_SECURITY_CORE_RELEASE` must use that exact same identifier. The installer separately pins the Phase 32 module bundle to:

`6ae4883c2c260df61bf760b8637dd339bda33d7b`

Do not change one pin independently. The Global Service rejects a present but mismatched Security Core manifest.

## Runtime bridges and remotes

- The renderer creates or reuses `PlayerGui/TikiTideOpenMainUI`, connects its open callback, and sets its `Ready` attribute. The unified launcher waits for that readiness before firing the BindableEvent.
- The Settings server service creates `ReplicatedStorage/TikiTideSettingsRemotes`; the client listens for the launcher's `TikiTideSettingsOpenRequest` and `TikiTideSettingsCloseRequest` PlayerGui attributes.
- The Social Actions server creates `ReplicatedStorage/TikiTideSocialRemotes` with `Request` and `Event` RemoteEvents.
- The Security server creates `ReplicatedStorage/SecuritySystem` with `StaffAlert` and `ReportIncident` RemoteEvents.
- The Staff Console client creates `StaffConsoleGui` and `StaffConsoleLauncher`; the unified launcher only displays its entry after the client reports `StaffAuthorized = true`. The server still checks every protected action.

## Security boundaries

- Client launchers, menus, notifications, and report controls are presentation/input surfaces only.
- Security Core Authorization, the ClubMusic controller, SecurityServer, Settings server service, Social Actions server service, and StaffActions server adapter enforce permissions and validate requests on the server.
- Social Actions accepts only named actions; clients cannot submit animation asset IDs. Duo hugs require both players to have Tiki Tide access, a live character, and proximity within 12 studs. Invitations expire after 20 seconds and are revalidated on acceptance.
- Settings privileged gravity and announcement actions use server-side ClubMusic permissions. Tiki Tide pass ownership does not itself grant staff permissions.
- SecurityClient's local report helper does not authorize or adjudicate reports; SecurityServer validates and routes them.
- Do not expose server-only BindableFunctions to clients.

## Configuration that must be completed

### Social animation assets

Set numeric IDs that the experience/group owns in `TikiTideSocialActions/AnimationConfig.lua`:

- `Dance1`
- `Dance2`
- `VIPDance`
- `HugActor`
- `HugTarget`

The checked-in values are currently `0`. Unconfigured animations fail closed and show an unavailable message. No animation assets are created or uploaded by these scripts.

### Tiki Tide entitlement

The selected controller source currently configures `TikiTidePassId = 2087955353`. Verify the asset ID and ownership in a published private test server before release. The Settings service reads the server-owned entitlement attribute set by the controller; it does not trust a client-provided pass claim.

### Studio testing

The controller source has `StudioStaff = true`. In Studio this treats test players as OWNER for testing. It is not a valid guest-denial or pass-ownership test. Temporarily set `StudioStaff = false` when testing guest denial, then restore the intended production setting.

## Install and test order

1. Install the pinned Security Core installer and verify the installed manifest reports the matching release IDs above.
2. Install the ClubMusic controller, Global Service, and the single updated renderer ModuleScript.
3. Install one Settings server Script and one Settings client LocalScript.
4. Install the Social Actions server Script with its child `TikiTideSocialActions/AnimationConfig` ModuleScript, plus one Social Actions client LocalScript.
5. Install one SecurityServer, SecurityClient, SecurityConsole, StaffActions, and RegularCommandsSecurityServer.
6. Install the unified launcher LocalScript. It hides the old main-menu, Social Actions, and Staff Console launch buttons; Settings' retired floating launcher remains hidden.
7. Test server authorization, guest denial, entitlement revocation, Settings open/close transitions, social invite accept/decline/expiry/cancel, proximity checks, malformed/flooded requests, staff alerts, report routing, spectator entry/exit/stealth restoration, and respawn/departure cleanup.
8. Test mouse, keyboard, touch, gamepad, desktop, tablet, and mobile layouts. Do not treat source-level support as proof of device runtime compatibility.

## Known integration boundary

The selected base Global Service currently marks cross-server playback synchronization as retired and uses per-server playback and request queues. This branch does not silently reintroduce the older full global queue. The requested optional playback-only synchronization with independent local request queues remains a separate merge item and must be restored by reconciling its authority, lease, and queue changes against this Security Core release.

## Verification status

This is a source integration. No Roblox Studio or published-server runtime test is claimed. Complete the test plan above before publishing.
