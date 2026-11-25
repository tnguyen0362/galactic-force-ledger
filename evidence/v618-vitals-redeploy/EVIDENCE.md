# v618 — vitals regen fix + spec redeploy model + enemy drop tables

## CRITICAL FIX: shield/HP regen never ran (all versions <= v614)
Root cause: VitalsService heartbeat called `require(script.ClassService)` — ClassService is a SIBLING
module, so script.ClassService is nil and require(nil) threw every tick exactly when regen should run.
Fixed to script.Parent.ClassService. Live verification (GF_RG): shield manually set to 50 with lastDamage
10s past -> 82.5 within 1.5s (~25/s spec rate). Full timing probe (GF_TM, deployed mission, player anchored
away from enemies): applied=50 damage shield 100->50, regenDelay measured 4.1s (spec: 4s), final=100.
HP regen shares the same heartbeat mechanism with HealthRegenDelay=9/Rate=8 constants conforming.

## Spec redeploy model (S03-030) — tickets retired
Implementation: first permanent death -> 8s countdown (REDEPLOY_COUNTDOWN=8, published as
GF_RedeployCountdown/GF_RedeployPendingFor + MissionEvent) -> automatic free redeploy:
LoadCharacter, safe pod at squad anchor or LZ, VitalsService.reset (full HP/shield),
CombatService.applyLoadout (full ammo+reserve), _G.GrenadeRefill (full grenades).
Ability cooldowns are timestamps in player state and deliberately not touched -> preserved.
Second permanent death -> returnToStation (no spectating); mission fails only when no active or
pending-redeploy players remain. DownedService.resetMission wired into StationService.resetMission.
Live verification (GF_RD PASS): countdown=8, ammo burned 3/10 -> restored 28/168, grenades 1->3,
shield 100, alive at mission.

## Enemy drop rarity tables (S11-016..020)
ENEMY_DROP_WEIGHTS: infantry 85/14/1/0, elite 55/35/9/1, BastionWalker 0/70/28/2, HighMarshalVeyr
0/40/50/10 (C/R/E/L, Normal baseline). enemyDropWeights() scales non-Common by DROP_SCALE
(Easy .65/Hard 1.35/Extreme 1.7) and renormalizes. Cache open path prefers enemy-source weights over
mission-tier weights whenever the cache instance source is an enemy id. Boss tables never Common.
