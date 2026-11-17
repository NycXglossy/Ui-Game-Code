# Phase 24 — Production Release & Legacy Retirement

**Status:** Release procedure and rollback boundaries documented. This phase is not permission to publish unverified source automatically.

## Release candidate

- Branch: security/phase1-foundation
- SecurityCore is the central authorization source for audited controller, global-service, spectator, threat-review and incident paths.
- Installer release pin must reference the exact source commit containing the approved SecurityCore modules and client adapters.
- Install only in a dedicated test place first. Record the exact branch commit installed.
- Keep the existing single ClubMusic controller and single Global Service owner. Never install a second queue/playback controller or the standalone legacy Music System / MusicRemotes transport alongside the secured controller.

## Pre-release gates

- [ ] Verify the live place hierarchy and all installed scripts match the documented integration guide.
- [ ] Inspect binary Roblox assets and third-party packages, or explicitly exclude them from the security certification scope.
- [ ] Run the Studio multiplayer authorization, remote abuse, incident, spectator, movement, purchase and lifecycle test matrices.
- [ ] Run a published test server with two-server MemoryStore/MessagingService tests using isolated test data.
- [ ] Confirm the modern AudioPlayer controller, crossfade, local queues and optional playback-only global sync are unchanged and working.
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
