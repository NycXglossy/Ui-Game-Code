# Phase 15 Extension — Correlation Hardening & Raid Detection

**Status:** Source implementation committed on the isolated phase15-correlation-hardening branch. Studio and published-server verification are still required. This is a local early-warning system, not an autonomous enforcement system.

## Implemented

### 15.1 — Explicit signal registry
- Replaced substring-based classification with exact signal-code registration.
- Registered audited movement/world-physics, audio validation, avatar/accessory validation, honeypot, admin authorization, SecurityMonitor, SafeCall, and watchdog codes.
- Observation-only client integrity heartbeat and client telemetry do not contribute to threat scoring.
- Unknown codes increment a diagnostic counter but receive no category, score, or confidence contribution.

### 15.2 — Event identity and source independence
- Added optional server-generated event ID de-duplication with a 30-second TTL and 256-ID cap.
- Player review records retain sorted exact source identifiers.
- High player confidence requires at least two distinct sources in addition to three categories, three codes, and score at least eight.
- Existing producer adapters do not yet consistently supply event IDs. Duplicate suppression across separate adapters is therefore guaranteed only where the caller supplies the same ID.

### 15.3 — Balanced contribution limits
- Repeated identical codes contribute at most three times per player window.
- Each category and source contributes at most eight points per subject window.
- Maximum eight distinct sources and twelve distinct codes per subject window; cohort aggregation is capped at 16 sources and 32 codes.
- Total subject score remains capped at 100.
- Only the allowlisted Critical severity receives a one-point bonus. Invalid/missing severity is treated as Info.
- Unknown codes never score.

### 15.4 — Explainable review records
- Player reviews include category, signal-code, and source counts; bounded sorted code/source lists; event count; session age/event count; confidence; score; and fixed reason labels.
- Raid reviews include join count, distinct signaled-player count, category/source/code counts, confidence, and fixed reason labels.
- No raw detail strings, report text, chat, asset IDs, client payloads, tracebacks, IP addresses, or device fingerprints are stored or returned.

### 15.5 — Lifecycle and capacity accounting
- Added bounded counters for expired subjects/reviews, capacity evictions, duplicate event IDs, capped contributions, unknown codes, rejected inputs, and denied queries.
- Pruning occurs during record, query, and join operations; no polling worker was added.
- Stop disconnects PlayerAdded/PlayerRemoving listeners and clears all retained state.

### 15.6 — Deterministic test coverage
- Added ClubMusicSecurityCore/SecurityThreatIntelligence.spec.lua with an injectable monotonic clock.
- The Studio server test covers repeated-code suppression, same-category suppression, unknown-code handling, invalid severity, category/source caps, duplicate event IDs, Medium/High evidence diversity, join-burst-only suppression, multi-player cohort corroboration, joiner capacity, cohort expiry, subject expiry/capacity, authorization rejection, and Stop cleanup.
- The test file is not included in the production installer module list.

### 15.7–15.8 — Session-aware evidence and scoring
- Added session start and capped session event counts.
- Existing players at service startup are initialized without being miscounted as new joins.
- PlayerAdded creates a session and join observation; PlayerRemoving clears the session.
- Account age and identity/device fingerprinting are not used.

### 15.9 — Server-wide raid/cohort indicators
- Added a 60-second rolling join cohort, capped at 128 distinct joiners.
- Initial Medium cohort threshold: at least 8 distinct joins, 3 distinct joining players with registered signals, 2 categories, and 2 sources.
- Initial High cohort threshold: at least 15 joins, 5 distinct signaled players, 3 categories, 3 sources, and 4 signal codes.
- Join bursts alone do not create a raid review.
- Cohort review retention is capped at 32 items with a 30-minute TTL.
- Thresholds are explicitly provisional; collect ordinary published-server baselines before treating them as production thresholds.

### 15.10 — Staff review integration
- Added QueryRaids to the existing ServerStorage-only threat-intelligence endpoint.
- Extended ;cmthreat with no target filter to show both player reviews and raid/cohort reviews.
- Added cohort metrics to the existing staff diagnostics status output.
- Both query paths retain the existing GlobalModeration checks in the controller and service.
- Phase 21 IncidentResponse case creation remains explicit and separately permission-checked.
- No cross-server MessagingService advisory transport was added in this update; local detection is independent of cross-server service availability.

## Source and installer changes

- Security module: ClubMusicSecurityCore/SecurityThreatIntelligence.lua
- Installer: ClubMusic_Security_Core_Installer.lua now pins the hardened module snapshot at commit 2b0c8ad144bf3257798c18f149c922d44ad350f1.
- Staff command/diagnostics: UI_Server_Controller_server (1).lua
- Deterministic Studio test: ClubMusicSecurityCore/SecurityThreatIntelligence.spec.lua
- Detailed architecture and acceptance gates: CLUBMUSIC_PHASE15_THREAT_INTELLIGENCE.md

## Safety boundary

- No new client remotes.
- No automatic kick, ban, teleport, shadow restriction, gameplay change, or punishment.
- No persistent writes, cross-server writes, or MessagingService raid broadcasts.
- No account-age multiplier, device fingerprinting, IP collection, or raw user content retention.
- No production raid verdict until thresholds are calibrated against normal live traffic and runtime acceptance passes.

## Remaining verification

1. Run the deterministic test in Studio server context.
2. Verify installer fetch, staging, promotion, rollback, and stop cleanup.
3. Inspect unknownSignals after a published test to identify any omitted exact producer codes.
4. Validate join burst thresholds against normal traffic, event launches, and reconnect waves.
5. Verify ;cmthreat output and GlobalModeration authorization with authorized and unauthorized accounts.
6. Run server load tests with high joins and security-signal bursts.
7. Run the existing ClubMusic playback, sync, queue, purchase, moderation, Utility Bar, and spectator regression suite.

**Important:** Source changes and GitHub commits are complete for this branch. Roblox Studio and published-server behavior have not been tested by this work session. The installer pin is updated in the repository only; the live place is unchanged.
