# Headshots measured end to end: ×2.00 against an authored ×1.50 (place 522)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Verification only; no source changes.

## Result

```
torso = 18.0  [dOriginRoot=5.2]     AR01 base damage
head  = 36.0  [dOriginRoot=3.4]     base × 2.00
ratio = 2.00                        authored 1.50
```

The head multiplier drift flagged last batch is now **measured through the real fire path**, not just inferred from `weakMultiplier`. Every headshot is
**33% stronger** than the specification allows.

## Why three earlier attempts failed

Each failure had a distinct cause, and none was the game:

1. **Wrong attribute container** — `note()` writes to `workspace.GFDebug`, not `workspace`, so a rejected shot looked like a silent one.
2. **Poisoned shot sequence** — a prior probe used `shotId = math.random(1e6)`; later shots with small ids were rejected as stale.
3. **`origin-too-far`** — the harness picked aim origins 6–18 studs from the player, but `MAX_ORIGIN_OFFSET` is **8**. Standing the player beside the target
   brought every origin inside the limit.
4. **Chest-plate occlusion** — even a correct aim line to `Torso` hits `ChestPlate`, which sits in front of it. The harness now *searches candidate origins*
   and only fires from one whose first raycast hit is the part it names.

## The harness recipe, worth reusing

Future combat verification in this project needs all four of these:

```lua
-- 1. a mission, or every hit is swallowed
workspace:SetAttribute("GF_InMission", true)
workspace:SetAttribute("GF_DeployGraceUntil", 0)
-- 2. freeze the rig so aim and raycast see one pose
for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = true end end
-- 3. stand within MAX_ORIGIN_OFFSET (8) of the target
root.CFrame = CFrame.lookAt(torso.Position + Vector3.new(0, 0, 3.2), torso.Position)
-- 4. pick an origin whose FIRST hit is the intended part, rather than assuming
local hit = workspace:Raycast(o, (part.Position - o).Unit * 40, rp)
if hit and hit.Instance.Name == "Head" then ... end
```

Point 4 is the one that took three attempts. Aiming *at* a part does not mean hitting it.

## Also established

Shield-first routing was probed while the harness was being built: with `Shield = 40` and a 36-damage hit the shield and health both came back unchanged — but
that run used the broken origins, so it proves nothing. Shield absorption *was* verified earlier in the session on a live enemy (60 shield absorbed the
shotgun's first hits with health untouched), so this is not a gap in the ledger, just an unmeasured case in this particular harness.

## Status

`S04-014`: body ×1.00 verified, head ×2.00 verified, authored head is ×1.5, and the *"marked weakpoint"* clause remains unimplemented (no rig part carries a
`WeakPoint` attribute). The row stays PARTIAL with the drift recorded precisely.

## Not changed

`weakMultiplier`'s `return 2` for `Head` is untouched. Flipping it to 1.5 invalidates every TTK figure recorded in this project, so it belongs to the owner's
balance pass — but the correct value is now measured rather than read.
