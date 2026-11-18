# Phase 24 — Production Release & Legacy Retirement

**Status:** Release procedure and rollback boundaries documented. Phase 24.1 incident-intake hardening is tracked on `phase24-incident-response-hardening`; Studio and published multiplayer tests remain outstanding.

## Release candidate

- Branch: phase24-incident-response-hardening
- SecurityCore remains the central authorization source for audited controller, global-service, spectator, threat-review, incident and report-intake paths.
- Installer release pin: 9719eb20b2e8d7cf7716bfcb23d633c4e8943322 (the exact source commit containing the additive IncidentResponse intake methods).
- The Global Service loader must use the same SecurityCore release pin. The Phase 32 modules remain independently pinned.
- Install only in a dedicated test place first. Record the exact branch commit installed.
- Keep the existing single ClubMusic controller and single Global Service owner. Never install a second queue/playback controller or the standalone legacy Music System / MusicRemotes transport alongside the secured controller.

## Pre-release gates

- [ ] Verify the live place hierarchy and all installed scripts match the documented integration guide.
- [ ] Inspect binary Roblox assets and third-party packages, or explicitly exclude them from the security certification scope.
- [ ] Run the Studio multiplayer authorization, remote abuse, incident, spectator, movement, purchase and lifecycle test matrices.
- [ ] Run published two-server tests for retained global moderation/configuration/announcement/receipt features only, using isolated test data. Do not test or enable cross-server playback sync.
- [ ] Confirm the modern AudioPlayer controller, crossfade, independent per-server playback clocks, Auto DJ selection and local queues work independently in two servers. Confirm no playback leader, shared snapshot, playback lease, or cross-server queue reconciliation is active.
- [ ] Confirm developer-product receipt idempotency and profile/session-save recovery.
- [ ] Confirm UtilityBar, Tiki Tide Settings, VIP access, DJ 100, Moderator 150, Admin 200, Co-owner 254 and Owner 255 behavior.
- [ ] Profile load, memory, server shutdown, reconnect and repeated installer execution.
- [ ] Verify staff commands and permissions, including replay, threat review, incident escalation, diagnostics and spectator controls.
- [ ] Capture a rollback snapshot and record the previous installed release revision.

## Legacy retirement policy

- The root-level standalone legacy Music System and its MusicRemotes transport are documented as reference-only and must not be installed alongside the current controller.
- Do not delete retained reference source solely because it is legacy. Archive or delete only after confirming no live-place consumer or packaged model depends on it.
- Do not retire SafeCall, ErrorHistory, watchdog, registry or other diagnostics components until dynamic consumers, embedded assets and live-place references are reconciled.
- Do not remove compatibility aliases or installer rollback assets until a full compatibility pass succeeds.
- No legacy diagnostic implementation is retired by this phase.

## Rollback procedure

1. Stop rollout and preserve the failing server logs and exact release commit.
2. Restore the previous installer backup snapshot and previous pinned module set.
3. Confirm only one controller, one Global Service owner and one active remote transport remain.
4. Verify receipt ledger, profile/session state and cross-server configuration are not overwritten or reset.
5. Run smoke tests for playback, queue, purchase, UtilityBar and Settings before reopening the test place.
6. Do not attempt to repair by deleting player data, clearing receipt ledgers, or enabling the standalone legacy Music System.

## Sign-off

A release is production-ready only after the owner confirms the live-place revision and the complete test matrix passes. Source commits, static checks and owner-reported operation are useful evidence, but they do not replace a reproducible test record.

## Retired playback sync and storage minimization

- Global playback synchronization is retired. Each server owns its own active track, playback clock, Auto DJ selection, crossfade lifecycle, and request queue.
- Playback must not depend on MemoryStore, DataStore, or MessagingService. A server restart starts a new local playback lifecycle.
- The Global Service's shared MemoryStore rate-limit map is disabled in minimal-storage mode; bounded per-server rate limits remain active.
- MemoryStore-backed SecurityCore/global operations services (idempotency, audit, incident snapshots) require separate consumer and acceptance-test review. They are not playback services and must not be removed until their live callers and required staff workflows are reconciled.
- Keep DataStore/MessagingService only for separately approved global features with demonstrated consumers, such as moderation/configuration/announcements/catalog invalidation/receipt protection. Their existence does not authorize playback synchronization.
- SecurityCore movement authorization remains a bounded, expiring server-local ledger and must not acquire a DataStore or MemoryStore dependency.
