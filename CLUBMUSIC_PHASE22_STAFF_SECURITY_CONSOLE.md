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
