# RNG uses `math.random`; dome duration is 20s against an authored 10s (place 504)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level inspection. No place changes.

## `S11-030` — randomness is not cryptographically appropriate

The spec asks for *"server cryptographically appropriate platform-supported unpredictable randomness for outcomes"*.

`CacheService` resolves every outcome through:

```lua
local function defaultRng() return math.random() end
local picker = rng or defaultRng
```

`math.random()` is Luau's process PRNG seeded internally — predictable given enough observations, and identical in kind across servers
rather than per-request unpredictable. This is the weakest option available on the platform; `Random.new()` with clock-derived entropy
would at least be per-session distinct.

One thing the build does well: **the picker is injectable** (`CacheService.roll(tier, owned, rng)`), so tests can supply a deterministic
function. That is good practice for reproducibility and is what let this audit reason about odds without gambling on them — but it does not
make the production path unpredictable.

## `S11-043` — dome duration is double the guaranteed value

The spec is unusually blunt:

> *"Dome duration remains guaranteed 10s (do not alter with Augments); shield radius eligible."*

`Configs/Abilities`: `DomeShield duration = 20, radius = 18`.

So the dome lasts **20 s against a guaranteed 10 s**, and the spec's instruction that augments must not alter duration cannot be violated
because nothing alters it — but the base value is already wrong by 2×.

The second half of the clause is also unmet in the other direction: *"shield radius eligible"* means augments **may** change the dome
radius, and nothing does. `blastRadius` acts only in `CombatService.detonate`, so a dome's 18-stud radius is fixed regardless of augments.

## What this means for feel

A 20-second dome on a 70-second cooldown is a 29% uptime defensive bubble, where the authored intent is 14%. Combined with the radius being
fixed rather than augment-scalable, the dome is both stronger and less customisable than specified.

## Not changed

Duration is a survivability lever — halving it changes how the Dome Shield ability plays and interacts with the sentry/barrier economy. Same
owner queue, and it should be decided alongside the ability cooldown drifts already recorded (`OrbitalStrike`, `OrbitalLance`,
`ReflectiveBarrier`, `Sentry`).

## Confidence

High on both: the RNG call site is a single line and the duration is a single config field. I did **not** measure actual roll distribution to
demonstrate PRNG predictability — the argument is about the algorithm class, not an observed break.
