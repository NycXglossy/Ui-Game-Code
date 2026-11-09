# Kohl's Admin Hardening Patch — 2026-11-08

## Current implementation

The repository contains:
- The original Kohl's Admin.rbxmx model (unchanged).
- Kohls_Admin_Hardening_Patch.lua, a Roblox Studio Command Bar patch for the imported model.

The patch script was corrected on branch audit/kohls-admin-hardening-2026-11-08 after comparison with the actual uploaded Loader source. The earlier version expected a loader configuration block that did not exist verbatim and omitted the MAIN_MODULE_NAME declaration. Do not use the older version from the ClubMusic branch.

The current patch is designed to:
1. Remove the Loader's runtime external MainModule fetch and Creator Store fallback.
2. Require only the bundled local MainModule, fail closed if it is missing, and validate the returned initialize API.
3. Handle an absent Config safely when resolving legacy configuration and fail closed if legacy mode is selected without its configuration.
4. Validate KDelete arguments as live Instances belonging to the DataModel before destroying them.
5. Validate KPaste payload structure, destination, move flag, and every source Instance before changing anything; cap each paste batch at 100 Instances.

## Important boundaries

- The model asset itself is still unchanged. The patch is a Studio-side source transformation; it has not been executed in Roblox Studio and is not yet baked into a replacement .rbxmx.
- The patch preserves the existing Kohl's Admin power check (f.getPower(plr) > 4) and does not merge Kohl's Admin permissions with ClubMusic DJ, moderation, or staff permissions.
- The dynamic script/localscript command capability remains present. It is a high-impact arbitrary-code capability. This patch does not disable or sandbox it; review the associated command registration and disable those commands if not essential.
- General RemoteEvent rate limiting, comprehensive per-command argument validation, and a full review of every embedded script/tool remain outstanding.
- This is a targeted hardening patch, not a certification that the entire admin package is safe.
- No Roblox Studio execution, multiplayer exploit test, or live production test has been performed.

## Apply and verify

1. Make a backup of the place/model first.
2. Import the current Kohl's Admin.rbxmx into Roblox Studio.
3. Select the Kohl's Admin root model/folder in Explorer.
4. Open View → Command Bar.
5. Run the complete current contents of Kohls_Admin_Hardening_Patch.lua from this branch.
6. Confirm the Output reports the loader, legacy configuration, KDelete, and KPaste edits.
7. Inspect the Loader source: it should contain no InsertService, LoadAsset, or external MainModule asset ID fallback.
8. Inspect the server MainModule: KDelete and KPaste should retain the server-side power check and include the new argument validation.
9. Test normal admin startup, legacy mode if used, delete/copy/paste, and authorized/unauthorized users in a private test place.
10. Save/export the patched model as a new .rbxmx. Keep the original backup until Studio tests pass.

Do not deploy to the live place until the Studio-side patch and behavior tests pass.
