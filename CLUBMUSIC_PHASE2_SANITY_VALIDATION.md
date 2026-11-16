# Phase 2 — Server Authority & Sanity Validation Standard

## Goal

Make server-side sanity validation a reusable requirement for privileged and gameplay-sensitive operations. This phase validates inputs and live references before the existing server authorization and execution paths continue. It does not grant permissions, replace domain-specific rules, or make client-side checks authoritative.

## Added shared component

`ClubMusicSecurityCore/SanityValidation.lua` provides:

- finite-number and bounded-integer checks;
- bounded-string checks;
- live Player-instance validation against the current Players service;
- finite, world-bounded Vector3 validation;
- finite, world-bounded CFrame validation;
- bounded data-tree validation (depth, entry count, string size, key types, cycles and unsupported values);
- dense, bounded player-target list validation with stale-reference and duplicate rejection.

The component is a validator, not an authorization authority. Each caller must still check actor permissions, entitlements, consent, game state, cooldowns and domain-specific constraints.

## First integrations

### TeleportValidationService

The teleport service now uses the shared finite-number, Vector3 and live-Player validators. It retains its existing short-lived, single-use ticket, participant binding, character/root identity and post-move position verification.

### Kohl's Admin regular-command adapter

The regular-command adapter now requires the shared validator. If it is unavailable, privileged regular-command filtering does not install.

Before a policy-protected command reaches its handler, the adapter validates:
- a live player actor;
- each configured target argument as a live Player or a dense bounded list of live Players;
- no duplicate targets and no more than eight targets per argument;
- finite numeric command values and existing per-property limits.

Invalid targets are denied before the command handler executes and a throttled security signal is reported. Existing permission checks and rate budgets remain in force.

This is not yet full Kohl's teleport ticket integration. The external command handler's exact bring/tp/to destination semantics are not in this repository snapshot. Those commands still need a verified pre-execution destination capture and post-execution ticket confirmation before being marked fully integrated.

## Installer

The Security Core installer now includes `SanityValidation` before `TeleportValidationService` and pins its download source to the commit containing both modules. The installer has not been executed.

## Required next integrations

- Apply the shared data-tree and field validators at the main UI remote ingress and any other exposed server remotes, without breaking existing action-specific contracts.
- Apply the standard to purchases, VIP/zone access, avatar/accessory, audio/animation, chat and social actions.
- Audit each state mutation for authorization immediately before execution, including after any yielding operation.
- Continue Kohl's bring/tp/to integration only after the actual command implementation and argument/destination semantics are verified.

## Safety and test requirements

- Malformed payloads, non-finite values, out-of-range values, stale Player references, duplicate targets, sparse arrays, cyclic tables and oversized payloads must be rejected before mutation.
- Valid commands and existing owner/co-owner/moderator hierarchy must continue to work.
- Legitimate Utility Bar movement, approved staff actions, respawns, vehicles and knockback must not be misclassified.
- Rejection does not automatically mean exploit intent; record evidence and correlate before moderation.
- No automatic kick/ban is enabled by this phase.
- No Studio or published-server runtime tests have been performed.
