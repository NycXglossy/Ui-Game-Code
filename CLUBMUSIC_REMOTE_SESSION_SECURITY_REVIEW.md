# ClubMusic Remote, Session, and Runtime-State Security Review

Date: 2026-11-15
Branch: `feature/sultan-settings-2026-11-10`

## 1. Remote routing: already centralized

The controller already uses one client-to-server gameplay dispatcher:

- `ReplicatedStorage/ClubMusicRemotes/RequestAction` is the single gameplay `RemoteEvent`.
- `ACTION_COOLDOWNS` is the allowlist of supported action names.
- `ControllerFunctions.handleAction` rejects unknown actions, non-string/oversized action names, malformed payloads, excessive top-level/nested keys, oversized strings, unsupported value types, and non-finite numbers before routing.
- Per-player and server-wide token buckets are applied before the action handler runs.
- The handler performs action-specific validation and server-side authorization.
- `GetState`, catalog, and playlist RemoteFunctions are read-only query endpoints. `StateChanged` and `Notice` are server-to-client outputs.
- `PurchaseDiagnostic` is intentionally separate untrusted telemetry; it has its own per-player rate limit and never proves a purchase. `ProcessReceipt` remains the purchase authority.

Do not collapse server-to-client notifications and read-only query endpoints into the mutation dispatcher. Do not expose a generic client-selectable service/method invocation interface.

ByteNet or Blink is not required to gain this architecture. Consider a typed network library only as a separately tested migration, after measuring payload/serialization benefits and confirming compatibility with the existing UI and remotes.

## 2. Profile session locking: already present

The controller already implements a DataStore `UpdateAsync` session lease in `SunsetStageClubProfiles_v1`:

- A profile is acquired before being placed in the live in-memory profile table.
- The lease records `owner` and `expiresAt`; another unexpired server's lease causes acquisition to fail closed.
- Saves verify the current owner inside `UpdateAsync` before writing.
- Successful periodic profile saves refresh the 180-second lease; XP settlement schedules a save every 60 seconds.
- Player departure performs a final save and releases the lease only after that save succeeds.
- Failed final saves retain the lease until expiry instead of exposing potentially stale data.
- Receipt persistence uses the same per-user writer lock and preserves the separate Prepared/Completed receipt journal and pending-receipt recovery protocol.

Do not install ProfileStore or another profile library alongside this implementation. A migration requires a separate compatibility plan for the existing profile schema, session ownership, title migration, receipt journal, pending receipt marker, Studio memory mode, and every writer. A library must become the single profile authority, not a second lock layered over the existing one.

## 3. Player-removal cleanup

The controller already clears the majority of per-user runtime maps on `Players.PlayerRemoving`, including request/action timestamps, action cooldown maps, token buckets, query throttles, pending audio, rank/permission caches, pass caches, moderation flags, and XP state. The purchase telemetry limiter has its own PlayerRemoving cleanup.

This hardening pass additionally clears:
- `profileWriteLocks[userId]` after final save/lease handling.
- `skipVotes[userId]` after the vote manager has processed departure.

Durable DataStore profiles, moderation records, and receipt journals are intentionally retained.

## 4. Validation still required in Roblox

Repository source review does not prove live behavior. Test in an isolated published environment:

1. Rapidly teleport/rejoin the same account and verify only one server can acquire the profile.
2. Force a save failure and verify the lease is retained.
3. Verify successful saves renew the lease before the 180-second expiry.
4. Retry a developer-product receipt during a server handoff and verify exactly-once reward recovery.
5. Send unknown actions, oversized/nested payloads, NaN/infinity, and rapid valid actions; verify rejection/rate limiting without affecting legitimate UI requests.
6. Join/leave repeatedly and inspect that per-user cache/rate-limit/debounce entries are cleared.

No external profile library or network protocol dependency was added in this pass.
