# Phase 11 — StaffSpectatorService

**Status:** Server authority, camera adapter, and installer integration are implemented in source. Studio and published-server verification remain outstanding.

## Components

- `ClubMusicSecurityCore/StaffSpectatorService.lua`: server-only state, authorization, target validation, lifecycle cleanup, movement suspension/restoration, and audit callbacks.
- `StaffSpectatorCamera.client.lua`: presentation-only camera adapter. It follows the target's Humanoid, handles target respawns/leave, disables normal PlayerModule controls during observation, and restores the staff camera/controls on exit.
- `ClubMusic_Security_Core_Installer.lua`: stages and installs the module into ServerStorage/ClubMusicSecurityCore and the LocalScript into StarterPlayer/StarterPlayerScripts. It pins the source release and retains previous copies for rollback.

## Authority and behavior

- Entry and target switching require a live staff Player and the existing SecurityCore `GlobalModeration` permission. No client permission or target claim is trusted.
- The service resolves targets through the server's live Players list, rejects invalid IDs and self-targeting, and requires a living target Humanoid.
- The server publishes only the staff observer's own spectator attributes. The client LocalScript uses those attributes only to select a camera subject; it cannot enter, switch, or authorize observation.
- During observation, the server saves the staff Humanoid's current WalkSpeed, JumpPower, JumpHeight, AutoRotate, UseJumpPower, and Jumping-enabled state, then suspends movement. Exit restores the captured values. Re-entering an active session is rejected; use SwitchTarget.
- The service automatically exits when the observer's character is removed, clears observer state if a target leaves, and cleans up on player departure or service shutdown.
- Enter, switch, exit, target departure, and staff departure are sent to the existing global audit endpoint when it is available. If unavailable, the bootstrap emits a bounded warning rather than claiming a durable audit succeeded.
- The local observer-control attribute `TikiTideSpectatorNoWorldActions` is available for other server gameplay services to honor. This phase does not claim every existing gameplay remote already checks that attribute.

## Server-only control API

The installer exposes `ServerStorage.TikiTideStaffSpectatorControl` as a BindableFunction for trusted server scripts only:

```lua
local control = game:GetService("ServerStorage"):WaitForChild("TikiTideStaffSpectatorControl")
local ok, message = control:Invoke("Enter", staffPlayer.UserId, targetPlayer.UserId)
-- Switch target: control:Invoke("SwitchTarget", staffPlayer.UserId, nextTarget.UserId)
-- Exit:         control:Invoke("Exit", staffPlayer.UserId)
-- State:        control:Invoke("GetState", staffPlayer.UserId)
```

Do not expose this BindableFunction through a client RemoteFunction/RemoteEvent without a separate server-authorized request adapter. The BindableFunction is intentionally server-only.

## Explicit limitations

- This phase supplies the server service and camera presentation, but does not add a Kohl's Admin command, staff GUI button, or chat command. A trusted server command/UI adapter must call the BindableFunction.
- The staff character remains in the world and visible to other players. This is not invisibility, noclip, or an untraceable mode; the target receives no explicit spectator notification from this service.
- Client control disabling is presentation/UX only. Server-side movement suspension is authoritative, but every other gameplay action/remote must separately honor the `TikiTideSpectatorNoWorldActions` state before claiming total interaction lockdown.
- No automatic kick, ban, moderation restriction, or target manipulation is performed.
- No Roblox runtime test is claimed by this source change.

## Studio test plan

1. Install with simulation stopped and verify the module, bootstrap, and LocalScript are present in their intended containers.
2. Confirm a Moderator/Admin with `GlobalModeration` can enter; a guest and an unauthorized client request cannot.
3. Verify target self-selection, invalid IDs, departed targets, missing/dead Humanoids, and simultaneous requests are rejected safely.
4. Verify observer camera follows target and target respawn, while normal movement controls are disabled.
5. Switch targets repeatedly; ensure the original movement snapshot is not overwritten.
6. Exit and verify original movement/jump/rotation settings and camera controls are restored.
7. Verify observer character respawn, target departure, staff departure, and server shutdown cleanup.
8. Verify audit records and fallback warnings, then regression-test Kohl's Admin, Utility Bar, Tiki Tide Settings, and desktop/mobile/console behavior.
