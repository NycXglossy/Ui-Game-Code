# Phase 32 — Account Risk, Ban-Evasion Signals & Moderation Enforcement

**Branch:** `fix/security-core-release-and-queue-loop`  
**Status:** Source modules, controller composition, staff-command bridge, request/custom-title restriction checks, and native-ban command guard are committed. Installation in Studio and runtime acceptance remain required.  
**Security authority:** Existing `ClubMusicSecurityCore/Authorization.lua` remains the sole role and permission authority.

## Goals and non-negotiable privacy limits

- Derive repeat-abuse signals only from platform-provided account attributes and authorized, verified moderation records.
- Use Roblox `Player.UserId` as the account identifier. Do not collect IP addresses, device IDs, browser identifiers, hardware IDs, fingerprints, behavioral biometrics, or external identity enrichment.
- Do not infer sensitive traits or claim that two accounts belong to the same person.
- Account linkage is an investigation clue, not proof of shared identity and never an automatic punishment trigger.
- Do not create a home-grown alternate-account detector. The only cross-account propagation in this phase is Roblox's native `Players:BanAsync()` option, which is platform-managed and described as suspected alternate-account propagation.
- Evidence is access-controlled, bounded to 50 history entries per account, and retained for at most 180 days by the service's rolling history cleanup.
- No risk score can issue a warning, restriction, kick, ban, or alt-account sanction by itself.

## Added source modules

| Module | Responsibility |
|---|---|
| `AccountRiskSignalService.lua` | Advisory score from low-confidence account age and verified recent moderation history; no identity inference or enforcement |
| `ModerationPunishmentService.lua` | Persistent warnings, feature restrictions, temporary/permanent Roblox bans, reversals, bounded evidence history |
| `ChatAbuseDetectionService.lua` | Server-side TextService filtering, bounded input, per-player rate limit, fail-closed output, trusted verified-violation callback |
| `Phase32ServiceBundle.lua` | Composes the three services with the existing shared SecurityCore Authorization instance |

All four are ModuleScripts intended for `ServerStorage.ClubMusicSecurityCore`. They are not client remotes and must not be required from a LocalScript.

## Account-risk signals

- `Player.AccountAge` under 14 days contributes only a small advisory signal (10 points, low confidence). It does not automatically reject or restrict the player.
- MembershipType is deliberately excluded; it is not identity verification.
- Verified moderation history is supplied through an injected, authorized history provider. Only records marked `verified = true` and within the rolling 30-day window contribute.
- The service caps its score at 100 and returns the source signal metadata. A score is for staff triage only.
- The experience currently has no authorized Roblox account-linkage feed to inspect. Cross-account linkage remains unavailable unless Roblox exposes a specific authorized platform signal. No indirect matching is implemented.

## Punishment policy

Supported actions:
- `Warn`: records a formal warning and sends an online player a notice; it does not kick the player.
- `Restrict`: records a named feature restriction; the consuming feature must check `IsRestricted(userId, key)` before granting access.
- `TempBan`: uses Roblox `Players:BanAsync()` for 60 seconds through 365 days.
- `PermanentBan`: uses Roblox `Players:BanAsync()` with `Duration = -1`.
- `Unban`: uses `Players:UnbanAsync()`, retains reversal history, and never deletes the original case.
- `RevokeRestrictions`: removes all active feature restrictions for an account and records the reversal.

Every action requires a live staff Player, bounded reason, and SecurityCore `GlobalModeration` authorization. Persistent evidence is written before enforcement. If persistence fails, no punishment is applied. If Roblox banning is disabled or `BanAsync` fails, the pending case is removed from active sanctions and a failure record is retained where storage permits.

### Suspected alternate-account propagation

- Default is `ExcludeAltAccounts = true`: no native alt propagation.
- Propagation can only be requested for a permanent ban.
- The actor must have both `GlobalModeration` and `IncidentResponse`, and explicitly set `confirmAltPropagation = true`.
- This is an explicit, manual senior-staff enforcement choice after case review; it is never triggered by the risk score or by an inferred relationship. The platform determines suspected alternate accounts; this experience does not receive or persist a list of linked accounts.
- A possible association is not proof of shared identity. Any separate enforcement against another account requires independent authorization and evidence.
- Roblox's `BanAsync` documentation states that `ExcludeAltAccounts = false` permits platform propagation to suspected alternate accounts. It does not guarantee that every alternate account will be detected.

## Chat filtering and strikes

- `FilterBroadcast(player, rawText)` enforces a 120-byte / 120-codepoint bound and a 1.25-second per-player submission interval.
- It uses `TextService:FilterStringAsync()` and `TextFilterResult:GetNonChatStringForBroadcastAsync()`.
- If filtering fails, no raw or partially filtered text is returned for display.
- Hash-heavy output is not a strike. Roblox filtering may legitimately replace content with `#`; the previous hash-ratio heuristic and its automatic three-strike kick are removed. Repeated independently verified violations can raise the advisory risk score and be reviewed for graduated staff-issued punishment.
- `RecordVerifiedViolation` is a trusted server-to-server hook only. It must be called only after a distinct, independently verified rule violation and should write through the moderation evidence service. It is not exposed to clients.
- Repeated filter-service outages are operational errors, not player violations.

## Storage and access

- DataStore key: `TikiTideModeration_v1` (configurable at construction).
- Per-account active sanctions are keyed by case ID. History is pruned to the latest 50 entries and 180 days, including cleanup on reads.
- Only minimal active-sanction metadata remains while a restriction or permanent ban is active; detailed reasons remain in the bounded history. Expired temporary sanctions are removed during cleanup.
- `GetHistory` checks `GlobalModeration` internally. `GetActive` is a server-only feature-enforcement helper and must never be exposed through a client RemoteFunction.
- The module injects the existing Authorization service and checks `GlobalModeration` for issuing/reversing punishments. Permanent-ban alt propagation additionally checks `IncidentResponse`.
- Audit events are emitted through an injected server-only callback. Do not include raw chat or unnecessary personal information in audit details.
- DataStore errors fail closed for punishment writes, history reads, and reversals.

## Source integration completed

The feature branch now includes source-level wiring:

- `UI_Server_Controller_server (1).lua` loads `Phase32ServiceBundle` only when the existing `ClubMusicSecurityCore.Authorization` service is available. It uses the already initialized shared authorization instance; no second role authority is created.
- The controller exposes Phase 32 actions only through the existing server-only `ClubMusicAdminBridge`. No client ban remote or client-supplied risk score is created.
- `KohlsAdmin_ClubMusic_Addon.lua` registers `;cmwarn`, `;cmrestrict`, `;cmtempban`, `;cmpermban`, `;cmpermban-alts`, `;cmunban`, `;cmunrestrict`, `;cmpunishmenthistory`, and `;cmrisk`.
- The controller enforces `MusicRequests` and `CustomText` restrictions server-side. Restriction reads use a five-second per-account cache; a failed/expired cache lookup fails closed for those features.
- Existing custom title filtering uses `ChatAbuseDetectionService:FilterBroadcast`; no raw text is displayed if filtering fails.
- `RegularCommandsSecurityServer.lua` blocks Kohl's native `ban` and `unban` commands so they cannot bypass Phase 32 evidence and reversal handling. The existing `kick` action remains separately permissioned/audited and is not a persistent ban.

## Remaining installation and release requirements

1. Install all four Phase 32 ModuleScripts under `ServerStorage.ClubMusicSecurityCore`: `ModerationPunishmentService`, `AccountRiskSignalService`, `ChatAbuseDetectionService`, and `Phase32ServiceBundle`.
2. Ensure the updated controller and Kohl's Admin addon/security adapter sources are the versions installed in Studio. Do not install a stale copy of any of these files.
3. Route any other custom broadcast-text inputs (for example future custom chat/announcement inputs) through `FilterBroadcast`; this phase does not replace Roblox's default chat filtering.
4. Before each additional restricted feature is used, wire a server-side `IsRestricted` check. `MusicRequests` and `CustomText` are already wired; `Chat`, `DJFeatures`, `Announcements`, and `Trading` require checks in their respective feature owners before those restrictions are advertised as active.
5. Publish the experience rules and an appeal route accessible to players. Roblox's BanAsync guidance expects creators to explain rules and provide a way to appeal.
6. Configure `Players.BanningEnabled = true` in Studio's Players properties; this property is not scriptable.
7. Add DataStore outage, cross-server ban, temporary expiry, unban, restriction enforcement, permission, and appeal tests in Studio and a published test universe.

## Staff command reference

- `;cmwarn <UserId> <reason>` — persistent formal warning and player notice.
- `;cmrestrict <UserId> <Feature[,Feature]> <reason>` — supported keys: `Chat`, `MusicRequests`, `CustomText`, `DJFeatures`, `Announcements`, `Trading`.
- `;cmtempban <UserId> <Seconds> <reason>` — 60 seconds through 365 days.
- `;cmpermban <UserId> <reason>` — permanent universe ban; no alt propagation.
- `;cmpermban-alts <UserId> <reason>` — permanent ban with Roblox suspected-alt propagation; requires `IncidentResponse` in addition to `GlobalModeration`.
- `;cmunban <UserId> <reason>` — reverse an active native ban.
- `;cmunrestrict <UserId> <reason>` — remove all active feature restrictions.
- `;cmunrestrict <UserId> <reason>` — reverse all active feature restrictions.
- `;cmpunishmenthistory <UserId>` — bounded history; requires `GlobalModeration`.
- `;cmrisk <UserId>` — advisory risk review; requires `IncidentResponse`.

## Acceptance matrix

| Test | Required result |
|---|---|
| New account | Low-confidence review signal only; no automatic kick |
| Membership type | Not used as identity or trust proof |
| Repeat verified violations | Bounded score and evidence references |
| Unverified / client-supplied history | Ignored |
| Suspected alt propagation | Senior confirmation required; Roblox handles matching |
| Account association | Never treated as proof or automatic punishment |
| Ban / unban | Native API success and evidence state reconciled |
| DataStore write failure | No new punishment claimed or applied |
| Ban API disabled / failure | No false success |
| Restriction | Each protected server feature checks active restriction |
| Chat filtering failure | No unfiltered text displayed |
| Hash-heavy filtered output | No strike based solely on hashes |
| Unauthorized lookup/action | Denied and audited |
| Retention | Old evidence pruned; maximum history 50 |
| Two-server test | Roblox native bans apply across universe; feature restrictions read shared persistent state |
| Published-place audit | Installed modules, remotes, Kohl's commands and actual consumers reconciled |

## Roblox API references

- Players / BanAsync / UnbanAsync / BanningEnabled: https://create.roblox.com/docs/reference/engine/classes/Players
- TextService:FilterStringAsync: https://create.roblox.com/docs/reference/engine/classes/TextService/FilterStringAsync
- TextFilterResult:GetNonChatStringForBroadcastAsync: https://create.roblox.com/docs/reference/engine/classes/TextFilterResult

## Certification boundary

The four source modules and source-level controller/Kohl's integration are committed to the feature branch. This does not certify that the modules are installed in the live place, that Roblox BanAsync/DataStore behavior works in Studio, or that the updated sources are active in the published experience. No Studio runtime or published two-server test was performed. Do not describe Phase 32 as runtime-certified until the acceptance matrix passes.
