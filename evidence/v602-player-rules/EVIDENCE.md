# v602 — player rules batch (S03-019/036/021/023)

Implementations:
- S03-019 roll lockout: fire() rejects while character Rolling attribute true. Probe: ammo untouched
  during roll (28->28), control fire after roll works (28->27). `[GF_S03] PASS`
- S03-036 mission loadout lock: armory equip/buy/equipAbility/equipGrenade/equipArmor all reject with
  "loadout locked in mission" while GF_InMission. Probe: equip rejected in mission, station unaffected.
- S03-021 fall damage: server humanoid state watching, <=55 studs/s harmless, 55-95 linear up to 40%
  max health through the VitalsService shield-first path. UNVERIFIED live (needs a real fall).
- S03-023 auto flashlight: client LocalScript, chest-mounted PointLight enabled automatically when
  ambient+brightness luma is dark. UNVERIFIED visually (needs a dark-area screenshot).
