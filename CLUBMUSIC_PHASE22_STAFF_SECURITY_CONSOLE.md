# Phase 22 — Staff Security Console

**Status:** Revised graphical Staff Console source is committed on the Phase 22 feature branch. Existing Kohl's Admin commands and server-side authorization remain the execution foundation.

## Staff spectator commands

- ;cmspectate <UserId> — enter observation mode for a live player.
- ;cmspectateswitch <UserId> — switch the current observation target.
- ;cmspectateoff — exit and restore the staff character's saved movement settings.
- ;cmspectatestate — inspect the current target.

## Security path

1. Kohl's Admin registers these commands in its Administration group.
2. The addon accepts only an online Player caller and invokes the server-only ServerStorage.ClubMusicAdminBridge.
3. The controller checks the caller through SecurityCore GlobalModeration before invoking the spectator control endpoint.
4. TikiTideStaffSpectatorControl is a ServerStorage BindableFunction, not a client remote.
5. StaffSpectatorService independently rechecks live Player identity and SecurityCore authorization for each operation.
6. Existing spectator lifecycle audit/replay records remain in place.

The status command is read-only and uses the same SecurityCore permission gate. Read-only command throttling and bounded output are inherited from the shared admin addon.

## Preserved boundaries

- The staff avatar remains visible in the world; this is not invisibility, noclip or untraceable mode.
- No notification is automatically sent to the observed player by this feature.
- TikiTideSpectatorNoWorldActions is a server-owned attribute for gameplay services to honor; not every gameplay service has yet been proven to consume it. Do not describe this as a universal action lock.
- Camera following is client presentation only; it cannot authorize observation.
- The original spectator-command slice introduced no UI changes; the revised graphical console is documented below.
- Diagnostics, replay, threat review and incident commands retain their existing independent permissions.

## Test checklist

- [ ] Enter, switch, query state and exit for authorized staff.
- [ ] Reject ordinary players, DJ-only rank, invalid IDs, self-targeting, offline targets and targets without a living character.
- [ ] Test staff departure, target departure, respawn, shutdown, camera replacement and movement restoration.
- [ ] Verify the observed player cannot use spectator attributes to grant themselves privileges.
- [ ] Verify no client can invoke ServerStorage endpoints.
- [ ] Confirm the four commands appear only in the intended Kohl's Admin command group.
- [ ] Regress ClubMusic playback, purchases, queue, UtilityBar, Settings and PC/mobile/console camera behavior.

**Future console work:** a dedicated graphical staff console is intentionally not introduced in this phase. The command bridge avoids a new client-facing security surface while the service is validated.


---

---

## Revised graphical ClubMusic command console

**This section supersedes the earlier placeholder Lockdown + Kick-only UI description above.**

Phase 22 now presents existing ClubMusic admin commands as a graphical console. It does not replace the command handlers or create a second moderation/security service.

### Main ClubMusic UI changes

- The **Clear Queue** control is removed from the main DJ Booth and is available from the Staff Console.
- The main **Moderation** tab is now visible only to the Owner tier. It retains owner pass-tier award/reset controls, but no longer exposes player request blocking or queue purging.
- Player request moderation, punishment actions, security investigation, incident handling, operational diagnostics, and administrative queue actions belong in the Staff Console.
- Normal music browsing, requests, queue viewing, and DJ playback controls remain in the main ClubMusic UI.

### Graphical console categories

- **Playback:** skip, pause/resume, restart, request lock, status, queue view/removal/clear, emergency request lock, emergency stop.
- **Requests:** request mute/unmute, clear a player's requests, track block/allow, request moderation history.
- **DJ Sessions:** status, start, handoff, end.
- **Moderation:** warn, restrict, temporary/permanent ban, suspected-alt propagation, unban, unrestrict, punishment history, account-risk review.
- **Security:** status, incidents, replay, threat intelligence, staff observation, threat-case escalation, incident open/resolve, security policy.
- **Diagnostics:** health, diagnostic snapshot, purchase diagnostics, services, errors, metrics, audit log, rate limits, config, recovery, reconciliation, catalog refresh, maintenance status.

The console uses action buttons and context-labelled fields rather than requiring staff to type Kohl's Admin command syntax. Destructive/high-impact actions require a second confirmation click. Existing Kohl's Admin commands remain available as a fallback.

### Security and execution path

1. The client sends a fixed UI action key and a bounded argument string.
2. `StaffActions.server.lua` maps that key to a fixed allowlisted `ClubMusicAdminBridge` operation. Arbitrary operation names from the client are rejected.
3. The server records request and completion/rejection events through the existing `TikiTideSecurityReplay` endpoint. If the audit endpoint is unavailable, the GUI command is not executed.
4. The server invokes the existing server-only `ServerStorage.ClubMusicAdminBridge`.
5. The controller's existing staff check, per-operation rank/permission checks, validation, service calls, and action scopes remain authoritative. The UI does not grant permissions.
6. Existing global commands retain their original scopes. The separate door lockdown remains current-server-only and does not use MessagingService, MemoryStore, or DataStore.

### Installation

- Install the updated `StaffActions.server.lua` under `ServerScriptService`.
- Install the updated `SecurityConsole.client.lua` under `StarterPlayer/StarterPlayerScripts`.
- The LocalScript creates `StaffConsoleGui` at runtime; no manually authored ScreenGui hierarchy is required.
- Keep the updated `UI_Renderer (2).lua` as the main ClubMusic UI renderer.
- Ensure the Phase 21/24 Security Core, controller, `ClubMusicAdminBridge`, and `TikiTideSecurityReplay` are installed.

### Acceptance checklist

- [ ] Authorized staff ranks can open the console; non-staff cannot execute commands even if they manually fire the RemoteEvent.
- [ ] Every GUI action maps to one fixed server allowlist entry; unknown keys and malformed arguments are rejected.
- [ ] Controller permission checks still reject actions beyond the caller's rank.
- [ ] Request, completion, and rejection audit events appear in the existing replay timeline.
- [ ] Missing bridge or audit endpoint fails closed.
- [ ] Existing Kohl's Admin command aliases still work.
- [ ] Main UI no longer exposes Clear Queue or player block/purge controls.
- [ ] Owner pass-tier award/reset functionality remains available.
- [ ] Local lockdown affects only the current server and restores original door settings.
- [ ] Test playback, requests, queue, DJ sessions, moderation, security, diagnostics, and PC/mobile UI in Studio before release.

**Release boundary:** Source-only feature branch. No Studio/runtime test, published multiplayer test, merge, or live deployment has been performed.


**Moderation boundary clarification:** The earlier standalone `KickPlayer` console action has been removed from the revised Phase 22 server surface. Staff moderation is routed through the existing Phase 32 warn/restrict/ban/unban operations, preserving their graduated authorization and punishment history. The local door lockdown remains separate.
