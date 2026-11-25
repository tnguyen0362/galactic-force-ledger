# Four classes verified available with correct personal + team auras (place 495)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Instrumentation only, no source edits.

## Data first this time

Dumping an archetype before trusting it has caught me three times, so the class shape was printed before anything was asserted:

```
Assault  personal={ReloadSpeed 0.10}  team={ReloadSpeed 0.05}
Heavy    personal={MaxShield 0.15}    team={MaxShield 0.05}
Recon    personal={DodgeRecharge 0.15} team={MoveSpeed 0.05}
Support  personal={ReviveSpeed 0.20}  team={HealthRegen 0.10}
```

All eight values match `GOAL_2026-11-24.md` L66 verbatim — *"Assault personal reload rate +10%, squad reload rate +5%; Heavy
personal max shield +15%, squad shield +5%; Recon personal dodge recharge rate +15%, squad movement +5%; Support personal revive
rate +20%, squad HP regen rate +10%"*.

## Runtime verification

Each class was selected on a real profile and applied through `ClassService.apply`:

```
Assault  ok=true  move=0.00  reload=0.15  shield=0.00  regen=0.00
Heavy    ok=true  move=0.00  reload=0.00  shield=0.20  regen=0.00
Recon    ok=true  move=0.05  reload=0.00  shield=0.00  regen=0.00
Support  ok=true  move=0.00  reload=0.00  shield=0.00  regen=0.10
```

Three things confirmed:

1. **All four are immediately available** — no purchase, rank or unlock gate blocked any `apply`.
2. **Personal and team stack on the owner**, which is what the spec requires for a solo player (*"each active class aura once,
   including its owner... treat solo as its own squad"*): Assault `0.15 = 0.10 + 0.05`, Heavy `0.20 = 0.15 + 0.05`.
3. **Each class produces a distinct effect** — reload, shield, movement, regen respectively, with no bleed between them.

Recon's `move=0.05` is its *team* component while its personal bonus is `DodgeRecharge`, which this attribute does not publish;
Support's `regen=0.10` is its team component while its personal bonus is `ReviveSpeed`. So the readings are consistent with the
config rather than evidence of a missing personal bonus.

## What this does not prove

- **The aura reaching a squad-mate.** One local client only. `modifiersFromIds` is exercised for a single player, so the
  multi-player merge path is unread.
- **Duplicate-stack prevention.** The spec requires each class aura to apply once even if two players share a class. Untestable
  without a second client.
- **The +25% caps** on movement and reload rate modifiers, and the +25% shield capacity cap, are not exercised — no combination
  reached them.
- **`MaxShield` applied without free healing** (spec: *"preserve current absolute value, clamp"*) was not checked; only the modifier
  value was read.
- The `duration=base/(1+speedBonus)` formula for positive rate traits was not exercised.

## Status

`COUNT-CLASS` ("immediately available distinct classes") is satisfied: **4**, all available, all distinct, values conforming. The
remaining class-behaviour clauses live on the other class rows and stay unproven pending a second client.
