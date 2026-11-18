# Phase 15 — Unified Incident Correlation & Threat Intelligence

**Status:** Source implementation committed. The correlation service now has an explicit server-reviewed signal registry, bounded contribution accounting, session context, and server-local raid/cohort early-warning. Studio/published-server verification, baseline calibration, and full producer signal-fidelity review remain open.

## Architecture

- SecurityMonitor remains the existing short-window per-signal counter and threshold notifier.
- SecurityReplayService remains the bounded per-server event timeline used for staff review.
- IncidentResponse remains the existing permission-checked MemoryStore-backed case lifecycle for explicit staff-created/resolved cases.
- SecurityThreatIntelligence is the single bounded, server-local correlation authority for player reviews and raid/cohort reviews. It does not create MemoryStore/DataStore records and does not automatically open or resolve an IncidentResponse case.

## Player correlation

- Per-subject rolling window: 10 minutes.
- Maximum tracked subjects: 256 per server.
- Maximum distinct registered signal codes per subject window: 12.
- Maximum retained player review items: 256 per server.
- Player review expiry: 30 minutes after the latest correlated signal.
- Repeated identical registered signal codes contribute at most three times per subject window.
- Per-category contribution cap: 8 points; per-source contribution cap: 8 points; total score cap: 100.
- Maximum independent source identifiers per subject window: 8; aggregate cohort evidence is capped at 16 sources and 32 signal codes.
- Confidence uses evidence diversity separately from score. Medium requires at least two categories, two distinct registered codes, and score at least four. High requires at least three categories, three codes, two sources, and score at least eight.
- Confidence is a triage label, not an exploitation probability. Score is an ordering aid, not a punishment threshold.
- Session start and bounded session event count are retained for up to 256 live subjects. Existing players at service startup receive a session baseline but are not counted as new joins. PlayerRemoving clears session state.
- Account age, username, device identity, IP address, and client fingerprint are not used.

## Explicit signal registry

- Substring classification has been removed. Only exact registered machine codes contribute categories or score.
- Audited signal families include movement/world-physics validation, audio asset validation, avatar/accessory validation, isolated honeypot remotes, staff/admin authorization failures, SecurityMonitor threshold crossings, SafeCall failures, and degraded watchdog pulses.
- Client integrity heartbeat and observation-only telemetry are not risk signals.
- Unknown codes are counted for diagnostics but contribute zero score, no category diversity, and no confidence evidence. This prevents arbitrary signal strings from inheriting a high category/weight through naming.
- Severity is normalized to the fixed Info, Warning, or Critical allowlist. Only Critical adds the bounded one-point bonus.
- Optional server-generated event IDs are de-duplicated in a 30-second ring capped at 256 IDs. Existing producers do not yet consistently provide event IDs, so cross-adapter duplicate suppression is only guaranteed when an ID is supplied.

## Raid/cohort early warning

- A rolling 60-second server-local join window retains at most 128 distinct joiners.
- The service observes PlayerAdded and PlayerRemoving. Players already in the server when the service starts are initialized as sessions but are not counted as new joins.
- A cohort review requires all of: at least 8 distinct joins in the window, at least 3 distinct joining players producing registered security signals, at least 2 signal categories, and at least 2 sources.
- Initial High cohort confidence requires at least 15 distinct joins, 5 distinct signaled players, 3 categories, 3 sources, and 4 distinct signal codes. Otherwise a qualifying cohort review is Medium.
- A join burst alone never creates a raid review. New-account age is not used.
- Maximum retained cohort reviews: 32; expiry: 30 minutes after the latest qualifying evidence.
- Cohort review records contain aggregate counts only, not a list of joining players. Individual player reviews remain separately queryable by authorized staff.
- Thresholds are provisional and must be calibrated against normal published-server traffic, event starts, reconnect waves, and legitimate popularity spikes before being treated as production raid verdicts.

## Staff review

- ServerStorage-only endpoint: TikiTideThreatIntelligence.
- Read-only status endpoint: GetTikiTideThreatIntelligenceStatus.
- Authorized Kohl's Admin command: ;cmthreat [UserId] [Limit], maximum limit 30.
- With no UserId filter, the command shows both individual correlated reviews and retained raid/cohort reviews. With a UserId filter, it shows that player's reviews only.
- Controller checks GlobalModeration; the service independently verifies a live Player and re-checks GlobalModeration before returning either query.
- Status diagnostics include raid review count, rolling join count, distinct signaled players, and unknown signal-code count.
- Phase 21 case creation remains explicit through ;cmthreatcase and its separate IncidentResponse permission check.

## Safety and resource boundaries

- No client RemoteEvent or RemoteFunction is added.
- No automatic kick, ban, shadow restriction, gameplay nerf, movement correction, or other enforcement is performed.
- No persistent or cross-server writes are performed by this service. No MessagingService raid broadcast is implemented in this update.
- No polling worker is added; expiry is pruned on record/query/join calls.
- Bounded collections: 256 player buckets, 256 player reviews, 256 event IDs, 256 session records, 128 joiners/cohort subjects, 32 raid reviews, 12 distinct signal codes per subject, and 8 source identifiers per subject.
- Counters are numeric and capped. Stop disconnects Player lifecycle listeners and clears retained in-memory state.
- Existing IncidentResponse remains a separate, explicit staff case-management workflow.
- Installer stages the module from pinned immutable source commit 40816ddb91b29fbde5bab30ccbe3a7972df63262 and retains the previous SecurityCore release for rollback.

## Runtime acceptance still required

1. Verify installer staging, pinned module fetch, promotion, rollback, and shutdown cleanup in Studio.
2. Verify all known producer codes are present and unexpected codes remain zero-weight; review the unknown-code counter after a published test.
3. Confirm repeated one-code and same-category signals never create a player review.
4. Confirm Medium/High thresholds, category/source caps, severity handling, event-ID dedupe, expiry, and capacity eviction.
5. Verify join bursts alone do not alert; corroborated multi-player bursts do; ordinary high-traffic/reconnect waves do not generate unacceptable false positives.
6. Verify ;cmthreat player and cohort output is bounded and unauthorized staff queries are denied.
7. Verify PlayerAdded/PlayerRemoving and service shutdown cleanup.
8. Profile signal overhead and test burst traffic on low-population and full servers.
9. Re-run playback controls, crossfade, local queues, playback-only global sync, purchases, moderation, Utility Bar, Settings, and spectator regressions.

**Release note:** This is a source-level implementation and installer update only. No Roblox Studio or published-server runtime test is claimed. Reviews are advisory evidence for authorized staff, not proof and not an enforcement decision.
