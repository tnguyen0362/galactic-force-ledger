# Rank gates are enforced on all four purchase paths (place 515)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. No source changes; probes removed and place re-saved
(no content delta).

## The problem with testing this

The profile is rank **15**, while the highest requirement in the catalogue is rank **7** for weapons and rank **12** for armour. So every rank gate
was already satisfied and no refusal was reachable. Lowering `profile.rank` to 1 for the duration of the test, then restoring it, makes all four
reachable.

One ordering detail that mattered: **ownership is checked before rank**, so an already-owned item refuses with `"already owned"` no matter the rank.
The first attempt produced `"already owned"` for `Sentry` and `TROPHY` for exactly that reason — the items had to be un-owned first.

## Measured

```
weapon  MR07   (r4)  at rank 1 -> "requires rank 4"
ability Sentry (r4)  at rank 1 -> "requires rank 4"
armour  TROPHY (r12) at rank 1 -> "requires rank 12"
grenade EMP    (r4)  at rank 1 -> "requires rank 4"   owned=false
grenade Frag   (r1)  at rank 1 -> no rejection (correct: rank 1 is allowed)
```

Four purchase paths, four correct refusals, each naming the exact requirement. `EMP`'s ownership stayed `false`, so a refused purchase grants
nothing. `Frag` being permitted at rank 1 is the control case: the gate discriminates rather than blocking everything.

## Also confirmed incidentally

The ability catalogue's unlock data matches the spec exactly — `Sentry rank4/900` and `OrbitalStrike rank8/1800` — read from the live config during
the ownership listing.

## What this does not cover

- `S12-012`'s second clause (standard rank clearance opening corresponding services or requisitions) is **not** verified — there is no requisition
  system to open.
- Rank was manipulated directly rather than earned, so this proves the gate logic, not the rank progression that feeds it.
- No client-side check: the armory may still *list* locked items, which is intended (`S12-008` asks for a separately shown rank gate), but I did not
  verify how locked items are presented.
