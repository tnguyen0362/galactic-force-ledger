# Correction: armory refusals *are* reported, with precise reasons (place 515)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`. No source changes; probe removed.

## The claim I made and have to retract

One batch ago I wrote:

> *"`ArmoryService.buy` returns `nil` for **both** success and refusal with no reason string, unlike `equipAugment`'s `(ok, why)`. The armory UI must
> be inferring success from profile state, which is fragile and impossible to assert from the outside."*

**Wrong on the substance.** `buy` does return `nil`, but refusals are reported through a dedicated path:

```lua
local function fail(player, reason)
    workspace:SetAttribute("GF_ArmoryRejected", reason)   -- test-visible
    push(player, { ok = false, reason = reason })         -- client-visible
end
```

Every failure branch calls it, so the reason is published as a workspace attribute **and** pushed to the client. The UI is not inferring anything, and
refusals are entirely assertable from outside — which is why this batch could test them.

I had read `buy`'s body, seen `return fail(...)` with no value, and concluded "no reason is reported" without reading `fail`. Same failure mode as the
other five: reasoning from an unread name.

## Measured refusals

```
SG04 with 10 credits  -> "needs 500 credits"
AR01 (owned)          -> "already owned"
NOPE (unknown id)     -> "unknown weapon"
```

Each names the exact shortfall — 500 credits, not "insufficient funds" — which is better player-facing feedback than a generic refusal.

## What remains genuinely untested

- **Rank gate**: unreachable on this profile, which is rank **15** while the highest weapon requirement is rank **7**. Testing it needs a low-rank
  profile, so `requires rank %d` is code-read only.
- `buyAbility`, `buyGrenade` and `buyArmor` share `fail` but were not individually refusal-tested.
- The **success** path still returns no value; `push(player, { ok = true, ... })` is the success signal. That is a consistent design, not a defect —
  my earlier characterisation of it as fragile was unfair.

## Net effect on the ledger

`S12-010` stays VERIFIED and is now better evidenced: a first purchase charges the exact price, a second charges nothing, and each refusal returns a
precise reason through `GF_ArmoryRejected`. The "silent refusal" defect I recorded does not exist.
