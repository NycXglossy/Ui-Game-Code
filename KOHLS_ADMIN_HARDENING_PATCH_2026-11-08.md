# Kohl's Admin Hardening Patch — 2026-11-08

## Current implementation

The repository contains the original `Kohl's Admin.rbxmx` and a Studio Command Bar patch at `Kohls_Admin_Hardening_Patch.lua`.

The uploaded model's XML source is readable from its Git blob. The patch was corrected to target the model's actual hierarchy:

- `Loader` Script
- `Loader.MainModule` (current v3 package)
- `Loader.MainModule.Shared.DefaultCommands.Creator`
- `Loader.MainModule.Server.LoadScript`
- `Loader.MainModuleLegacy` (optional legacy implementation)

This matters because the v3 MainModule is not the legacy server dispatcher. The legacy RemoteEvent and native command code lives in the sibling `MainModuleLegacy` ModuleScript.

## Security changes in the current patch

1. Removes the Loader's external MainModule asset-fetch and Creator Store fallback.
2. Requires only the bundled local MainModule, fails closed if it is missing, and validates the returned initialization API.
3. Handles missing legacy Config safely and fails closed if legacy mode is selected without its required configuration.
4. Adds a per-player operation allowlist and cooldowns for the legacy admin RemoteEvent. The KuID handshake is separately constrained; non-handshake operations must carry the expected internal ID.
5. Adds a central minimum-power policy for sensitive legacy remote operations: KDelete, KPaste, and KUpdate require Kohl's Admin power 5 or higher. Existing handler-level checks remain.
6. Limits legacy command-bar remote payloads to 512 characters; command execution continues through Kohl's Admin's command dispatcher and its command permission checks.
7. Restricts KDelete and KPaste to Workspace descendants; rejects script/module deletion targets and invalid source/destination relationships.
8. Validates KPaste as a dense list, caps batches at 25 Instances and 500 combined descendants, validates every source before mutation, and stages clones before parenting them.
9. Removes the legacy native `script`/loadstring command entirely.
10. Removes the v3 Creator `script` and `localscript` command registrations.
11. Replaces the v3 `Server.LoadScript` backend with a fail-closed function, disabling the bundled FiOne/loadstring execution path even if another bundled command or add-on tries to call it.
12. Validates KCam CFrame components as finite numbers and bounds position coordinates to ±100,000 studs.
13. Computes all modified source strings before writing and applies four Source writes transactionally, rolling back earlier writes if a later write fails.

## Arbitrary-code execution decision

The bundled Kohl's Admin arbitrary-source execution features are intentionally disabled. This is a deliberate security trade-off: the built-in `script` and `localscript` commands are not retained because a Creator-only permission check is not a sandbox. Reviewed, bundled ModuleScripts should be used for supported extensions instead.

This patch cannot prevent a separate custom add-on, third-party package, or another server script from independently implementing dynamic code execution. Review custom add-ons and other installed packages separately.

## Important boundaries

- The patch is a Studio-side source transformation. It has been checked against the uploaded XML source anchors, but it has **not** been executed in Roblox Studio and has not been exported into a replacement `.rbxmx`.
- The original model file in the repository remains unchanged.
- The legacy RemoteEvent receives stronger per-operation controls, but the complete behavior of every dynamically registered listener and every third-party add-on has not been exhaustively tested. KHA-06 therefore remains partially open pending runtime verification.
- Workspace-only delete/paste checks are intentionally narrower than general DataModel membership and may affect workflows that edited objects outside Workspace. Verify expected Kohl's Admin building/copy workflows in Studio.
- No Roblox Studio execution, multiplayer exploit test, or live production test has been performed.
- This is targeted hardening, not certification that the entire admin package or place is safe.

## Apply and verify

1. Back up the place and imported model.
2. Import the current `Kohl's Admin.rbxmx` into Roblox Studio.
3. Select the Kohl's Admin root model/folder in Explorer.
4. Open View → Command Bar and run the complete current contents of `Kohls_Admin_Hardening_Patch.lua` from this branch.
5. Confirm the Output reports that Creator script/localscript commands and the legacy native script command are removed, the FiOne/loadstring backend is disabled, and the legacy remote controls are installed.
6. Inspect the Loader: it should contain no InsertService, LoadAsset, or external MainModule asset ID fallback.
7. Inspect `MainModule.Shared.DefaultCommands.Creator`: no `script` or `localscript` command entries should remain.
8. Inspect `MainModule.Server.LoadScript`: it should fail closed and must not require FiOne or compile/execute supplied source.
9. Inspect `MainModuleLegacy` if legacy mode is retained: its native script command should be absent; KDelete/KPaste should enforce Workspace scope and bounded/staged paste; ServerEvent should enforce its operation allowlist, ID, cooldown, and minimum-power policy.
10. Test startup, normal moderation/admin commands, command bar, delete/copy/paste, camera wind direction, legacy mode if used, and each privilege tier in a private test place.
11. Confirm that custom add-ons do not depend on `_K.LoadScript`; any such dependency should fail closed until replaced with reviewed code.
12. Save/export the patched model as a new `.rbxmx`. Keep the original backup until Studio tests pass.

Do not deploy to the live place until the Studio-side patch and behavior tests pass.
