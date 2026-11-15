# ClubMusic Optional Global Playback Sync — Published Test Plan

## Safety setup
- Use a dedicated published test universe/place with the same scripts and DataStore/MemoryStore configuration as production.
- Keep `playbackSyncEnabled=false` until the first two-server baseline is ready.
- Do not use production player queues or production moderation data for destructive tests.
- Use at least two live server instances; three are recommended for takeover/re-election checks.
- Studio remains isolated by default (`EnableInStudio=false`).

## Test cases

| ID | Scenario | Expected result | Result |
|---|---|---|---|
| P01 | Enable sync with two servers online | Exactly one server reports Leader; the other reports Follower. | Not run |
| P02 | Leader starts/changes track | Both servers play the same track and metadata. | Not run |
| P03 | Leader pauses/resumes/restarts | All servers converge on the same playback state and position. | Not run |
| P04 | Staff on follower requests Skip | Command is forwarded and applied once by the elected leader. | Not run |
| P05 | Leader advances at track end | One next-track decision is made from the leader's local queue. | Not run |
| P06 | Add different requests on each server | Queue contents/order remain distinct; no queue is copied or merged. | Not run |
| P07 | Change request lock or moderation on one server | The change remains local and does not alter another server's local request policy. | Not run |
| P08 | Shut down the leader | Lease expires/releases; a remaining server claims a higher durable fencing generation and becomes leader. | Not run |
| P09 | Resume/force an old leader after takeover | Its old generation/token cannot commit over the new leader's snapshot. | Not run |
| P10 | Temporarily interrupt MemoryStore/DataStore access | Status reports degraded/unavailable; server fails closed as leader and retries without crashing the service loop. | Not run |
| P11 | Restore service access | One server reacquires leadership safely; playback resumes from the latest durable snapshot. | Not run |
| P12 | Disable sync | Playback-only leadership is released; each server returns to its own local playback/queue behavior. | Not run |
| P13 | Re-enable sync | A single new leader is elected and a new fencing generation is established. | Not run |
| P14 | Run an ordinary isolated Studio session | Cross-server stores are not touched and local playback remains isolated. | Not run |

## Evidence to record
For each test, record:
- UTC timestamp and server JobId (shortened in shared notes);
- sync enabled state, leader/follower status, and fencing generation;
- current track ID and playback revision before/after the action;
- local queue contents on each server (test-only track/request identifiers);
- relevant Output warnings/errors;
- pass/fail and reproduction notes.

## Release gate
Do not enable global playback sync in production until:
1. P01–P09 pass repeatedly across fresh server instances.
2. P10–P11 demonstrate safe degradation and recovery.
3. P12–P14 pass, including Studio isolation.
4. No cross-server queue/request data appears in playback snapshots or messages.
5. The Owner/Co-Owner UI toggle and status accurately reflect the service.

**Current state:** Test plan prepared; all cases remain Not run. The code has not been runtime-validated by this change.
