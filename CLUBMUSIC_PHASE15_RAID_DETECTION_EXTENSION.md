# Phase 15 Extension — Correlation Hardening & Raid Detection

**Status:** Design and implementation requirements. This document does not claim that the raid detector is implemented or runtime-verified. The existing Phase 15 service remains the only threat-correlation authority.

## Goals

Extend the existing bounded, server-local `SecurityThreatIntelligence` service in controlled steps. Improve signal quality and explainability, add session context, and add a separate server-wide cohort view for coordinated-raid indicators. Preserve the existing safety boundary: advisory detection and staff review only.

## 15.1 — Explicit signal registry

Replace substring-based category inference with a reviewed registry of exact signal codes. Each entry defines a category and bounded base weight. Severity is accepted only from a small allowlist. Unknown codes must be rejected or recorded in a low-weight `Other` bucket and must never inherit a high weight from a substring match.

Before switching the registry on, inventory every existing producer (ReportSignal, RecordGlobalSecuritySignal, SecurityMonitor, watchdog, SafeCall, CharacterPhysicsGuard, avatar validation, and honeypots). Add exact producer codes to the registry and retain a compatibility test for every call site. Do not silently rename producer signals.

## 15.2 — Event identity and source independence

Track originating subsystem separately from signal code. Add an optional server-generated event identifier for adapters that forward one underlying event through more than one path. Keep a bounded recent-ID ring with a short TTL so the same event cannot inflate counts when replay, monitor, and threat-intelligence adapters all observe it.

Source diversity is supporting evidence, not proof. A single source emitting many different codes must not be treated as independent corroboration. High confidence should require category, code, and source diversity after event de-duplication.

## 15.3 — Balanced contribution limits

Keep the existing per-code repeat ceiling and total score ceiling. Add per-category and per-source contribution ceilings so a noisy adapter cannot dominate the score. Severity bonuses must be applied only to registry-approved severity values. Unknown severity contributes no bonus.

A score is an ordering aid for staff triage, not a probability or a punishment threshold.

## 15.4 — Explainable review records

Review output should include only bounded, fixed-schema fields: confidence, score, distinct category/code/source counts, event count, first/last observed age, and fixed reason codes. Example reasons: `MULTI_CATEGORY`, `MULTI_SOURCE`, `REPEATED_SIGNAL_CAPPED`, `SESSION_ACTIVITY`, `JOIN_BURST`, `COHORT_CORROBORATION`.

Never retain or return raw chat, report text, asset IDs, arbitrary detail strings, client payloads, tracebacks, IP addresses, or device fingerprints.

## 15.5 — Lifecycle and capacity accounting

Expose bounded counters for expired subject buckets, expired review items, capacity evictions, rejected inputs, duplicate event IDs, and capped contributions. Counters must themselves be numeric and bounded. Do not add a polling worker; prune during record/query calls as the current service does.

## 15.6 — Deterministic tests

Use an injectable monotonic clock in tests. Cover exact registry behavior, unknown codes, invalid severity, source and category caps, duplicate forwarding, thresholds, expiry, capacity eviction, authorization, query limits, Stop cleanup, and burst workloads. Tests must prove that one signal repeated many times cannot create a multi-category incident.

## 15.7 — Session-aware evidence

Track a subject's observed session start and a bounded session event count separately from the rolling correlation window. Session context must reset on PlayerRemoving and must not be inferred from account age. Retain the existing bounded subject cap and TTL. If a player was already present when the service starts, initialize their session once without duplicating join events.

Session activity is context only; a short session or new account is not itself suspicious.

## 15.8 — Weighted risk scoring

Use only registry-defined weights, category/source caps, and event de-duplication. Keep evidence-diversity confidence separate from score. Do not multiply risk based on account age, device identity, username patterns, or other weak proxies. A high score from one noisy source must not become High confidence.

## 15.9 — Server-wide raid/cohort indicators

A per-player correlator cannot detect coordinated raids alone. Add a bounded server-wide cohort window with aggregate counters for:
- joins per short time bucket;
- distinct joining players;
- distinct players producing validated security signals;
- distinct signal categories and sources represented across the cohort;
- repeated abuse indicators observed during the same cohort window.

Do not define production thresholds until published-server baselines are measured across ordinary traffic, event launches, reconnect waves, and legitimate popularity spikes. Prefer configurable, conservative thresholds with a minimum distinct-player requirement. A join burst alone should be an informational signal, not a raid verdict.

Cohort review records should expose aggregate counts and a bounded list of relevant UserIds only to authorized staff. Do not expose cohort data to clients. Avoid storing raw IP/device identifiers or attempting to link accounts through unsupported fingerprinting.

## 15.10 — Optional cross-server advisory and staff escalation

Cross-server intelligence is a later optional layer. If introduced, MessagingService messages must be versioned, size-limited, timestamp-checked, sender/job-validated, deduplicated, and rate-limited. Messages are advisory hints only; receiving a message must never kick, ban, restrict, or alter a player. Local detection must continue when MessagingService is unavailable.

Staff escalation remains explicit. A staff member with the appropriate IncidentResponse permission may create a Phase 21 case from a reviewed item. GlobalModeration review permission and IncidentResponse case-management permission remain separate. No automatic case creation or enforcement.

## Raid-detection architecture

```
Player joins / validated server-side security signals
                    |
                    v
       Bounded session + cohort counters
                    |
                    v
       SecurityThreatIntelligence
          /                 \
         v                   v
 Per-player review      Server-wide cohort review
         \                   /
          v                 v
           Authorized staff review
                    |
          Explicit Phase 21 escalation
                    |
             Human decision only
```

## Rollout order

1. Inventory all current signal producers and exact codes.
2. Add explicit registry and tests before changing live classification.
3. Add event identity/de-duplication and source-aware evidence.
4. Add category/source contribution caps and explainable review fields.
5. Add lifecycle counters and deterministic tests.
6. Add session-aware evidence.
7. Add server-wide cohort/join-burst detection in observe-only mode.
8. Collect published-server baselines and tune thresholds.
9. Consider cross-server advisory messages only after local behavior is stable.
10. Integrate staff escalation without changing Phase 21 authorization or enforcement boundaries.

## Acceptance gates

- No new client remotes.
- No automatic kick, ban, teleport, shadow restriction, or gameplay change.
- No raw user-generated content or client-supplied detail retained.
- All subject, event-ID, cohort, and review collections have explicit caps and expiry.
- One player repeatedly triggering one signal cannot create a raid alert.
- A join burst without corroborating activity does not become a high-confidence raid.
- Ordinary high-traffic sessions and reconnect waves are measured before thresholds are enabled.
- MessagingService failure cannot disable local detection.
- Unauthorized staff cannot query player or cohort review data.
- Phase 21 case creation remains an explicit, permission-checked staff action.
- Studio and published-server acceptance tests are completed before any installer release pin is advanced.

**Release boundary:** This extension is a design specification on the Phase 15 hardening branch. It does not modify the live Roblox place, does not change the existing installer pin, and is not a claim of runtime raid-detection capability.
