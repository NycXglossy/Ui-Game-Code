# ClubMusic Optional Global Playback-Only Sync

Status: **Integrated on `integration/tiki-tide-system-consolidation`; opt-in and disabled by default.** This is static repository integration, not a Roblox runtime certification.

## Intended behavior

When an Owner or Co-Owner enables the shared setting, participating public servers follow one authoritative Now Playing stream:
- current track metadata and track changes;
- shared playhead position and server-time anchor;
- pause, resume, restart, and skip from the elected leader;
- leader status and authority readiness in the DJ Booth UI.

Every server retains its own independent request queue and local selection state:
- player requests, request limits, and queue order;
- queue reordering/removal and request moderation;
- local playlist rotation and Auto DJ refill;
- local skip-vote state.

The elected leader consumes **its own local queue** when selecting the next shared track. Followers never import, publish, or mutate another server's queue. A follower's own queue remains intact and becomes eligible to drive playback if that server later becomes leader or if sync is disabled.

When sync is disabled, each server stops following and continues independently from its current track, then advances from its own local queue. Disabling sync does not delete or merge any queue.

## Implementation

### Playback authority

- `MusicGlobalPlaybackAuthority.lua` stores only the current track, pause state, position, server-time anchor, playback revision, and leader fencing identity.
- The authority uses a dedicated DataStore snapshot and a MemoryStore expiring leader lease.
- Each leadership term claims a monotonically increasing durable fencing generation.
- A playback commit must match the current revision, generation, leader token, and leader JobId. A stale former leader cannot overwrite a newer term after the new fence is committed.
- The Playback MessagingService topic carries mode-change and snapshot-invalidation messages only; DataStore remains the recovery source.
- The module is included in `ClubMusic_Global_Optional_Services.rbxmx`. Install it as a ModuleScript named `MusicGlobalPlaybackAuthority` somewhere under ServerStorage (the global service resolves the exact module name recursively).

### Global service

- `ClubMusic_Global_Service_server_1.lua` exposes status, snapshot, leadership, commit, and authorized setting APIs.
- The shared `playbackSyncEnabled` config defaults to `false`.
- The service independently checks SecurityCore `GlobalConfig` authorization when the setting is changed.
- Studio cross-server services remain isolated by default (`EnableInStudio = false`).
- The service reconciles the shared setting and renews/elects the fenced leader on an eight-second cadence.

### Controller and UI

- `UI_Server_Controller_server (1).lua` keeps the existing modern AudioPlayer backend and local queue manager.
- The controller applies playback-only snapshots to the local modern audio source and periodically reconciles missed MessagingService invalidations.
- Only the elected leader may advance, skip-vote, pause/resume, or restart while sync is active. Playback controls issued on a follower are rejected rather than forwarded.
- Queue contents, local playlist state, request locks, and local moderation state are not included in playback snapshots.
- `UI_Renderer (2).lua` exposes the mode and leader status in the Owner/Co-Owner DJ Booth controls. The server and SecurityCore revalidate authorization; the client UI is not trusted.

## Installation and configuration

1. Keep the shared `playbackSyncEnabled` setting at its default `false` during installation.
2. Install `MusicGlobalPlaybackAuthority` from `ClubMusic_Global_Optional_Services.rbxmx` as a ModuleScript under ServerStorage.
3. Install the current Global Service and UI Controller scripts in their existing server locations.
4. Ensure the experience has the required published DataStore and MemoryStore access. Do not enable Studio cross-server access in the production place for convenience.
5. Enable the setting only in a dedicated published test universe after the test plan below is run and recorded.

## Required validation before production

- two- and three-server leader election and follower status;
- independent request queues before, during, and after sync;
- leader track changes, pause/resume, restart, skip, and natural track end;
- follower control rejection;
- forced leader shutdown, lease expiry, takeover, and stale-leader fencing;
- missed-message reconciliation;
- DataStore, MemoryStore, and MessagingService outage/recovery;
- disable/re-enable behavior and Studio isolation;
- modern AudioPlayer startup, seek, pause/resume, reload, and crossfade interaction.

No Roblox Studio or published multi-server runtime tests have been executed as part of this integration. Keep the setting disabled until these tests pass.
