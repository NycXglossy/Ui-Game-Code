# Kohl's Admin Hardening Patch — 2026-11-08

## Scope applied by the Studio patch

This repository contains a reviewed patch script at `Kohls_Admin_Hardening_Patch.lua`. It is intended to be run from Roblox Studio's Command Bar with the imported Kohl's Admin root selected.

The patch:
1. Disables the loader's automatic external MainModule fetch and fallback to Creator Store asset IDs.
2. Requires the bundled local `Loader.MainModule` only, fails closed if it is missing, and validates the returned `initialize` API before calling it.
3. Validates `KDelete` payloads as live Instances before destroying them.
4. Validates `KPaste` payload shape, destination, move flag, every source Instance, and caps each paste batch at 100 before mutating anything.
5. Repairs the packaged Explorer `GetSelection` LocalScript: wraps its `iconMap` string in an array before passing it to `ContentProvider:PreloadAsync`, which requires a list.

## Important boundaries

- The original `Kohl's Admin.rbxmx` model file is retained unchanged in this commit. The connector rejected the 7.4 MB replacement payload, so the patch is supplied as an executable Studio patch rather than falsely marking the model asset itself as rewritten.
- Run the patch against the imported model in Studio, then save/export the patched model and replace the original upload in your project.
- The existing admin permission hierarchy remains separate from ClubMusic. No Kohl's Admin role grants ClubMusic DJ, moderation, or staff permissions.
- The dynamic `script` / `localscript` command capability is not silently removed because doing so may break intended administrator workflows. It remains a high-impact capability restricted by the existing high-power command permission. Disable those commands if arbitrary code execution is not a required feature.
- The earlier static audit was targeted, not a complete audit of all embedded scripts. This patch does not certify every embedded command/tool as safe.
- The separate F3X Building Tools error at `Player:WaitForChild('PlayerGui')` is not changed by this patch. `Players.LocalPlayer` is nil when that Core module is required from server context; the correct repair is to ensure the Core is required by its client `PluginInitializer` LocalScript, not to add a nil fallback. The exact live caller producing the `Server - Core:493` log must be verified in Studio before changing the F3X loader.
- No Roblox Studio execution, multiplayer exploit test, or live production test has been performed.

## Apply

1. Import the Kohl's Admin model into Roblox Studio.
2. Select the Kohl's Admin root model/folder in Explorer.
3. Open View → Command Bar.
4. Paste the complete contents of `Kohls_Admin_Hardening_Patch.lua` and run it.
5. Confirm the Output reports the hardening edits and the Explorer `PreloadAsync` fix.
6. Save/export the model as a new `.rbxmx` backup.
7. Re-open the saved model and verify the Loader uses the bundled MainModule and no longer contains external auto-update loading.
