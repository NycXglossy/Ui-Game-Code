# ClubMusic Local Playback — Studio Regression Plan

Status: Current test plan for the local-only playback architecture (2026-11-15).

## Test setup

- Use a dedicated published test place or a Studio server with at least two clients.
- Each live server must own its own queue, current track, playback clock, Auto DJ selection, and crossfade transitions.
- Do not enable or test a global queue, playback leader, shared playback clock, or cross-server queue reconciliation; those features have been retired.
- Use non-production test accounts for purchase and moderation tests.

## Local playback tests

| ID | Scenario | Expected result |
|---|---|---|
| L01 | Start two game servers and add different requests | Each server retains its own queue and current track. |
| L02 | Run Auto DJ in both servers | Each server selects and advances tracks independently. |
| L03 | Skip, pause, resume, and restart on server A | Only server A's playback state changes. |
| L04 | Reorder, remove, and clear queue entries on server A | Only server A's queue changes. |
| L05 | Trigger a crossfade | The incoming deck fades in and the outgoing deck is cleaned up without an extra queue advance. |
| L06 | Change client A's volume or mute | Client B's output level remains unchanged. |
| L07 | Reload or rebuild the modern audio backend | The same track, playhead, speed, and pause state are restored where recovery supports it; the queue is not advanced twice. |
| L08 | Restart a server | The new server starts with its own local playback lifecycle; it does not inherit another server's queue or playback clock. |

## Shared-service regression tests

| ID | Scenario | Expected result |
|---|---|---|
| G01 | Block a player or track through global moderation | The moderation change reaches active servers and is enforced locally. |
| G02 | Publish an announcement or shoutout | The event is delivered to eligible active servers without changing playback. |
| G03 | Change a global boost | The shared boost state is delivered to active servers; local queues remain independent. |
| G04 | Change the catalog | Servers refresh catalog data through invalidation; playback timelines remain local. |
| G05 | Attempt an unauthorized global action | Server-side authorization denies it regardless of client UI state. |
| G06 | Send malformed or repeated remote requests | Server-side validation and rate limits reject or throttle them. |

Record Studio and published-server results separately. A static repository audit is not a runtime certification.
