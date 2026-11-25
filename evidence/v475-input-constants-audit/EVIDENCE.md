# Input / player / HUD audit: constants vs spec, two real drifts and two row-text errors (place 475)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, `Constants` read in Edit mode. No source changes, so the place
was not re-saved.

## Method

`Constants` was read whole and compared against `GOAL_2026-11-24.md` **L384/L921** (movement, dodge, delays) and L145 (downed /
revive) rather than against the ledger's own row text — because the row text is a paraphrase and paraphrases drift.

Measured values:

```
Movement.WalkSpeed = 17.5   Movement.SprintSpeed = 24     Movement.AdsSpeed = 13
Movement.RollCharges = 2    Movement.RollDuration = 0.55  Movement.RollDistance = 15.5
Vitals.HealthMax = 100      Vitals.ShieldMax = 100
Vitals.ShieldRegenDelay = 4 Vitals.ShieldRegenRate = 25
Vitals.HealthRegenDelay = 9 Vitals.HealthRegenRate = 8
Combat.DownedTimeout = 45   Combat.ReviveDuration = 3.5   Combat.ReviveRange = 12
```

## Two genuine mismatches

| constant | value | spec | consequence |
|---|---|---|---|
| `Combat.DownedTimeout` | **45 s** | **60 s bleedout** | a downed player dies 15 s earlier than authored |
| `Combat.ReviveDuration` | **3.5 s** | **"hold revive 3s"** | a revive takes half a second longer than authored |

Both are the same defect class the conformance check was built for — a number that silently disagrees with the spec — but
`Constants` is not a `Configs` module, so `CheckRunner`'s spec section does not cover it.

## Two row-text errors in the ledger itself

The ledger rows carry paraphrases that disagree with the authoritative spec, and I nearly recorded two false defects by
trusting them:

- **`S03-016`** says *"Walk 17, sprint 24 studs/s"*. Spec L384 says *"walk ~17–18"*. `WalkSpeed 17.5` **conforms**; the row
  text is the thing that is wrong.
- **`S03-018`** says *"roll 0.55s ~13 studs"*. Spec L384 says *"moves ~14–17 studs"*. `RollDistance 15.5` **conforms**.

This is the same failure that produced the ER-16 false conflict and the pity comment: a secondary description being treated as
the specification. Rows were corrected rather than the constants.

Everything else conforms: `RollCharges 2`, `RollDuration 0.55`, `AdsSpeed 13` (spec "~12–14"), `HealthMax/ShieldMax 100`,
`ShieldRegenDelay 4` / `HealthRegenDelay 9` (spec "preserve previous exact 4s / 9s delay logic").

## Confidence limits

- `Constants` values are **configuration, not demonstration**. Nothing here was fired, rolled, downed or revived to prove the
  runtime uses these numbers — except the downed flag itself, which a previous batch exercised via `VitalsService.downPlayer`.
- Dodge invulnerability for the full roll (L384's "full invulnerability during entire roll") was not tested at all.
- Fall damage, vault/mantle, and the armour flashlight were not examined this batch.
- The rest of the cluster (glyph swap, touch layout, virtual cursor, controller menus, colour-blind reliance) has **no evidence
  file specific enough to map**, so those rows stay UNKNOWN rather than being marked from presence of code.
