# ClubMusic Global Health and Recovery — Historical Phase 1 Notes

> Historical design record. The standalone Global Health and Global Recovery ModuleScripts described in the original version of this document are not present in the current repository branch. Do not create or install copies from this document.

## Current implementation

The current branch consolidates diagnostics into these server-local components:

- `ClubMusic_Global_Diagnostics_Service.lua` — coordinator and read-only snapshot.
- `ClubMusic_Local_Service_Registry.lua` — bounded local service availability registry.
- `ClubMusic_Server_Health_Service.lua` — local Heartbeat and process-memory observations.
- `ClubMusic_Local_Watchdog_Service.lua` — local progress pulses for Playback, AutoDJ, Queue, Moderation, and Recovery.
- `ClubMusicErrorHandler.lua` — bounded local error history and duplicate aggregation.
- `ClubMusic_Global_Service_server_1.lua` — wires the modules into the existing ServerStorage BindableFunction API.
- `UI_Server_Controller_server (1).lua` — reports local playback/queue/moderation progress and provides an authorized admin summary.

See `CLUBMUSIC_DIAGNOSTICS_IMPROVEMENT_PLAN.md` for the current installation and verification checklist.

## Historical safety decisions retained

- Diagnostics never owns queue or playback state.
- Diagnostics never retries storage operations or performs recovery.
- Error reporting is optional and cannot block service startup.
- Error history is bounded and local to the current server process.
- A failed backend read is not treated as proof that a player is banned.
- A pending catalog reservation is not cleared, expired, or rewritten by diagnostics.
- Detailed error records and tracebacks remain server-side.

## Current recovery boundary

There is no standalone Global Recovery ModuleScript in the current branch. Playback recovery remains inside the existing controller-owned playback watchdog. The diagnostics Watchdog only observes and reports progress; it does not trigger that recovery path.

The diagnostic Recovery probe reports `NotInstalled` until an explicit local recovery status provider is wired. This is not itself a failure and does not block ClubMusic startup.

## Local-only diagnostics constraint

No diagnostic heartbeat, peer-server registry, cross-server metrics, or cross-server error aggregation is permitted. Existing cross-server ClubMusic features continue independently, while diagnostics reports only the current server's local observations.

## Verification

The current coordinator, registry, ServerHealth, Watchdog, and ErrorHistory sources have been statically inspected and committed. Roblox Studio and published-server runtime testing remain required.
