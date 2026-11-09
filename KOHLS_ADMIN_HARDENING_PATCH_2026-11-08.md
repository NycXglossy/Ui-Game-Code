# Kohl's Admin Hardening Patch — 2026-11-08

## Current implementation

The repository contains:
- The original Kohl's Admin.rbxmx model (unchanged).
- Kohls_Admin_Hardening_Patch.lua, a Roblox Studio Command Bar patch for the imported model.

The patch script was compared against the actual uploaded Loader and MainModule source. It includes the following targeted changes:

1. Removes the Loader's runtime external MainModule fetch and Creator Store fallback.
2. Requires only the bundled local MainModule, fails closed if it is missing, and validates the returned initialize API.
3. Handles an absent Config safely when resolving legacy configuration and fails closed if legacy mode is selected without its configuration.
4. Validates KDelete arguments as live Instances belonging to the DataModel before destroying them.
5. Validates KPaste payload structure, destination, move flag, and every source Instance before changing anything; caps each paste batch at 100 Instances.
6. Adds per-player cooldowns and an allowlist for the legacy admin RemoteEvent operations, including the initial KuID handshake. The existing command dispatcher cooldown is retained.
7. Raises the built-in legacy native loadstring script command from power 5 (Owner) to power 6 (Game Creator), keeping the command available only at Game Creator level or above.
8. Validates the KCam response as a CFrame before reading LookVector.

## Dynamic-code findings

- The newer Creator addon contains script and localscript commands that use Kohl's custom Loadstring/FiOne execution path. The module is explicitly documented in-source as containing dangerous commands restricted to creators and is registered under the Creator command group.
- The legacy MainModule also contains a separate native loadstring script command. The patch raises that command's required power to 6 (Game Creator), rather than removing it.
- Both execution paths remain high-impact arbitrary-code capabilities. Do not grant Creator access to accounts that should not be able to run arbitrary server/client code. Disable these commands if your game does not require them.

## Important boundaries

- The model asset itself is still unchanged. The patch is a Studio-side source transformation; it has not been executed in Roblox Studio and is not yet baked into a replacement .rbxmx.
- The patch preserves the existing Kohl's Admin power checks for destructive operations and does not merge Kohl's Admin permissions with ClubMusic DJ, moderation, or staff permissions.
- The RemoteEvent cooldowns are a targeted abuse-control layer, not a substitute for authorization checks in every handler. Some command-specific listeners are registered dynamically; they still need full behavior testing.
- A complete review of all 344 embedded source-bearing items, all third-party dependencies, and all command argument paths remains outstanding.
- No Roblox Studio execution, multiplayer exploit test, or live production test has been performed.
- This is targeted hardening, not a certification that the entire admin package is safe.

## Apply and verify

1. Make a backup of the place/model first.
2. Import the current Kohl's Admin.rbxmx into Roblox Studio.
3. Select the Kohl's Admin root model/folder in Explorer.
4. Open View → Command Bar.
5. Run the complete current contents of Kohls_Admin_Hardening_Patch.lua from this branch.
6. Confirm the Output reports the loader, legacy configuration, delete/paste validation, RemoteEvent rate limiting, Creator-only native script command, and KCam validation edits.
7. Inspect the Loader source: it should contain no InsertService, LoadAsset, or external MainModule asset ID fallback.
8. Inspect the server MainModule: KDelete and KPaste should retain their server-side power check and include the new argument validation; ServerEvent should include the event allowlist and per-player cooldowns; the legacy script command should require power 6.
9. Test normal admin startup, legacy mode if used, command bar, delete/copy/paste, camera wind direction, and authorized/unauthorized users in a private test place. Test burst traffic to confirm rate limits do not disrupt normal UI usage.
10. Save/export the patched model as a new .rbxmx. Keep the original backup until Studio tests pass.

Do not deploy to the live place until the Studio-side patch and behavior tests pass.
