# Phase 32 — Account Risk, Ban-Evasion Signals & Moderation Enforcement

**Branch:** `fix/security-core-release-and-queue-loop`  
**Status:** Source modules added; runtime wiring, installation, and Roblox Studio acceptance remain required.  
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

All three are ModuleScripts intended for `ServerStorage.ClubMusicSecurityCore`. They are not client remotes and must not be required from a LocalScript.

## Account-risk signals

- `Player.AccountAge` under 14 days contributes only a small advisory signal (10 points, low confidence). It does not automatically reject or restrict the player.
- MembershipType is deliberately excluded; it is not identity verification.
- Verified moderation history is supplied through an injected, authorized history provider. Only records marked `verified = true` and within the rolling 30-day window contribute.
- The service caps its score at 100 and returns the source signal metadata. A score is for staff triage only.
- Cross-account linkage remains unavailable unless Roblox exposes a specific authorized platform signal to this experience. No indirect matching is implemented.

## Punishment policy

Supported actions:
- `Warn`: records a formal warning and gives an online player a notice via disconnect; warning is retained in history.
- `Restrict`: records a named feature restriction; the consuming feature must check `IsRestricted(userId, key)` before granting access.
- `TempBan`: uses Roblox `Players:BanAsync()` for 60 seconds through 365 days.
- `PermanentBan`: uses Roblox `Players:BanAsync()` with `Duration = -1`.
- `Unban`: uses `Players:UnbanAsync()`, retains reversal history, and never deletes the original case.

Every action requires a live staff Player, bounded reason, and SecurityCore `GlobalModeration` authorization. Persistent evidence is written before enforcement. If persistence fails, no punishment is applied. If Roblox banning is disabled or `BanAsync` fails, the pending case is removed from active sanctions and a failure record is retained where storage permits.

### Suspected alternate-account propagation

- Default is `ExcludeAltAccounts = true`: no native alt propagation.
- Propagation can only be requested for a permanent ban.
- The actor must have both `GlobalModeration` and `IncidentResponse`, and explicitly set `confirmAltPropagation = true`.
- This is an additional senior-staff confirmation. The platform determines suspected alternate accounts; this experience does not receive or persist a list of linked accounts.
- A possible association is not proof of shared identity. Any separate enforcement against another account requires independent authorization and evidence.
- Roblox's `BanAsync` documentation states that `ExcludeAltAccounts = false` permits platform propagation to suspected alternate accounts. It does not guarantee that every alternate account will be detected.

## Chat filtering and strikes

- `FilterBroadcast(player, rawText)` enforces a 120-byte / 120-codepoint bound and a 1.25-second per-player submission interval.
- It uses `TextService:FilterStringAsync()` and `TextFilterResult:GetNonChatStringForBroadcastAsync()`.
- If filtering fails, no raw or partially filtered text is returned for display.
- Hash-heavy output is not a strike. Roblox filtering may legitimately replace content with `#`; the previous hash-ratio heuristic is removed.
- `RecordVerifiedViolation` is a trusted server-to-server hook only. It must be called only after a distinct, independently verified rule violation and should write through the moderation evidence service. It is not exposed to clients.
- Repeated filter-service outages are operational errors, not player violations.

## Storage and access

- DataStore key: `TikiTideModeration_v1` (configurable at construction).
- Per-account active sanctions are keyed by case ID. History is pruned to the latest 50 entries and 180 days.
- Service callers must enforce SecurityCore authorization before querying `GetActive` or `GetHistory`; do not expose these methods through an unguarded RemoteFunction.
- The module injects the existing Authorization service and checks `GlobalModeration` for issuing/reversing punishments. Permanent-ban alt propagation additionally checks `IncidentResponse`.
- Audit events are emitted through an injected server-only callback. Do not include raw chat or unnecessary personal information in audit details.
- DataStore errors fail closed for punishment writes, history reads, and reversals.

## Integration requirements before release

1. Install the three ModuleScripts under `ServerStorage.ClubMusicSecurityCore`.
2. Construct the existing Authorization service using `Authorization.GetShared()`; inject that same instance into `ModerationPunishmentService.new({ authorization = authorization, onAudit = ... })`.
3. Provide a server-only authorized history adapter to `AccountRiskSignalService.new({ getAuthorizedHistory = ... })`. The adapter must return only verified moderation records and must enforce `IncidentResponse` for staff-facing queries.
4. Route existing custom broadcast text entry points through `ChatAbuseDetectionService:FilterBroadcast`; only the returned filtered text may be displayed. Do not create a parallel chat system or duplicate default Roblox chat filtering.
5. Before any restricted feature is used, call `IsRestricted` server-side. Fail closed when the restriction store is unavailable.
6. Add staff-only, server-authorized commands or UI actions for warning, restriction, temp ban, permanent ban, history, and unban. Do not add a client-controlled risk score or direct ban remote.
7. Publish the experience rules and an appeal route accessible to players. Roblox's BanAsync guidance expects creators to explain rules and provide a way to appeal.
8. Configure `Players.BanningEnabled = true` in Studio's Players properties; this property is not scriptable.
9. Reconcile existing Kohl's Admin native `ban/unban/kick` commands so they cannot bypass the intended evidence and permission policy. Do not silently remove existing commands without checking their consumers and role configuration.
10. Add DataStore outage, cross-server ban, temporary expiry, unban, restriction enforcement, permission, and appeal tests.

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

The repository source modules and this phase document are committed to the feature branch. This does not certify that they are installed, wired into the live controller, tested in Studio, or active in the published experience. Do not describe Phase 32 as runtime-certified until the acceptance matrix passes.
