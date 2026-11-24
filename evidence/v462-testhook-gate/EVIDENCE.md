# Test-hook gate: penetration-tested, client cannot enable (build 462)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1` (placeId 120646942844931), Play mode, one local client.
Reads taken from the Server datamodel; the attack was fired from the Client datamodel.

## Why this was tested

`GOAL_2026-11-24.md` L224 requires test-only debug affordances to be gated by Studio or an explicit private allowlist,
with *"no live arbitrary reward/spawn commands."*

`HANDOFF.md` documents six switches, two of which grant state directly:

- `GF_TestHooks` enables `grantTestAugment` and `bossRewardTest`
- `GF_ForceRankUps` forces rank-ups

The audit could not tell from documentation whether a client could set them. Reading the code found the gate is
`workspace:GetAttribute("GF_TestHooks") ~= true`, checked server-side in `ArmoryService`, `CacheService` and
`DispatchService`. **An attribute is not a permission model**, so believing the comment in the code would have been
assuming the thing under test.

## The attack, in order

| Step | Datamodel | Result |
|---|---|---|
| 1. Read the attribute | Client | `GF_TestHooks = nil` |
| 2. `workspace:SetAttribute("GF_TestHooks", true)` | Client | `pcall` returned **true**; client-local value now **true** |
| 3. Read the attribute back | **Server** | **`nil`** — the client write did not replicate |
| 4. `SetLoadout:FireServer({action="grantTestAugment", id="QuickFeed"})` | Client | fired, no error |
| 5. Read the rejection | **Server** | `GF_ArmoryRejected = "test hooks disabled"` |

## Verdict

The gate holds. A client can set the attribute on its own copy of `Workspace`, but attributes set by a LocalScript do not
replicate to the server, and the guard reads the server's copy. The reward action was refused **and recorded a reason**,
which also confirms the fix from `v406` that armory refusals no longer fail silently.

## Two things this does not cover

- **The mechanism is not the one the spec names.** L224 asks for Studio gating or an explicit private allowlist. What
  exists is a server-only workspace attribute. It achieves the required property — unreachable from live play — by
  replication semantics rather than by an allowlist, so a server-side script that sets the attribute *does* enable the
  hooks with no further check.
- **`GF_ForceRankUps` has no guard at all.** `RewardsService:136` reads it directly rather than checking it behind a
  `~= true` refusal, so it depends entirely on the same non-replication property. Not exploited here, not proven unsafe
  either, but it is a weaker construction than its siblings.

## Reproduce

Set `GF_TestHooks` from a Client datamodel, then read `workspace:GetAttribute("GF_TestHooks")` from the Server datamodel.
It reads `nil`. Firing `SetLoadout` with `grantTestAugment` yields `GF_ArmoryRejected = "test hooks disabled"` and leaves
`GF_AugmentBought` unset.
