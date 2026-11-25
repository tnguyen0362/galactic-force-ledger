# Mastery progress in the debrief, with an ordering bug fixed on the way (place 471)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 471**.

## The gap

`S10-039` / `GOAL_2026-11-24.md` L165: *"Mission-only at settlement; display progress in debrief/Armory."*

Mastery was settle-able and persistable after places 467–470, but nothing ever showed it. A player could grind toward level 5
with no indication of how close they were — which makes the second augment socket feel arbitrary.

## The ordering bug this exposed

Mastery settles in `ExtractionService.finish`, and the debrief payload is built inside `RewardsService.grant` — which
`finish` calls **before** the settle ran (the settle block sat at the end, next to `SquadService.reset()`).

So a naive payload field would have reported the **pre-mission** mastery value: the player finishes a mission, earns 25 XP, and
the debrief tells them they earned nothing. That is worse than no display at all.

Fixed by moving the settle block above the `RewardsService.grantAll(...)` call. It already used `payoutObjective`, which is
computed earlier in `finish`, so the move is safe.

## The change

| file | change |
|---|---|
| `ExtractionService.finish` | mastery settle moved **before** the payout, with the reason in a comment |
| `RewardsService.grant` | reads `profile.weaponMastery[weaponId]` and `ProfileService.masteryLevel` after settlement, adds `mastery = { weaponId, xp, level }` to the `MissionComplete` payload |
| `MissionHUD` | renders `Mastery  <weapon>  level <n>  (<xp> XP)` after the Military XP line |

All three compile.

## Measured

Probe `Script` in `ServerScriptService` (live module instances): equip `SMG03`, complete the primary, set `pendingMastery = 25`,
then `ExtractionService.finish(true)`.

```
weapon=SMG03  before=60  after=85  settled=25
```

Then the **rendered** client debrief, read from `PlayerGui`:

```
Credits  base 450  +  squad bonus 0
Military XP  base 600  +  squad bonus 0
Mastery  SMG03  level 1  (85 XP)      <- the just-settled value
Primary objective: COMPLETE
Extraction: SUCCESSFUL
Salvage bonus  +0 scrap  +0 cells  +0 tech
Carried salvage secured
Salvage: 0 scrap · 0 energy cells · 0 tech
Military Rank: 15
```

`(85 XP)` is the proof the ordering fix landed: had the payload been built first it would have read `60`.

## A mistake worth recording

My first edit attempt corrupted `ExtractionService` with a stray `-` at the start of a comment line:

```
	-	-- primary failed keeps nothing; ...
```

Cause: I built the replacement with `string.gsub`, and the **pattern** contained `-` characters, which Lua treats as lazy
quantifiers. `gsub` is not a plain-text replace. `loadstring` caught it immediately (`Expected identifier ... got '-'`) and it
was repaired in one edit — but the lesson is that every use of `gsub` on source text here is a pattern match, and this project
has already lost an edit to text matching once (`v439`: *"That line exists twice — the edit landed in the late-join one"*).

## Still open

- **Armory surface**: the spec asks for mastery in the debrief *and* the Armory. Only the debrief is done. `ArmoryService.state`
  exposes augment sockets per weapon but not mastery XP or level, and no Armory row renders either.
- Level 5 is the last level, so the line reads `level 1` for a long time; there is no "level 5 is max" annotation.
- Solo, `SABOTAGE_RELAY`, one weapon. No co-op debrief check.
