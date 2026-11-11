# Sultan Settings Add-on

This add-on is intentionally separate from the ClubMusic renderer and overhead title renderer.

## Install

1. Add `SultanSettingsService.server.lua` as a **Script** under `ServerScriptService`.
2. Add `SultanSettings.client.lua` as a **LocalScript** under `StarterPlayer > StarterPlayerScripts`.
3. Keep the existing `ClubMusicBootstrap.client.lua`, `UI_Network`, `UI_Renderer`, `UI_Server_Controller`, and `ClubMusic_Overhead_Title_Renderer_client.lua` unchanged.
4. Publish/test in a private test place first.

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
- The existing controller must be running so its verified Sultan attribute and authorization resolver are available.
- If the Sultan GUI is destroyed or replaced while open, its cleanup restores the compact ClubMusic HUD state and releases its controller back binding.
- Privileged actions re-check Sultan/admin authorization after text filtering or other yielding permission checks; broadcast cooldowns are checked again immediately before sending.

## Controller test checklist

In Roblox Studio with a gamepad connected, verify D-pad / thumbstick selection across all tabs and controls, gold focus visibility, scrolling through long player lists, A-button activation, text entry through the console keyboard, confirm focus stays on the text field when the keyboard opens and returns when it closes, B to dismiss the keyboard before closing the panel, and B again to close the panel. On Settings, apply movement and toggle AFK / teleport permissions; confirm focus returns to a valid control after any page rebuild. On Players, filter the roster and confirm hidden rows disappear without leaving navigation gaps, the list resizes to the visible matches, and focus moves to Search if the selected row is filtered out. Trigger a denied teleport request and confirm focus returns to that row's action button. Also test closing/replacing the Sultan GUI while open and confirm the compact HUD is restored; revoke Sultan access during a pending filtered message and confirm the request is rejected; submit simultaneous broadcasts and confirm cooldowns are not bypassed. Verify touch and mouse input remain functional. Controller support is implemented in the client UI but still requires runtime testing on the target console.
