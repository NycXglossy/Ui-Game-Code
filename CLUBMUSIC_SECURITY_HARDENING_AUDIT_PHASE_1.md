# ClubMusic Security Hardening Audit — Phase 1

Branch: \`audit/hardened-clubmusic-2026-11-08\`

Audit date: 2026-11-10

## Scope

Static review of the current server-side ClubMusic controller, the catalog and playlist services, and the global service budget/API boundary.

Reviewed areas:
- Client-to-server action event validation and action allowlisting.
- Client-callable state, catalog, and playlist RemoteFunctions.
- Per-player and per-server throttles plus cross-server shared budgets.
- Staff, administrator, Sultan, and moderation permission checks.
- Playlist and custom catalog persistence validation.
- Custom title filtering and profile mutation paths.
- ServerStorage-only BindableFunction integration boundary.

This is a code review, not a penetration test or runtime certification.

## Results

### 1. Client action contract

The action handler checks that the caller is still connected, the action is a bounded string, the payload is a bounded table, and the action is allowlisted before it spends shared budget or dispatches behavior.

The payload validator limits top-level keys to 16, nested keys to 16, key lengths to 32 bytes, string values to 1,024 bytes, and accepts only finite numbers, strings, booleans, and one level of bounded nested tables.

### 2. Rate limiting and shared service

Recognized actions pass local token-bucket limits and the global action budget. Live servers fail closed when the global action-budget call cannot be confirmed.

Client-callable state/catalog/playlist queries also use local and shared query budgets and per-player cooldowns. The catalog service independently clamps offsets to 0–10,000 and page sizes to 1–50.

Audio asset inspection now fails closed in live servers unless the shared audio budget explicitly confirms capacity. Studio retains its isolated local fallback behavior.

### 3. Permission checks

Static review confirmed server-side checks for:
- Staff-only playlist management and DJ controls.
- Staff-only custom catalog management and Creator Hub audio inspection.
- Administrator-only queue clearing and moderation actions.
- Sultan-only title slot selection, clearing, and visibility controls.
- Target moderation rank checks that reject self-targeting and equal/higher-ranked targets.

Player request, favorites, skip voting, rewards, and owned-cosmetic actions are separately validated against server-owned profile and queue state.

### 4. Persisted data and user content

- Playlist data is sanitized on load/refresh and bounded to 30 playlists and 100 tracks per playlist.
- Custom catalog records are shape-checked and sanitized; malformed persisted records are not silently rewritten by mutations.
- Catalog paging is clamped inside the service, not only at the remote boundary.
- Custom title content is allowlist-validated, filtered through Roblox text filtering, and checked again against the same profile after the yielding filter request.

### 5. Server-only integration

The global API uses BindableFunctions in ServerStorage. The client-facing remotes do not expose those Bindables. The Kohl's Admin bridge remains server-side and continues to pass through ClubMusic's own rank authorization, action validation, cooldowns, and shared budgets.

## Code change made during this phase

Commit: \`44d285342c10e2f4f3e0599dbe9efa0b0ee2f4a9\`

The live Creator Hub audio inspection path previously allowed local-only fallback if the shared audio-budget API failed to respond. It now rejects the inspection unless the shared budget explicitly returns \`true\`. This closes the aggregate-budget fail-open path during shared-service failures.

## Runtime verification still required

No Roblox Studio runtime or multi-server test was executed as part of this static audit. Before production release, test in a separate published test universe:

1. Send malformed actions: unknown action names, non-table payloads, oversized strings, excess keys, nested tables, NaN, and infinity. Confirm rejection without errors or state changes.
2. Send rapid action and query bursts from one client and several clients. Confirm local and shared limits engage and recover after refill.
3. Temporarily make the shared budget API unavailable in a live-like test. Confirm action, state/catalog/playlist queries, and audio inspection fail closed as designed; confirm Studio isolation remains usable.
4. Invoke staff/admin/Sultan actions from ordinary accounts and test demotion while connected. Confirm no privileged mutation occurs.
5. Test playlist and catalog concurrent writes from multiple servers, malformed stored test fixtures, DataStore throttling, and refresh failures.
6. Test custom title filtering failure and player departure during the yielding filter call. Confirm no unfiltered text is applied and no unloaded profile is mutated.
7. Verify profile reward claims, title purchases, session locks, failed saves, reconnects, and concurrent sessions across separate servers.
8. Verify Kohl's Admin commands still work through the existing bridge and that \`;cmskip\`, pause, restart, and lock behavior remain unchanged.

## Conclusion

The reviewed server-side boundaries show layered validation, authorization, and throttling, with one shared audio-budget fail-open condition fixed in this phase. No additional confirmed client-facing permission bypass was established by this static pass.

Status: **Static review complete for the scope above; adversarial runtime and multiplayer verification pending.**

Do not describe the system as exploit-proof or production-certified until the runtime test matrix has been completed.


### 6. Profile persistence and purchase receipts

A follow-up static review covered the profile session lease, serialized profile writes, and Developer Product receipt handling:
- Profile acquisition uses an atomic DataStore update and refuses to load a profile owned by another unexpired server session.
- Profile saves verify the session token inside UpdateAsync and refuse to overwrite a profile after ownership is lost.
- Profile writes are serialized per user and coalesced to avoid unbounded save-task creation.
- Developer Product rewards use a per-purchase durable journal and a pending marker committed with the profile reward; retries verify purchase/user/product identity before acknowledging.
- Global XP boost receipts use their own purchase journal and a pending marker around the global timer update to make retries idempotent.
- A failed or incomplete receipt operation returns NotProcessedYet rather than acknowledging an unconfirmed reward.

These are static findings only. Fault-injection tests are still needed for server shutdown between each receipt transaction step, simultaneous receipt callbacks, lease expiry, and DataStore throttling.
