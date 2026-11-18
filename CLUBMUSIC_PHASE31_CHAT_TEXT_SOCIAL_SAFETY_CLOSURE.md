# Phase 31 — Chat, Text & Social Safety Closure

## Status

Tracked-source audit and targeted hardening are implemented on `fix/security-core-release-and-queue-loop`. This phase is not runtime-certified. Native Roblox chat remains a platform responsibility; third-party Kohl's Admin message handlers and live-place-only scripts remain outside the verified source boundary.

## Scope and authority

- Security Core `Authorization` remains the sole staff permission authority.
- Roblox `TextService` broadcast filtering is used for experience-owned player-authored text that is replicated or shown to multiple players.
- Roblox `TextChatService` remains responsible for native Roblox chat moderation and filtering. This phase does not replace, intercept, or weaken native chat.
- No raw player-authored text is used as a fallback when filtering fails.
- Teleport consent is a session preference with default-deny behavior. Explicit `GlobalModeration` authority is the existing staff override.
- No new remote, permission system, profile field, DataStore, or persistent text cache was introduced.

## Audited text and social surfaces

### ClubMusic custom titles and title tags

File: `UI_Server_Controller_server (1).lua`

- Legacy custom title and extended title-slot saves use `TextService:FilterStringAsync` followed by `GetNonChatStringForBroadcastAsync` before profile storage or replicated attributes.
- Persisted title slots are re-filtered before they are selected or exposed through Player attributes. A failed filter keeps the saved text server-side and hides the replicated title.
- The overhead title renderer consumes server-owned attributes only, escapes RichText special characters, and maps collection tag IDs to fixed labels/styles. It does not accept a text remote or grant authority.
- Title style, font, effect, slot, and color values are constrained by server allowlists.
- **Phase 31 hardening:** the shared title filter now rejects invalid UTF-8 and over-limit input before calling TextService. Save and slot-selection paths re-check live profile ownership, Tiki Tide entitlement, and unlocked-slot access after the yielding filter call and before committing/replicating the title.
- Collection title tags are fixed server-owned cosmetics, not arbitrary player-authored text.

### Tiki Tide AFK text, local announcements, and overhead bubbles

File: `TikiTideSettings/TikiTideSettingsService.server.lua`

- AFK text is filtered for broadcast before it is stored in session settings and replicated through `TikiTideAFKMessage`. Filtering failure leaves it unset; no raw text fallback exists.
- The tracked Tiki Tide settings UI reads the AFK message from the settings snapshot. No tracked overhead renderer consumer for `TikiTideAFKMessage` was found in this repository snapshot; any map-specific AFK display script must be checked in the live place.
- Local announcements and overhead bubble broadcasts use the same server-side broadcast filter and UTF-8-safe output truncation.
- Both announcement paths require Security Core `GlobalAnnouncement`, re-check the live actor and permission after filtering, then apply cooldowns before broadcasting.
- Existing limits: 180-second local announcement cooldown; 5-second per-player bubble cooldown; 0.25-second settings request cooldown; bounded server-wide ingress token bucket (48 capacity, 24 tokens/second).
- Text is passed to clients as plain text; the client does not enable RichText for these broadcast labels.

### Cross-server announcements

File: `ClubMusic_Global_Service_server_1.lua`

- `PublishAnnouncement` requires a valid positive actor UserId, a live Player in the publishing server, and Security Core `GlobalAnnouncement` permission before filtering.
- The publishing server filters with `TextService`, rechecks that the same actor remains live and authorized, then publishes only filtered text.
- Receiving servers validate the MessagingService envelope, message schema, and replay ID before raising the local announcement event. They do not re-filter the trusted publisher's already-filtered result.
- Filter failure or actor departure/permission loss before publish fails closed.

### Shared maintenance message

File: `ClubMusic_Global_Service_server_1.lua`

- **Phase 31 hardening:** the shared `maintenanceMessage` config path previously accepted a bounded string but did not itself require TextService filtering.
- Both `SetGlobalConfig("maintenanceMessage", ...)` and `SetGlobalMaintenance(..., message, ...)` now filter non-empty text for broadcast before shared persistence/publication.
- The actor must be a live server Player with `GlobalConfig` permission before and after the yielding filter call.
- When maintenance is toggled without supplying a replacement message, the existing persisted message is re-filtered before it is republished. An empty string remains an intentional clear operation.
- Filtering or authorization failure prevents the config update; there is no raw-text fallback.

### Player-to-player teleport

File: `TikiTideSettings/TikiTideSettingsService.server.lua`

- Teleport consent defaults to false and is session-scoped. The recipient explicitly enables or disables `TikiTideAllowTeleport`.
- The actor must have server-resolved Tiki Tide access. The recipient must be a different live Player with a living character, unless the actor has Security Core `GlobalModeration` permission (existing staff override).
- Actor, recipient, character identities, and consent are rechecked after authorization checks and before movement.
- The destination comes only from the server-observed recipient HumanoidRootPart CFrame; the client supplies only a target UserId.
- `TeleportValidationService` must be available. The server creates and completes a one-use teleport ticket; no raw client destination is accepted.
- Existing actor cooldown is 2 seconds and recipient cooldown is 3 seconds. Both are reserved before movement to close concurrent duplicate requests and are released if ticket creation or movement fails.
- PlayerRemoving clears consent/session state and cooldown records.

### Staff player-control and message commands

File: `RegularCommandsSecurityServer.lua`

- The tracked Kohl's adapter gates `announce`, `unannounce`, `hint`, `message`, `fullmessage`, and `privatehint` through Security Core permissions and a bounded Broadcast budget.
- `bring`, `tp`, `to`, and `place` are permission-gated teleport/control commands; target arguments are validated through shared `SanityValidation.ValidatePlayerTargets` with a maximum of eight targets.
- Moderation commands such as mute/unmute, kick, ban/unban are separately gated by `GlobalModeration` and bounded moderation budgets.
- The adapter validates targets before handing off to native Kohl's handlers. The native package implementation is external to this source snapshot; its post-yield target revalidation and its own message text filtering were not verified here.

## Native Roblox chat boundary

- No custom player-to-player chat remote or experience-owned general chat replacement was found in the reviewed controller, UI network, Tiki Tide settings, and Utility Bar sources.
- Native Roblox chat filtering and moderation remain owned by Roblox `TextChatService` / platform chat systems.
- This phase does not claim that third-party scripts, plugins, runtime-inserted models, or the live place contain no additional chat or text remotes.

## Source-level verification

- [x] Custom title saves and persisted title selection filter before replication.
- [x] Title input is bounded and UTF-8 validated before TextService.
- [x] Title entitlement and slot access are rechecked after filtering yields.
- [x] Tiki Tide AFK, local announcement, and bubble text use server-side broadcast filtering.
- [x] Cross-server announcements are filtered by the trusted publisher and receiver envelopes are validated.
- [x] Shared maintenance message writes now filter before persistence/publication, including the no-new-message toggle path.
- [x] Tiki Tide teleport uses explicit recipient opt-in, live target/character checks, server-observed destination, a validation ticket, and actor/recipient cooldowns.
- [x] Staff social/admin commands are routed through Security Core permissions and bounded budgets in the tracked adapter.
- [x] No new remote, profile schema, persistent text store, or parallel permission authority was introduced.

## Required runtime and external verification

Roblox Studio and published-server tests remain required:

1. Submit normal, emoji, multi-byte, invalid UTF-8, empty, whitespace-only, and oversized title/AFK/announcement/bubble/maintenance strings.
2. Force TextService failures for every experience-owned text path; confirm no raw text is saved, replicated, or broadcast.
3. Revoke Tiki Tide access while a title filter request is yielding; confirm save/selection does not commit.
4. Revoke announcement/config permission or remove the actor while filtering is yielding; confirm no broadcast/config write occurs.
5. Verify persisted legacy title and maintenance strings are re-filtered before display/publication.
6. Test local announcement cooldown, bubble cooldown, settings ingress limits, and cross-server announcement replay/schema rejection.
7. Test teleport consent off/on/revoked during request, actor/recipient departure, respawn during authorization, dead characters, concurrent callers, cooldown recovery, staff override, and TeleportValidationService unavailable/failure paths.
8. Test Kohl's announce/hint/message/fullmessage/privatehint filtering, target departure during native handler execution, and staff permission changes against the installed package.
9. Verify native `TextChatService` is configured/enabled in the live place and normal chat filtering remains intact.
10. Search the actual published place, package descendants, plugins, and runtime-created instances for additional TextBoxes, custom messages, BubbleChat, announcement, teleport, and player-target remotes.

## Certification limits

- Repository source inspection only; no Roblox Studio runtime or Luau parser was available.
- No published-server or multi-server tests were run.
- Kohl's Admin native announcement/private-message handlers and binary package descendants were not inspected sufficiently to certify their filtering implementation.
- Live-place-only scripts and map-specific AFK display consumers remain unverified.
- No live player profiles or persistent data were modified by this phase.
