# ClubMusic Global Catalog Consistency — Phase 2

## Scope

This phase closes the cross-server race between catalog mutation and global queue writes. It also corrects the Kohl's Admin custom-command success feedback contract. The existing admin command mappings, permission checks, action handlers, and `;cmskip` behavior are unchanged.

## Kohl's Admin success notification fix

Kohl's Admin treats a non-nil string returned by a custom command's `run()` callback as an error notification. The shared ClubMusic addon previously returned success text for accepted commands, which caused successful operations to appear as command failures.

The addon now:
- Returns `nil` for accepted commands.
- Continues returning a string for genuine rejection and invocation failures.
- Uses Kohl's Admin's informational notification API for `;cmstatus` and `;cmqueue` results.
- Leaves ClubMusic's existing success notices for state-changing commands intact.

## Shared catalog revision and reservations

The global queue DataStore state now includes:
- `catalogRevision`: a monotonic catalog epoch.
- `catalogChangeTrackId`: the ID currently being added or removed.
- `catalogChangeKind`: `add` or `remove`.

The new fields are backward-compatible with existing schema-version-1 queue state. The sanitizer defaults older records to revision zero and preserves the earlier in-branch removal reservation field during rollout.

### Queue write fencing

Every global single-entry enqueue, automatic batch enqueue, and fallback transition must provide the server's locally synchronized catalog revision. The shared queue transaction rejects a stale revision. A server that receives a revision mismatch refreshes its catalog before retrying. The queue transaction also rejects an entry matching the active catalog-change reservation.

This covers player requests, Auto DJ/playlist batches, and empty-queue fallback transitions. A stale server cannot rely only on its local catalog cache to enqueue an ID after another server changes the catalog.

### Catalog addition

In global mode, the controller reserves the track ID in the global queue DataStore before writing the catalog record. The reservation advances the catalog revision and blocks enqueues for that ID. After the catalog write is confirmed, the controller completes the reservation and publishes catalog invalidation.

If a server stops after the catalog write but before finalization, retrying the same audio addition refreshes the catalog and completes the existing reservation when the record is already present.

### Catalog removal

In global mode, removal first atomically reserves the track ID in the same DataStore used by global queue writes. The reservation transaction rejects removal if the track is current or queued. Only after reservation succeeds does the controller refresh and mutate the catalog DataStore.

The reservation is completed only after:
1. The catalog refresh confirms the removed record is absent (or the removal call succeeds).
2. Any active shared playlist rotation has been synchronized.

If the catalog write outcome is uncertain, the reservation remains active. If the controller stops midway, retrying `;cmremove custom-<assetId>` resumes the same reservation. The reservation is deliberately not auto-expired: expiring it could reopen the race if the catalog write had committed just before a server stopped.

### Recovery behavior

A pending reservation is fail-safe but can temporarily block further catalog mutations. Retry the same add/remove operation after storage recovers. Do not manually edit the global queue DataStore or clear the reservation by hand.

The reservation is single-operation at a time. This deliberately serializes catalog mutations so an add cannot race a removal or another add. Enqueues for unrelated IDs can continue using the current revision.

## Files changed

- `KohlsAdmin_ClubMusic_Addon.lua`
- `MusicGlobalQueueService.lua`
- `ClubMusic_Global_Service_server_1.lua`
- `UI_Server_Controller_server (1).lua`

## Deployment notes

1. Update the existing scripts/modules in their current locations; do not create a second controller or global service.
2. Deploy the four files together so the global service and controller use the same reservation API.
3. Restart/roll over existing live servers after deployment. Servers still running the pre-revision controller can continue using the old enqueue contract until they shut down.
4. Keep `EnableInStudio=false` as the default. Use a separate test universe for intentional cross-server tests.

## Verification status

- Repository files were fetched after each update and their resulting blob hashes matched the committed content.
- Static call-path review covered global single enqueue, batch enqueue, fallback advance, catalog add, catalog remove, and playlist rotation synchronization.
- No Roblox Studio runtime, live multi-server race, or Kohl's Admin UI test was run by the assistant. Those checks remain required before publishing to the live experience.
