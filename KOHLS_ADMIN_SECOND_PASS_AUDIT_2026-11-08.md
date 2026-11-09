# Kohl's Admin Second-Pass Security Audit — 2026-11-08

## Executive result

**Status: PARTIAL PASS — patch logic reviewed; model-wide audit and runtime verification remain blocked.**

This second pass reviewed the current `Kohls_Admin_Hardening_Patch.lua` and `KOHLS_ADMIN_HARDENING_PATCH_2026-11-08.md` on branch `audit/kohls-admin-hardening-2026-11-08`. The original `Kohl's Admin.rbxmx` is present in the branch, but the GitHub file connector returned an empty body for that binary model in both UTF-8 and base64 modes. Therefore, this pass could not independently inspect the model's embedded source, verify the reported 344 source-bearing items, or confirm that the patch's literal source anchors match the exact current model revision.

No Roblox Studio execution, multiplayer testing, or live-place testing was performed. This report does not certify the model as safe.

## Findings

### KHA-01 — High: arbitrary-code execution remains available to Creator-level accounts

The patch raises the legacy native `script` command from power 5 to power 6, but it does not remove that capability. The Creator addon also retains `script` and `localscript` commands using the custom Loadstring/FiOne execution path, as documented in the existing hardening report.

**Impact:** An account granted Creator-level Kohl's Admin access may be able to execute arbitrary server/client code. A compromised or improperly trusted Creator account can therefore cause broad game compromise.

**Recommendation:** Disable both execution paths unless operationally essential. If retained, restrict Creator access to a very small trusted set, audit every command registration and permission check, and test the exact execution context. Treat this as a privileged capability, not a sandbox.

### KHA-02 — High: the uploaded model is not yet a verified patched artifact

The current branch documentation states that the original model is unchanged and that the patch is a Studio-side source transformation that has not been executed or exported into a replacement `.rbxmx`.

**Impact:** The presence of the patch script in GitHub does not mean the live/imported Kohl's Admin model is hardened. Deploying the original model without successfully applying and verifying the patch leaves the original attack surface in place.

**Recommendation:** Apply only to a backup in Studio, inspect the resulting Loader and MainModule source, export a new model, and retain the original backup. Do not deploy until the verification checklist passes.

### KHA-03 — Medium: patch application is not atomic

The patch assigns `loader.Source = loaderSource` before it performs all MainModule replacements. The later MainModule replacements use fail-fast assertions. If one of those assertions fails, the script can stop after changing the Loader but before changing the MainModule.

**Impact:** A failed patch run can leave a partially modified model with the loader hardened but the server module still carrying old behavior.

**Recommendation:** Compute and validate every replacement in memory first. Only after all Loader and MainModule assertions succeed should the script assign either `.Source`. Ideally retain original source strings and restore them if any assignment fails.

### KHA-04 — Medium: paste throughput is high for a destructive operation

The patch sets `KDelete = 0.025` (up to 40 events/second per player) and `KPaste = 0.2` (up to 5 events/second). Each accepted paste may clone as many as 100 Instances.

**Impact:** A single authorized account can request a theoretical burst of up to 500 cloned Instances per second, before accounting for clone cost, replication, and downstream scripts. The cooldown is per player and per operation, not a server-wide budget.

**Recommendation:** Use a much smaller per-batch cap, a token-bucket budget that accounts for the number/complexity of Instances, and a server-wide aggregate limit. Add maximum descendant/serialized-size constraints where practical.

### KHA-05 — Medium: delete/paste target validation is broad

The patch confirms that KDelete targets and KPaste sources/destinations are live Instances descended from `game`. This is stronger than accepting arbitrary client payloads, and the existing `f.getPower(plr) > 4` check remains. However, DataModel membership alone does not restrict operations to safe editable containers.

**Impact:** A sufficiently privileged account can target high-impact Instances or paste into sensitive parts of the DataModel if those targets are reachable through the command's UI/protocol.

**Recommendation:** Add explicit target and destination policy checks. Reject service roots, the admin package itself, security-critical scripts/modules, and other protected containers unless a specific supported admin workflow requires them.

### KHA-06 — Medium: event allowlisting and cooldowns do not prove per-command authorization

The patch adds an allowlist and per-player cooldown table for legacy RemoteEvent operation names. It does not add a complete per-operation permission matrix or comprehensive argument validation for every operation. The patch documentation itself notes that the cooldowns are not a substitute for authorization checks in each handler and that dynamically registered listeners still need behavior testing.

**Impact:** A rate-limited event can still be dangerous if its existing handler has an authorization gap or accepts an unsafe payload. A name allowlist limits the event surface; it does not establish that each operation is safe for the caller.

**Recommendation:** Review every allowlisted operation and every dynamically registered listener. For each one, document the required Kohl's Admin power, validate argument types/ranges/ownership server-side, and test calls from ordinary players, moderators, owners, and Creator-level accounts.

### KHA-07 — Low: KCam checks the CFrame type but not its numeric components

The patch checks `typeof(b) == "CFrame"` before reading `LookVector`. This prevents a wrong-type payload from reaching that code, but does not explicitly check that the resulting components are finite and within expected bounds.

**Impact:** A malformed or extreme CFrame may still produce unexpected camera behavior if such values are accepted by the remote serialization path.

**Recommendation:** Validate all position and orientation components as finite numbers and enforce reasonable world-coordinate bounds before using the value.

## Confirmed positive changes in the patch source

- Removes the Loader's external MainModule asset-fetch/Creator Store fallback and requires the bundled local ModuleScript.
- Fails closed when the bundled MainModule is missing or returns an invalid initialization API.
- Handles missing legacy Config safely and rejects legacy mode when its required configuration is absent.
- Retains the existing power check for KDelete/KPaste and adds Instance/payload checks.
- Adds a 100-Instance paste batch cap.
- Adds per-player/per-operation cooldowns and an operation-name allowlist for the legacy admin RemoteEvent.
- Raises the legacy native script command's required power to 6.
- Checks the KCam response type before accessing CFrame data.

## Verification matrix

| Area | Second-pass result |
|---|---|
| Patch source reviewed | Pass |
| Loader external fallback removal present in patch | Pass |
| KDelete/KPaste input checks present in patch | Pass |
| RemoteEvent allowlist/cooldowns present in patch | Pass |
| Dynamic code execution eliminated | Fail — remains Creator-scoped |
| Patch application atomicity | Fail — Loader is assigned before MainModule checks finish |
| Full embedded model source audit | Not verified — binary model body unavailable to this pass |
| All 344 source-bearing items reviewed | Not verified |
| Per-command authorization across all listeners | Not verified |
| Roblox Studio / multiplayer / live testing | Not performed |
| Patched replacement model exported | Not verified |

## Required next actions before deployment

1. Make the patch atomic so no source is assigned until all replacements have passed validation.
2. Decide whether Creator `script`/`localscript` execution is genuinely required; disable it if not.
3. Reduce paste batch size and add cost-based plus server-wide throttling.
4. Add protected-container rules for delete/paste.
5. Audit every RemoteEvent operation and dynamic listener for explicit authorization and argument validation.
6. Provide an XML/text export or extracted source files for the model so the full embedded source audit can be completed.
7. Apply the corrected patch to a backup in Studio, test all documented workflows and privilege tiers, then export a new `.rbxmx`.

**Deployment recommendation: Do not treat this model as fully hardened or production-ready yet.**


## Patch correction follow-up — 2026-11-08

The patch source was subsequently revised on this audit branch to address the directly actionable findings:

- **KHA-03:** all source-string replacements are now prepared and asserted before either Script.Source property is assigned. The MainModule write is rolled back if the Loader write fails.
- **KHA-04:** KDelete is throttled to 10 requests/second and KPaste to 1 request/second per player; paste batches are capped at 25 Instances and 500 combined descendants.
- **KHA-05:** delete/paste targets are narrowed to Workspace descendants; paste validates a dense list, rejects invalid/self-descendant targets, and stages clones before parenting. This narrower scope may affect workflows that edited outside Workspace and must be tested.
- **KHA-07:** KCam now rejects non-CFrame, non-finite component values, and position coordinates outside ±100,000 studs.

The revised patch is stored at `Kohls_Admin_Hardening_Patch.lua` on this branch. These are source-level corrections only. **KHA-01** (Creator-scoped arbitrary-code execution) and **KHA-06** (full per-command authorization review) remain open; full model inspection and Studio/multiplayer testing remain outstanding. The corrected patch has not been executed against the model.
