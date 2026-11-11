# Sultan Settings Add-on

This add-on is intentionally separate from the ClubMusic renderer and overhead title renderer.

## Install

1. Add `SultanSettingsService.server.lua` as a **Script** under `ServerScriptService`.
2. Add `SultanSettings.client.lua` as a **LocalScript** under `StarterPlayer > StarterPlayerScripts`.
3. Keep the existing `ClubMusicBootstrap.client.lua`, `UI_Network`, `UI_Server_Controller`, and `ClubMusic_Overhead_Title_Renderer_client.lua` unchanged.
4. Install the updated `UI_Renderer (2).lua` from this branch in place of the current ClubMusic UI renderer. It contains the small shared-state bridge that coordinates the compact HUD and floating launcher with Sultan Settings; do not install it as a second parallel renderer.
5. Ensure there is exactly one copy of `SultanSettingsService.server.lua` and one copy of `SultanSettings.client.lua`. Duplicate service copies compete for the same `RemoteFunction.OnServerInvoke` callback and can create duplicate event listeners.
6. Publish/test in a private test place first.

The server add-on creates `ReplicatedStorage/SultanSettingsRemotes` itself. It reads the server-owned `IsTikiTideSultan` player attribute set by the existing ClubMusic controller, and uses the existing server-only `ClubMusicAuthorizationResolver` for privileged gravity and announcement actions.

**Required entitlement configuration:** In the existing `UI_Server_Controller` configuration, set `TikiTideSultanPassId` to the real Sultan Game Pass asset ID before testing pass-holder access. Its current value in the audited source is `0`, which disables Game Pass ownership grants. Existing verified staff rank level 1+ still receives Sultan-tier access. Sultan pass ownership alone does not grant administrator permissions: gravity requires `GlobalConfig` (rank level 3+) and announcements require `GlobalAnnouncement` (rank level 2+).

## Included

- Sultan-only walk speed (20–100) and jump power (80–300), applied on respawn only for verified Sultan players.
- AFK state and filtered AFK message replicated as `SultanAFK` and `SultanAFKMessage` attributes.
- Opt-in teleport-to-me permission; teleport requests are validated on the server.
- Gravity control (20–192.62) restricted to ClubMusic `GlobalConfig` permission.
- Admin overhead broadcasts and server announcements restricted to `GlobalAnnouncement`; announcements have a 180-second server-wide cooldown.
- Separate Settings / Players / Message panel. Existing custom overhead titles, title slots, fonts, effects and collection tags remain in ClubMusic → Title Tag.
- Gamepad navigation for selectable tabs, actions and text fields, with gold focus feedback, automatic vertical scroll-to-selection, and B / Escape back handling. TextBox focus is allowed to handle the console virtual keyboard.

## Important scope notes

- This add-on does not modify the existing ClubMusic profile schema or title renderer.
- Movement and AFK preferences are session-scoped; they reset when the player leaves.
- Gravity affects the whole current server, not every server in the experience.
- Announcement cooldown is server-local, not cross-server.
- The existing controller must be running so its verified Sultan attribute and authorization resolver are available. The Sultan service can create its remotes independently, but privileged administrator actions fail closed until the controller's resolver exists.
- Install order: existing ClubMusic controller and its required modules first, then the Sultan server service and client LocalScript. The scripts may start in Roblox's normal scheduling order, but the controller must finish initialization before testing administrator-only actions.
- If the Sultan GUI is destroyed or replaced while open, its cleanup restores the compact ClubMusic HUD state and releases its controller back binding.
- Privileged actions re-check Sultan/admin authorization after text filtering or other yielding permission checks; broadcast cooldowns are checked again immediately before sending.

## Controller test checklist

In Roblox Studio with a gamepad connected, verify D-pad / thumbstick selection across all tabs and controls, gold focus visibility, scrolling through long player lists, A-button activation, text entry through the console keyboard, confirm focus stays on the text field when the keyboard opens and returns when it closes, B to dismiss the keyboard before closing the panel, and B again to close the panel. On Settings, apply movement and toggle AFK / teleport permissions; confirm focus returns to a valid control after any page rebuild. On Players, filter the roster and confirm hidden rows disappear without leaving navigation gaps, the list resizes to the visible matches, and focus moves to Search if the selected row is filtered out. Trigger a denied teleport request and confirm focus returns to that row's action button. Also test closing/replacing the Sultan GUI while open and confirm the compact HUD is restored; revoke Sultan access during a pending filtered message and confirm the request is rejected; submit simultaneous broadcasts and confirm cooldowns are not bypassed. Verify touch and mouse input remain functional. Controller support is implemented in the client UI but still requires runtime testing on the target console.

## Pass creation status and Studio test mode

The Tiki Tide Sultan Game Pass has **not been created yet**. Keep `TikiTideSultanPassId = 0` until the real pass is published and its asset ID is available. A zero ID intentionally disables Sultan Game Pass ownership grants; do not use a placeholder or another pass ID.

The current controller configuration has `StudioStaff = true`. In Studio, that setting treats **every test player as OWNER**, which also grants Sultan-tier access through the server-verified staff path even while the Sultan pass ID is zero. This is useful for testing the Sultan interface, but it is **not** a valid guest-access or pass-ownership test. To test guest denial in Studio, temporarily set `StudioStaff = false`; with `GroupId = 0` and no matching `StaffUserIds`, Studio players will then be guests. Restore the intended production setting before publishing. Once the pass is created, configure only its actual asset ID and verify ownership in a published private test server.


## Deployment readiness checklist

Before publishing to the live experience:

- [ ] Replace the existing ClubMusic renderer with this branch's updated `UI_Renderer (2).lua`; do not run both renderer copies.
- [ ] Confirm the existing ClubMusic server controller and all of its required ServerStorage modules are installed exactly once.
- [ ] Install exactly one Sultan server Script and one Sultan client LocalScript at the paths listed above.
- [ ] Keep `TikiTideSultanPassId = 0` until the Sultan Game Pass is actually created and published.
- [ ] Set `StudioStaff = false` when validating guest denial in Studio; its current `true` value grants OWNER/Sultan test access to every Studio player.
- [ ] Test staff access, guest denial, entitlement revocation, respawn, and controller/UI transitions in a private test place.
- [ ] After the Game Pass exists, add its real asset ID and verify a real owner and a non-owner in a published private server.
- [ ] Test keyboard, touch, mouse, and a physical console controller. Do not treat responsive sizing or source-level focus wiring as proof of console runtime compatibility.
- [ ] Check server/client output for missing remotes, duplicate scripts, TextService filtering failures, and controller resolver startup errors.
- [ ] Only publish after all applicable checks pass; pass-owner and live console checks remain blocked until the pass exists and target-device testing is performed.
