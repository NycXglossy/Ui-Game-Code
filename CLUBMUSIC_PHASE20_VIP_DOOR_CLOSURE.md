# Phase 20 – VIP Access, Door Lockdown, and Club Closure

## Scope
Extends the existing Phase 22 Staff Console and server-side VIP zone controller. No chat commands, duplicate door controller, or cross-server closure state are added.

## Door lockdown
- Reuses `StaffActions.server.lua` and `Workspace.ClubDoors`.
- Saves/restores each BasePart's `CanCollide`, `Color`, and `Transparency`.
- Captures BaseParts added while lockdown is active.
- Retains Security Core `SecurityPolicy` authorization and Security Replay auditing.

## VIP zone
- Reuses `SecurityServer.server.lua` and the main controller's `IsVIP` attribute from `EntitlementAuthority`.
- Adds no independent group-rank check, Game Pass lookup, or parallel entitlement resolver.
- Waits briefly for the authoritative entitlement attribute; unresolved entitlement does not grant access.
- Staff bypass continues to use Security Core.
- During closure, VIP entitlement alone does not exempt a guest.

## Club closure console
- Adds Close, Reopen, and Status under the graphical **Club Closure** category.
- Close/Reopen require a server-issued 10-second confirmation and re-check `SecurityPolicy`.
- `ServerStorage.TikiTideClubClosed` is in-memory current-server state only.
- Before closing, the server verifies all connected players' staff status. If any check is unavailable, closure aborts before removal.
- Verified staff remain; guests receive a closure notice and are removed.
- New arrivals during closure are checked through Security Core and removed if not verified staff.
- Security Replay audits the request and individual removals; a missing required audit prevents the transition.
- Reopening clears only this server's closed state.

## Evacuation boundary
The closure batch uses `Player:Kick()` only for temporary mass evacuation, not as an individual moderation command or a Phase 32 ban/restriction. This avoids creating a duplicate moderation-console action.

## Studio acceptance tests (not run)
1. Verify exact restoration of door collision, color, and transparency.
2. Add a BasePart under `Workspace.ClubDoors` during lockdown and verify capture/restoration.
3. Verify VIP group/Game Pass/awarded tiers still resolve through `EntitlementAuthority`.
4. Verify non-VIP players return to `ClubEntrance`; verified staff bypass the VIP zone.
5. Verify Close requires Prepare then Confirm and expired confirmations are rejected.
6. Verify closure aborts if staff authorization cannot be verified.
7. Verify staff remain, guests are removed, and new non-staff arrivals are removed while closed.
8. Verify Reopen restores guest access.
9. Verify audit failure prevents close/reopen.
10. Confirm no MessagingService, MemoryStore, or DataStore is used for closure state.

No Studio, live-server, or deployment tests are claimed.
