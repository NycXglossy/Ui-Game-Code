# Phase 15 — Unified Incident Correlation & Threat Intelligence

**Status:** Source implementation committed. Studio/published-server verification and signal-fidelity review remain open. This phase adds a bounded, server-local correlation layer on top of the existing SecurityMonitor, SecurityReplayService, diagnostics, SafeCall, and IncidentResponse services; it does not replace any of them.

## Architecture

- `SecurityMonitor` remains the existing short-window per-signal counter and threshold notifier.
- `SecurityReplayService` remains the bounded per-server event timeline used for staff review.
- `IncidentResponse` remains the existing permission-checked MemoryStore-backed case lifecycle for explicit staff-created/resolved cases.
- New `SecurityThreatIntelligence` correlates multiple independent signals into temporary local review items. It does not create MemoryStore/DataStore records and does not automatically open or resolve an IncidentResponse case.

## Correlation model

- Per-subject rolling window: 10 minutes.
- Maximum tracked subjects: 256 per server.
- Maximum distinct signal codes per subject window: 12.
- Maximum retained review items: 256 per server.
- Review-item expiry: 30 minutes after the latest correlated signal.
- Repeated identical signal codes contribute weight at most three times per subject window.
- Signal codes and source identifiers are short, validated machine tokens. Raw detail strings, chat, asset IDs, client payloads, and tracebacks are not retained.
- Signal categories include Movement, Audio, Social, Avatar, Purchase, Messaging, Authorization, Remote, Watchdog, SafeCall, Diagnostics, Monitor, and Other.
- A review item is created only after at least two distinct signal categories and two distinct signal codes produce a score of at least four. A High confidence review requires at least three categories, three signal codes, and score at least eight.
- One signal, even if repeated, cannot independently create a review item because category diversity is required.
- Confidence is a triage label for evidence diversity, not a probability that a player is exploiting.

## Integrated signal sources

- Existing `ReportSignal` events, including confirmed audio-validation and admin-bridge signals.
- Existing `RecordGlobalSecuritySignal` events, including CharacterPhysicsGuard and avatar-validation adapters.
- SecurityMonitor threshold crossings.
- Explicit unhealthy local watchdog pulses.
- SafeCall protected-operation failures, through an optional failure callback.
- The same underlying security signal events continue to be recorded in the existing replay timeline where that adapter already records them; the correlation service stores only the fixed signal code/source/category summary.

## Staff review

- ServerStorage-only endpoint: `TikiTideThreatIntelligence`.
- Read-only status endpoint: `GetTikiTideThreatIntelligenceStatus`.
- The authorized Kohl's Admin command is `;cmthreat [UserId] [Limit]`, with a maximum limit of 30.
- The command checks `GlobalModeration` permission in the controller and the correlation service independently re-checks the live Player and permission before returning results.
- Results show subject UserId, confidence, score, event count, age, categories, and signal codes only.

## Safety and resource boundaries

- No client RemoteEvent or RemoteFunction is added.
- No automatic kick, ban, shadow restriction, gameplay nerf, movement correction, or other enforcement is performed.
- No persistent or cross-server writes are performed by the correlation service.
- No additional polling loop or background worker is created; expiry is pruned on record/query calls with a five-second minimum sweep interval, avoiding a full retained-state scan on every signal.
- Existing incident updates use a per-server ID index instead of linearly searching the retained incident list for each qualifying signal. The index is cleared on incident eviction, expiry, and service shutdown.
- All in-memory maps and lists have explicit capacity limits.
- Existing IncidentResponse remains a separate, explicit staff case-management workflow.
- The installer stages the new module and retains the previous SecurityCore release for rollback.

## Runtime acceptance still required

1. Verify installer staging, pinned module fetch, promotion, rollback, and shutdown cleanup in Studio.
2. Confirm a single signal and repeated same-category signals never create a review item.
3. Confirm two independent categories/signals cross the Medium threshold and three categories/signals cross the High threshold.
4. Verify score caps, signal-code caps, subject eviction, incident ring capacity, and expiry.
5. Verify ordinary clients cannot access either ServerStorage endpoint and unauthorized staff queries are denied.
6. Verify `;cmthreat` output is bounded, contains no raw detail/traceback/client payload, and respects target/limit parsing.
7. Confirm ReportSignal, CharacterPhysicsGuard, SafeCall, watchdog, and SecurityMonitor adapters produce only the intended fixed codes.
8. Verify a missing correlation module/endpoint does not block core ClubMusic startup or security validation.
9. Profile per-signal overhead and test under burst traffic.
10. Re-run playback controls, crossfade, independent per-server queues, purchases, moderation, Utility Bar, Settings, and spectator regressions.

**Release note:** This is a source-level implementation only. No Roblox runtime test is claimed. Correlation results are advisory staff-review items, not proof and not an enforcement decision.
