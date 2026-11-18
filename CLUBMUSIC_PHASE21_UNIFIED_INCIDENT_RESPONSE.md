# Phase 21 — Unified Incident Response

**Status:** Source integration and a confirmed incident-coalescing defect fix committed. Automated punishment remains disabled.

## Changes

1. Fixed the existing incident update callback in ClubMusicSecurityCore/IncidentResponse.lua. When a user already had an open incident, the callback attempted to read nextItem.eventCount before nextItem existed. It now increments from old.eventCount, preserving the existing stored count and pending coalesced flags.
2. Added explicit staff escalation from a retained threat-review item into a MemoryStore-backed ManualReview incident:
   - Kohl's command: ;cmthreatcase TTI-12
   - Controller validates the fixed TTI-digits identifier and requires IncidentResponse.
   - The controller queries the current server's ThreatIntelligence endpoint; the service independently checks the caller's GlobalModeration permission.
   - The server constructs a short summary from the review ID, confidence, score and fixed signal codes. No free-form client evidence is forwarded.
   - The incident is opened through the existing Global IncidentResponse service, which independently checks IncidentResponse.
   - Server-level reviews without a positive player UserId are not converted into player incidents.

## Existing workflow

- ;cmthreat [UserId] [Limit] reviews bounded, server-local correlation items.
- ;cmthreatcase <TTI-review-ID> explicitly escalates one retained review item.
- ;cmincident <kind> <UserId|server> <summary> remains available for authorized manual case creation.
- ;cmincidents lists recent incidents.
- ;cmresolve <incident-ID> resolves a case.
- IncidentResponse remains the TTL-bounded MemoryStore case index; ThreatIntelligence remains server-local advisory correlation. The two are not conflated.

## Safeguards

- No review item automatically opens a persistent case.
- No single signal automatically causes a kick, ban, shadow restriction, movement correction, or gameplay nerf.
- Threat confidence labels are evidence-diversity triage, not probabilities.
- Case creation and resolution require SecurityCore IncidentResponse.
- Threat review queries independently require SecurityCore GlobalModeration.
- StorageGuard and ResourceGuard remain in the write/read path; bounded item size, TTL, local indexes and read cache remain enforced.
- The incident summary is machine-generated and capped at 120 characters.

## Acceptance tests

- [ ] Open a first incident and verify stored eventCount=1.
- [ ] Open/coalesce repeated flags for the same subject and verify eventCount increases without callback errors or duplicate open records.
- [ ] Verify one-second write throttling, pending flag coalescing, TTL, 5 KB encoded-size bound and 256-entry local indexes.
- [ ] Convert a valid current-server TTI review; verify subject, fixed summary and incident state.
- [ ] Reject expired/missing TTI IDs, malformed IDs, server-level review IDs and unauthorized callers.
- [ ] Verify case resolution is idempotently rejected after the first resolution.
- [ ] Test MemoryStore unavailable, StorageGuard open and ResourceGuard exhausted paths.
- [ ] Verify no automatic enforcement occurs from either service.

**Not included:** automated ban waves, automated shadow moderation, appeal UI, or automatic gameplay restrictions. Those require a separately approved policy and reversible enforcement design.


## Client staff alerts and player-report UI companion

Phase 21 includes the optional client presentation script at `StarterPlayer/StarterPlayerScripts/SecurityClient.client.lua`.

- Listens to `ReplicatedStorage.SecuritySystem.StaffAlert` and displays a Roblox notification with incident ID, category, target, filtered reason, and reporter/source.
- The server fires this RemoteEvent only to players currently authorized by the shared SecurityCore Authorization service.
- Supports the compatibility fields `Category`, `TargetName`, `Reason`, `ReporterName`, and `Id`, while also accepting the structured incident fields.
- Provides a `submitPlayerReport(targetPlayer, reasonText)` helper to connect to a report button. It sends the target UserId and reason through `ReportIncident`; all meaningful validation and TextService filtering remain server-side.
- The client script does not determine staff status and cannot authorize or create incidents directly.

The matching server payload contains only filtered report text. Automated VIP-zone alerts use the same notification shape with `Automated Security` as the reporter/source.

### Client acceptance tests

- [ ] Ordinary players can submit a report through the UI helper, but never receive staff dispatch alerts.
- [ ] Authorized staff receive player-report and VIP-zone alerts.
- [ ] Non-staff clients cannot receive staff alert payloads by invoking client code.
- [ ] Notifications handle missing/legacy fields without client errors.
- [ ] SetCore startup delay does not permanently drop the alert.
- [ ] Report text displayed to staff is the server-filtered text, not the raw client string.
