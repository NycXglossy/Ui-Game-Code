# Phase 24.1 — Incident Intake Hardening

**Status:** Source integration prepared on `phase24-incident-response-hardening`. Studio and published multiplayer acceptance tests remain required. This is not a production sign-off.

## Architecture preserved

- `ClubMusicSecurityCore/IncidentResponse.lua` remains the sole incident snapshot service.
- Existing `Open`, `Resolve`, `GetRecent`, `GetStatus`, and `Stop` methods remain available.
- Existing MemoryStore map name, per-user key strategy, TTL, coalescing, one-write-per-second server throttle, StorageGuard, ResourceGuard, bounded indexes, and 5 KB record ceiling remain in place.
- Staff-created incidents still pass through Security Core `IncidentResponse` authorization.
- Player report intake is a separate narrow server-only service method; it does not grant players staff permission.
- The Global API intake endpoints are BindableFunctions in ServerStorage, not client remotes.

## Added intake paths

### Player reports

`SecurityServer.server.lua` creates/uses:

- `ReplicatedStorage.SecuritySystem.ReportIncident` (client-to-server RemoteEvent)
- `ReplicatedStorage.SecuritySystem.StaffAlert` (server-to-staff RemoteEvent)

The server validates the reporter, live target, target identity, UTF-8, control characters, payload size, and a 15-second reporter cooldown. Text is filtered with TextService before it is passed to the trusted Global API. The incident is stored as `AbuseReport` under the target UserId. Staff receive only the incident identifier and participant UserIds; raw client text is not broadcast.

### VIP restricted zone

- `VIPRestrictedZone` must be an anchored BasePart.
- The server verifies that the reported character/root is still in the zone bounds.
- Membership is read from the main controller's server-published `IsVIP` attribute, which is derived from EntitlementAuthority; unknown entitlement state is not treated as trespass.
- Staff status is resolved through the shared SecurityCore Authorization singleton.
- An unauthorized player is moved to `ClubEntrance` when it is a valid BasePart.
- A fixed `SecurityAlert` system signal is submitted through the same IncidentResponse store with a 10-second per-subject cooldown.
- No kick, ban, restriction, or automatic punishment is performed.

## Release pin alignment

The Global Service loader and Security Core installer must both use the exact IncidentResponse source release commit `e894e50a9f3d837854049e1bfa5c758502760984`. The installer continues to pin Phase 32 independently. Do not install a different Core folder revision while leaving the Global Service loader pin unchanged.

## Studio installation

1. Update the installed `ClubMusicSecurityCore` folder with the revised installer.
2. Replace the existing `ClubMusic_Global_Service` Script source with `ClubMusic_Global_Service_server_1.lua` from this branch.
3. Create a Script named `SecurityServer` under `ServerScriptService` and paste `SecurityServer.server.lua`.
4. Confirm the existing controller continues to publish `IsVIP` from EntitlementAuthority.
5. Ensure `Workspace.VIPRestrictedZone` and `Workspace.ClubEntrance` exist; the zone must be anchored.
6. Verify there is only one Global Service owner and no standalone `IncidentManager` is installed.

## Acceptance tests

- [ ] Unauthorized player can submit a valid report without receiving IncidentResponse permission.
- [ ] Invalid types, NaN/infinite/negative/fractional UserIds, self-report, offline target, malformed UTF-8, control characters, oversized reason, and empty reason are rejected.
- [ ] Reporter cooldown is enforced before TextService yields; repeat remote calls do not create duplicate filter work.
- [ ] TextService failure rejects the report without storing raw text.
- [ ] IncidentResponse coalesces repeated reports for the same subject and preserves eventCount.
- [ ] Existing staff `Open`, `Resolve`, and `GetRecent` command workflows still work.
- [ ] Global Service refuses a mismatched Core manifest and loads the exact pinned module revision.
- [ ] Staff alerts reach only currently authorized staff.
- [ ] VIP, VVIP, Tiki Tide, group-member, and owner-awarded VIP access bypass the zone.
- [ ] Staff bypass is resolved through SecurityCore Authorization; an unavailable auth refresh does not falsely eject staff.
- [ ] Missing/invalid entrance does not crash the detector; incident recording remains independent.
- [ ] Repeated Touched events do not cause repeated teleports/incidents inside the cooldown.
- [ ] MemoryStore unavailable, StorageGuard open, and ResourceGuard exhausted paths are handled without automatic punishment.
- [ ] No kick, ban, restriction, or gameplay nerf occurs.

**Not included:** Discord webhook delivery, automated punishment, appeal UI, offline-target public reports, or a second incident history store.
