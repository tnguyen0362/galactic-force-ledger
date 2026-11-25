# The free starter pick now exists and works end to end (place 518)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 518**.

## What was missing

`S10-009`'s fourth reward component: *"First-time choose AR/SMG/LMG free"*. Without it a new player could not obtain `SMG-03` (600) or `LMG-12` (1400),
which is why `S01-027`'s "starter equipment" half was unmet.

## Implemented

**Server** — `TutorialService.claimStarter(player, weaponId)`, validated in this order:

1. profile exists → `"no profile"`
2. `tutorialCompleted == true` → `"tutorial not complete"`
3. `starterClaimed ~= true` → `"starter already claimed"`
4. `weaponId ∈ {AR01, SMG03, LMG12}` → `"not a starter option"`

then grants ownership, sets `starterClaimed`, marks dirty, and publishes `GF_StarterClaim` / `GF_StarterClaimState`.

**Profile** — `starterClaimed = false` added to `ProfileService.defaults`.

**Transport** — new `ClaimStarter` RemoteEvent under `GF.Remotes`, wired in `TutorialService.start()`; a rejection sets `GF_StarterClaimState = "rejected:<reason>"`.

**UI** — `TutorialUI` shows a `STARTER PICK` frame with `AR` / `SMG` / `LMG` buttons once the tutorial reports complete and the claim is outstanding.

## Measured

Server rules, called directly:

```
before completion:      ok=false  why="tutorial not complete"   owned=false
claim SMG03:            ok=true                                 owned=true  claimed=true
second claim LMG12:     ok=false  why="starter already claimed"
illegal MR07:           ok=false  why="not a starter option"
```

(For the last two, `owned=true` reflects ownership that already existed on this test profile from earlier work — neither call granted it.)

UI, measured in a live client:

```
StarterPick present | label=STARTER PICK | buttons=AR,SMG,LMG | visible=true
```

Full player path — the client fired `ClaimStarter("LMG12")` exactly as the button does:

```
now: LMG12 owned=true  claimed=true  state=claimed:LMG12  tutorialCompleted=true
```

So the option is granted free, the grant is recorded once, and the state replicates.

## Two bugs I hit and fixed in this batch

- **The pick frame never appeared.** I parented it to `script.Parent:FindFirstChildOfClass("PlayerGui") or script.Parent`, which resolves to
  `StarterPlayerScripts` — so the frame was created inside a non-UI container. Fixed by parenting to `Players.LocalPlayer:WaitForChild("PlayerGui")`.
  I verified the fix by looking for the frame, not by assuming the code ran.
- **The pick would have vanished after four seconds.** `paint()` sets `gui.Enabled = false` on a 4-second timer after completion; a frame parented under
  `gui` would hide with it. Reparented to the PlayerGui root, with a comment saying why.

A third problem was **measurement**, not code: my first end-to-end read reported `owned=false` and looked like a failed grant. The reader script's
`task.wait(11)` expired *before* the client fired the remote, so it observed the pre-claim state. A fresh reader after the click showed the truth.

## Limits

- The **button click itself** was not physically clicked; the client fired the same remote the `Activated` handler fires. The handler body is three
  lines and untested only in the sense that `Instance.new("TextButton").Activated` was not exercised.
- The pick appears whenever `Tutorial_Complete` is true and no claim exists — including for a returning player who re-enters the tutorial state, which
  is probably fine but is not a designed rule.
- `starterClaimed` is new schema. A profile saved before this change loads with `false` via defaults, which is intended, but the migration was not
  tested against a real old save.
- `TutorialService.finishForTest` from the previous batch still ships.
