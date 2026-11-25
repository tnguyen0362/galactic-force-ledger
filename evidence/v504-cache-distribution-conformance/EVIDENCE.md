# Cache rarity distributions: sums conform, per-difficulty table does not (place 504)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level config inspection. No place changes.

## What exists

`Configs/Caches` holds one rarity weight table per **tier**, and difficulty selects a tier:

| difficulty | tier (`tierForDifficulty`) | weights C/R/E/L | sum |
|---|---|---|---|
| Easy | Common | 82 / 16 / 1.9 / 0.1 | 100 |
| Normal | Rare | 48 / 43 / 8 / 1 | 100 |
| Hard | Epic | 18 / 48 / 30 / 4 | 100 |
| Extreme | Legendary | 0 / 30 / 55 / 15 | 100 |

Each tier also carries its content count — `augments = 1 / 2 / 3 / 4` for Common/Rare/Epic/Legendary — and a per-enemy drop
chance (`infantry 0.01, heavy 0.04, commander 0.07` for Common).

## Against the authored table

`GOAL_2026-11-24.md` specifies the distribution **per mission source**:

| source | spec C/R/E/L | config (via tier) | verdict |
|---|---|---|---|
| Easy mission | 80 / 18 / 2 / 0 | 82 / 16 / 1.9 / 0.1 | close, not equal |
| Normal mission | 65 / 29 / 5.5 / 0.5 | 48 / 43 / 8 / 1 | **substantially off** |
| Hard mission | 40 / 43 / 15 / 2 | 18 / 48 / 30 / 4 | **substantially off** |
| Extreme mission | 20 / 43 / 30 / 7 | 0 / 30 / 55 / 15 | **wrong shape** |

Three findings, in order of importance:

1. **Extreme cannot drop a Common.** The authored table keeps **20%** Common on Extreme; the Legendary tier has `Common = 0`. So the
   hardest difficulty is strictly narrower than authored, not merely shifted.
2. **The drift is progressive, not uniform.** Easy is within ~2 points per bucket; Normal, Hard and Extreme diverge increasingly. That
   is the signature of hand-tuned tier weights standing in for a per-source table, rather than the table being transcribed.
3. **The structure differs.** The spec models a **source → distribution** mapping (five mission difficulties plus four enemy classes).
   The build models **tier → distribution**, with difficulty naming a tier and all enemies sharing one tier's weights. So per-source
   control does not exist even where the numbers happen to be close.

## What does conform

- **Every weight table sums to exactly 100**, which `S11-011` requires.
- **Content counts are 1/2/3/4 by tier**, matching the authored rarity ladder.
- The per-enemy **drop chances** exist (`infantry 0.01 / heavy 0.04 / commander 0.07`), which the spec's enemy rows imply but do not
  state numerically.

## Not changed, deliberately

Correcting these would mean retuning drop rates for every mission difficulty — including introducing a 20% Common roll on Extreme.
That changes loot pacing substantially and is the same class of decision as boss HP, ability cooldowns and mission length. Recorded with
exact numbers so the owner can rule on it in one pass with those others.

## Not examined here

`S11-027`/`S11-028` (per-cache probability maths, `1-(1-p)^n`) concern the *display* of odds and were not assessed; `S11-030`
(server-appropriate randomness) and `S11-068` (100k-draw simulation) are separate.
