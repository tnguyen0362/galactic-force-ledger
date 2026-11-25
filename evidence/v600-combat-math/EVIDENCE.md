# v600 — combat math measurements and overflow fix

`[GF_CM] PASS torso=18.0 head=36.0 ratio=2.00 afterHead1 shield=12 health=500 afterHead2 shield=0 health=488 ttk65=2.70s`

Measured live on synthetic targets through the validated fire path:
- Headshot multiplier exactly 2.00x on health (36 vs 18).
- Shield absorbs RAW damage only: 30-shield target hit by 18x2 headshot drops to 12 shield (raw 18
  absorbed, NOT head-boosted 36) with zero health damage while shield covers the raw.
- DEFECT FIXED: hitMultiplier was reset to 1 whenever any augment loadout existed, so overflow health
  damage lost the headshot bonus (measured 6 instead of 12). Now overflow raw x hitMultiplier x
  weakFactor x armorFactor applies exactly: second headshot breaks the 12 remaining shield and deals
  6 overflow raw x2 = 12 health damage (health 500 -> 488 exactly).
- TTK derivation anchored in the live 18-shot measurement: at 65% realistic accuracy ~28 fired shots
  at 600rpm = 2.70s firing time, inside the spec 2-4s band.
