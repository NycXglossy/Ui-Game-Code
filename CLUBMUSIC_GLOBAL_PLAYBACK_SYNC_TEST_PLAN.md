# ClubMusic Playback Regression and Optional Sync Test Plan

Status: Optional playback-only sync is integrated on `integration/tiki-tide-system-consolidation`, but the shared setting remains **OFF by default**. Record Studio and published-server results separately. Static repository checks are not runtime certification.

## Test setup

- Use a dedicated published test universe with at least two servers and API services enabled for cross-server tests.
- Use non-production accounts for purchase and moderation tests.
- Keep Studio isolation enabled by default (`EnableInStudio = false`).
- Start with `playbackSyncEnabled = false`.

## Local playback regression tests (sync OFF)

| ID | Scenario | Expected result |
|---|---|---|
| L01 | Start two game servers and add different requests | Each server retains its own queue and current track. |
| L02 | Run Auto DJ in both servers | Each server selects and advances tracks independently. |
| L03 | Skip, pause, resume, and restart on server A | Only server A's playback state changes. |
| L04 | Reorder, remove, and clear queue entries on server A | Only server A's queue changes. |
| L05 | Trigger a crossfade | The modern incoming deck fades in and outgoing audio is cleaned up without an extra queue advance. |
| L06 | Change client A's volume or mute | Client B's output level remains unchanged. |
| L07 | Reload/rebuild the modern audio backend | The same track, playhead, speed, and pause state are restored where recovery supports it; the queue is not advanced twice. |
| L08 | Restart a server | The new server starts its own local playback lifecycle and does not inherit another server's queue. |

## Optional playback-only sync tests (sync ON)

| ID | Scenario | Expected result |
|---|---|---|
| S01 | Owner enables sync from the DJ Booth | The shared config is saved; the UI reports enabled and waits for a leader. |
| S02 | Co-Owner enables/disables sync | The server accepts the authorized setting change and publishes the mode change. |
| S03 | Guest, DJ, or Moderator attempts to change the mode | Server-side `GlobalConfig` authorization rejects the action. |
| S04 | Start two servers with different local queues, then enable sync | One server becomes leader; both display the leader's Now Playing track. Each queue remains unchanged and distinct. |
| S05 | Add/reorder/remove requests on a follower | Only that follower's local queue changes; it is never written to the shared playback snapshot. |
| S06 | Leader selects the next track from its local queue/Auto DJ/playlist | Followers apply the shared track and playhead; their local queues remain untouched. |
| S07 | Attempt skip, skip vote, pause/resume, or restart from a follower | The follower rejects the control and does not change shared playback. |
| S08 | Use skip, pause/resume, and restart on the leader | The resulting playback state is committed and reconciled to followers. |
| S09 | Let the leader reach a natural track end | Only the leader advances from its local queue; followers follow the committed next track. |
| S10 | Force the leader server to shut down | Its lease expires/releases; another server acquires leadership and continues from its own local queue. |
| S11 | Wake the former leader after takeover | Its stale fencing token/revision cannot overwrite the new leader's playback snapshot. |
| S12 | Drop a Playback MessagingService invalidation | Periodic snapshot reconciliation repairs the follower's Now Playing state. |
| S13 | Temporarily interrupt DataStore or MemoryStore | Authority status becomes degraded; stale leaders cannot commit; recovery restores a single leader. |
| S14 | Disable sync while multiple servers are active | Each server stops following, continues from its current track, and uses its own local queue for subsequent transitions; no queue is deleted or merged. |
| S15 | Disable then re-enable sync | The service re-elects a leader; each server's local queue remains intact. |
| S16 | Attempt to enable sync in default Studio isolation | The service rejects the change with a Studio-isolation message; local playback remains usable. |
| S17 | Test modern AudioPlayer startup, seek, pause, resume, reload, and crossfade while following | Followers converge on the leader's track/playhead without falling back to legacy audio or modifying local queues. |

## Shared-service regression tests

| ID | Scenario | Expected result |
|---|---|---|
| G01 | Block a player or track through global moderation | The moderation change reaches active servers and is enforced locally. |
| G02 | Publish an announcement or shoutout | The event reaches eligible active servers without changing playback. |
| G03 | Change a global XP boost | The shared boost state reaches active servers; local queues remain independent. |
| G04 | Change the catalog | Servers refresh catalog data through invalidation; playback snapshots contain no catalog or queue data. |
| G05 | Attempt an unauthorized global action | Server-side authorization denies it regardless of client UI state. |
| G06 | Send malformed or repeated remote requests | Server-side validation and rate limits reject or throttle them. |

## Evidence to record

For each test, record:
- date/time and test universe/place;
- server JobIds and which server held leadership;
- before/after Now Playing track IDs and playhead positions;
- before/after local queue IDs on every server;
- DataStore, MemoryStore, and MessagingService errors;
- whether the expected result passed, failed, or was not run.

Do not enable the mode in production until the multi-server cases pass. No Roblox Studio or published-server runtime tests have been executed by this code integration.
