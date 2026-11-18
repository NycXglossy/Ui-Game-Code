# Phase 22 — Staff Security Console

**Status:** Staff-facing command integration committed through the existing Kohl's Admin bridge. No new client remote or mobile UI was added.

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
- No new UI layout or mobile changes were made.
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

## Graphical staff console actions — additive extension

**Status:** The following source companion is prepared on the Phase 22 feature branch. It extends the existing command/spectator work above; it does not replace it.

### Files

- `StaffActions.server.lua` — install as a Script under `ServerScriptService`.
- `StarterPlayer/StarterPlayerScripts/SecurityConsole.client.lua` — install as a LocalScript under `StarterPlayer/StarterPlayerScripts`.

The existing Phase 21 `SecurityClient.client.lua` remains separate and unchanged.

### Actions and permissions

- Current-server lockdown requires Security Core `SecurityPolicy`.
- Exact online username removal requires Security Core `GlobalModeration`.
- The first graphical-console slice does not add mute, freeze, teleport, warn, ban, or global lockdown.
- Console visibility is enabled for Security Core level 2+ and rechecked every 30 seconds.
- The server reauthorizes every state-changing request. GUI visibility is not a security boundary.
- Target staff status is checked through Security Core; staff targets and unverifiable targets are protected from removal.

### Local lockdown behavior

- Uses only `Workspace.ClubDoors` and descendant BaseParts.
- Saves each part's original `CanCollide` and `BrickColor`.
- Applies collision and red color while lockdown is active.
- Captures BaseParts added while lockdown is active.
- Restores saved properties when disabled or when the server script is destroyed.
- Lockdown state is held only in the current server's memory. No cross-server messaging or persistent storage is used.

### Player removal behavior

- Exact username matching only; partial names and DisplayNames are not accepted.
- Rejects self-removal, offline targets, malformed names, oversized reasons, and protected staff.
- Filters the reason through TextService for the target before `Player:Kick()`.
- Blank reason uses `Removed by Club Security.`.

### Remote and audit contract

The server creates or validates root-level ReplicatedStorage RemoteEvents:

- `SecurityAction` — client-to-server requests.
- `SecurityActionResult` — server-to-requesting-client results.

Supported actions: `GetStatus`, `ToggleLockdown`, and `KickPlayer`.

State-changing actions require a successful write to the existing server-local `TikiTideSecurityReplay` BindableFunction before execution. Request and completion/failure records use the existing replay timeline; no parallel audit or incident store is created. If the replay endpoint is unavailable, the action is denied.

The UI requires a second click to confirm lockdown. Set `StarterGui.StaffConsoleGui.Enabled = false` by default in Studio. The ScreenGui must contain `MainFrame.LockdownBtn`, `KickBtn`, `TargetPlayerBox`, and `ReasonBox`; `StatusLabel` is optional.

### Installation and acceptance

1. Confirm the Phase 24 Security Core and controller integration are installed, including `TikiTideSecurityReplay`.
2. Add `StaffActions.server.lua` under `ServerScriptService`.
3. Add `SecurityConsole.client.lua` under `StarterPlayer/StarterPlayerScripts`.
4. Confirm `Workspace.ClubDoors` contains only the door parts intended for this control.
5. Test in a dedicated published test place with test accounts.

- [ ] Unauthorized RemoteEvent calls cannot toggle lockdown or remove players.
- [ ] Moderator can remove eligible non-staff players; only SecurityPolicy staff can toggle lockdown.
- [ ] Another server remains unaffected by local lockdown.
- [ ] Original door collision/color values are restored, including for parts added during lockdown.
- [ ] Partial usernames, DisplayNames, self-targets, offline targets, and staff targets are rejected.
- [ ] TextService failure rejects removal.
- [ ] Missing audit endpoint causes state-changing actions to fail closed.
- [ ] Console hides for non-staff and is hidden again after staff authorization is lost on a recheck.
- [ ] Existing Phase 21 report/staff-alert remotes and the Phase 22 spectator commands continue to work.

**Release boundary:** Source-only feature branch. No Studio runtime tests, published multiplayer tests, merge, or live deployment have been performed.
