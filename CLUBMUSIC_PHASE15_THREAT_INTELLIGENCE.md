# Phase 15 — Threat Intelligence and Raid/Cohort Review

**Status:** Selectively integrated on `integration/tiki-tide-system-consolidation`. Source integration only; Studio and published-server acceptance tests remain outstanding.

## Release reconciliation

The hardened module is pinned independently:
- Security Core release: `7ebc71e3a6fa9ef04e80d5f332e5f72617c8d288` (unchanged)
- Phase 32 release: `6ae4883c2c260df61bf760b8637dd339bda33d7b` (unchanged)
- Threat Intelligence module only: `2b0c8ad144bf3257798c18f149c922d44ad350f1`

The installer fetches `SecurityThreatIntelligence.lua` from the dedicated Phase 15 pin and every other Security Core module from the existing release pin. `ReceiptAuthority`, `ReceiptHash`, and `ReceiptTransactionService` remain in the installer list. Do not replace the complete Security Core release pin with the older Phase 15 installer pin.

## Architecture and safety

- The service is bounded and server-local. It does not persist evidence, write cross-server state, broadcast raid notices, or alter gameplay.
- It has no kick, ban, restriction, or automatic-enforcement path.
- Player and cohort reviews are advisory evidence for authorized staff; confidence is a triage label, not a verdict.
- Existing IncidentResponse remains a separate, explicit staff case workflow.
- No client RemoteEvent or RemoteFunction is added.

## Exact signal registry

Only explicitly registered machine codes contribute score, category diversity, or confidence. Unknown codes are counted for diagnostics but contribute zero score and no confidence evidence. This avoids substring-based classification of arbitrary telemetry.

The reviewed registry covers movement/world-physics validation, audio asset validation, avatar/accessory validation, isolated honeypot remotes, staff/admin authorization failures, SecurityMonitor threshold crossings, SafeCall failures, and degraded watchdog pulses. Observation-only client telemetry is not a risk signal. Additional current producer codes remain zero-weight until individually audited and registered.

- Severity is normalized to `Info`, `Warning`, or `Critical`; only `Critical` receives the bounded one-point bonus.
- Repeated identical registered codes contribute at most three times per subject window.
- Per-category and per-source contribution caps are eight points; total score is capped.
- Maximum eight source identifiers and twelve distinct registered codes are retained per subject window.
- Optional event IDs are deduplicated for 30 seconds in a 256-ID cap. Existing producers do not yet consistently provide event IDs.

## Player correlation

- Rolling player evidence window: 10 minutes.
- Maximum tracked subjects: 256 per server; maximum player review records: 256 per server.
- Player review expiry: 30 minutes after the latest correlated signal.
- Medium confidence requires at least two categories, two registered signal codes, and score at least four.
- High confidence requires at least three categories, three codes, at least two sources, and score at least eight.
- Session start and bounded session event count are included. Existing players at service startup receive a session baseline but are not counted as new joins.
- Account age, username, device identity, IP address, and client fingerprint are not used.

## Raid/cohort early warning

- Rolling join window: 60 seconds, at most 128 distinct joiners.
- A cohort review requires at least 8 distinct joins, at least 3 distinct joining players producing registered signals, at least 2 signal categories, and at least 2 independent sources.
- Initial High confidence requires at least 15 joins, 5 signaled players, 3 categories, 3 sources, and 4 signal codes. Otherwise a qualifying review is Medium.
- Join volume alone never creates a raid review.
- At most 32 cohort reviews are retained; each expires after 30 minutes.
- Cohort records contain aggregate counts only, not a list of joining players.
- Thresholds are provisional and must be calibrated against normal published-server traffic, event starts, reconnect waves, and legitimate popularity spikes.

## Staff review and diagnostics

- ServerStorage-only endpoint: `TikiTideThreatIntelligence`.
- `Query` returns player/server reviews; `QueryRaids` returns cohort reviews. Both independently verify a live Player and `GlobalModeration` authorization.
- `;cmthreat [UserId] [Limit]` displays player reviews and, without a UserId filter, raid/cohort reviews.
- The controller applies the existing GlobalModeration check; the service independently rechecks authorization.
- Diagnostics include raid review count, rolling join count, distinct signaled players, and unknown signal-code count.
- `;cmthreatcase` remains limited to player review IDs and the separate IncidentResponse permission. Cohort reviews are not automatically converted into cases.

## Runtime acceptance still required

1. Run `ClubMusicSecurityCore/SecurityThreatIntelligence.spec.lua` in a Studio server test harness.
2. Verify installer fetches the isolated threat-module pin while retaining current Security Core and Phase 32 pins, and stages, promotes, and rolls back correctly.
3. Verify intended producers use exact registered codes; inspect `unknownSignals` after a published test.
4. Confirm repeated one-code and same-category signals do not create reviews; verify caps, severity normalization, event-ID dedupe, expiry, and capacity eviction.
5. Verify join bursts alone do not create reviews; corroborated multi-player bursts do; normal traffic and reconnect waves do not cause unacceptable false positives.
6. Verify `;cmthreat` output is bounded and unauthorized staff queries are denied by both controller and service.
7. Verify PlayerAdded/PlayerRemoving cleanup, Stop disconnection, and load throttling.
8. Profile burst traffic and run playback-only sync, local queue, purchase, moderation, Utility Bar, Settings, and spectator regressions.

**No Roblox Studio or published-server runtime tests have been run by this integration.** Keep the feature advisory-only and calibrate thresholds before operational reliance.
