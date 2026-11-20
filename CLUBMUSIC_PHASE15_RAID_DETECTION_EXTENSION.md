# Phase 15 Extension — Correlation Hardening & Raid Detection

**Status:** Selectively integrated on `integration/tiki-tide-system-consolidation`. This is a local early-warning system, not autonomous enforcement.

## Implemented

- Exact registered machine codes replace substring-based classification. Unknown codes remain visible in counters but receive no score, category, or confidence contribution.
- Audited signal families include movement/world-physics (including delayed extreme assembly velocity/rotation), audio, avatar/accessory, honeypot, admin authorization, SecurityMonitor, SafeCall, and watchdog signals. The two physics codes are registered as Movement evidence at weight 2; observation-only inventory/animation telemetry and avatar API read failures remain zero-weight.
- Optional event IDs are deduplicated for 30 seconds in a bounded 256-ID table. Existing producers do not yet consistently provide event IDs.
- Repeated identical codes contribute at most three times per player window. Category and source contributions are capped at eight points; at most eight sources and twelve codes are retained per subject.
- Only allowlisted Critical severity receives a one-point bonus. Invalid or missing severity is normalized to Info.
- Player review records include bounded categories, codes, sources, session context, confidence, score, and fixed reason labels. Cohort records contain aggregate counts only.
- A rolling 60-second join cohort is capped at 128 distinct joiners. At most 32 cohort reviews are retained for 30 minutes.
- A cohort review requires at least 8 joins, 3 distinct signaled joining players, 2 categories, and 2 sources. High confidence requires at least 15 joins, 5 signaled players, 3 categories, 3 sources, and 4 codes.
- Join bursts alone never create a review. Thresholds remain provisional pending published-server baselines.
- Pruning occurs during record/query/join operations; no polling worker or cross-server transport is added. Stop disconnects Player lifecycle listeners and clears retained state.
- `ClubMusicSecurityCore/SecurityThreatIntelligence.spec.lua` covers repeated-code suppression, same-category suppression, unknown-code handling, severity normalization, caps, event-ID dedupe, confidence diversity, join-only suppression, cohort corroboration, expiry, capacity, authorization, and Stop cleanup.

## Release reconciliation

Only `SecurityThreatIntelligence.lua` is pinned to `2b0c8ad144bf3257798c18f149c922d44ad350f1`. The main Security Core release remains `7ebc71e3a6fa9ef04e80d5f332e5f72617c8d288`; Phase 32 remains `6ae4883c2c260df61bf760b8637dd339bda33d7b`. Receipt modules remain in the current installer manifest.

## Safety boundary

- No client remotes, persistent writes, cross-server writes, or MessagingService raid broadcasts.
- No automatic kick, ban, teleport, shadow restriction, gameplay change, or punishment.
- Cohort reviews remain server-local advisory evidence. No IncidentResponse case is opened automatically.
- The test spec is not included in the production installer module list.

## Remaining verification

Run the deterministic Studio test; verify installer staging/promotion/rollback; audit producer codes and unknown-code counts; calibrate thresholds against normal traffic; verify staff authorization and bounded output; and run burst/load tests. Re-run playback-only sync, local queues, purchases, moderation, Utility Bar, Settings, and spectator regressions.

**Studio and published-server runtime verification remain outstanding.**
