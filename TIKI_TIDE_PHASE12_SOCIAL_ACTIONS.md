# Tiki Tide Social Actions — Phase 12

## Files and placement
- `TikiTideSocialActions/AnimationConfig.lua`: ModuleScript under the new server script's `TikiTideSocialActions` child folder.
- `TikiTideSocialActions.server.lua`: Script in ServerScriptService.
- `TikiTideSocialActions.client.lua`: LocalScript in StarterPlayer/StarterPlayerScripts.

## Configure your animation assets
Set the five numeric IDs in AnimationConfig to the assets you own/manage:
- Dance1, Dance2, VIPDance
- HugActor, HugTarget

Use numeric IDs only. The service fails closed for an unconfigured animation. No animation assets were created or uploaded.

## Security and behavior
- Server-authoritative action whitelist; clients cannot supply asset IDs or choose arbitrary animation names.
- Dance1/Dance2 require server-set Tiki Tide entitlement; VIPDance additionally requires server-set VIP/VVIP/Tiki Tide entitlement.
- Hug requires both players to have Tiki Tide access, a live character/Humanoid/root part, and distance <= 12 studs.
- Invitations have unique server-generated IDs, a 20-second expiry, one outstanding invite per sender/recipient, sender cooldown, inbound recipient cooldown, accept/decline/cancel lifecycle, and cleanup on either player leaving.
- Distance, entitlement, player identity and character state are checked again on acceptance.
- Playback is server-initiated on server-created/located Animators. Only tracks owned by this social-action service are stopped; unrelated Action-priority tracks are untouched.
- Requests use separate client-to-server and server-to-client RemoteEvents. Payload shape/size, per-player token bucket, cooldowns and action names are bounded.
- No DataStore schema, Tiki Tide Settings remotes, SecurityCore authorization path, teleport consent, or Phase 10 teleport protections are modified.

## Deployment and verification
This is source-only. Place the scripts/modules as listed above and configure the IDs before enabling the feature. Run Studio multi-client tests for solo actions, VIP denial/grant, invite accept/decline/expiry/cancel, player departure, respawn between invite and accept, distance changes, concurrent invites, and malformed/flooded requests. Verify all five assets are permitted for this experience/group. No Studio or published-server test is claimed.
