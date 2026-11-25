# The place-539 crash is now guarded — and the guard was proven to fail (place 542)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 542**.

## Why this batch

Last batch shipped a fatal regression: a throw inside `State`'s defaults table made `State.create` fail for **every player**, and the only symptom was
`no state` wherever something read it. The suite stayed green throughout, because nothing tested state construction. That is the gap this batch closes.

## Change

`State.ensure` built its table inline, which is untestable without a `Player`. The literal is now `State.buildDefaults()`, and `ensure` calls it:

```lua
function State.buildDefaults(): PlayerState
    -- Extracted from ensure() so state CONSTRUCTION can be tested without a Player. A throw in here is
    -- fatal and silent: it made State.create fail for every player at place 539...
    local Constants = require(game:GetService("ReplicatedStorage").GF.Shared.Constants)
    return { ... }
end
```

Three checks added to `DamageChecks` (inside `CheckRunner.run()`):

1. `buildDefaults()` constructs without error.
2. The returned table carries **numeric** `ammo` and `reserve`.
3. `reserve > 0` — i.e. the catalogue seeding is real, not a literal 0.

## Proven in both directions

Healthy:

```
buildDefaults ok=true reserve=168 | passed=660 failed=17 nonDrift=0
```

Then I **reintroduced the bug on purpose** (`local _ = NotAThing.GF` at the top of `buildDefaults`):

```
buildDefaults ok=false err=State:45: attempt to index nil with 'GF'
passed=657 failed=18 nonDrift=1
state defaults construct without error: State:45: attempt to index nil with 'GF'
```

The guard fails, names the exact error, and pushes `nonDrift` from 0 to 1 — so it is a real tripwire rather than decoration. The injection was then removed and
the suite returned to `passed=660 failed=17 nonDrift=0`, with zero `NotAThing` references left.

## Why "prove the test fails" matters here

Every previous batch in this session verified that things *work*. None verified that a check would *catch* the failure it exists for. A guard that has only ever
been seen green is an assumption; this one has been seen red.

## Limits

- The guard covers **construction**, not the runtime consequences. It would not catch a state field that is present but wrong in a way the checks do not
  anticipate (e.g. reserve seeded from the wrong weapon).
- It runs on `CheckRunner.run()`, not at server start, so a broken build still boots; the failure appears when the suite is run.
- The three checks assert types and `reserve > 0`, not every field — `shield`, `weapons`, `cooldowns` and the rest are unasserted.
