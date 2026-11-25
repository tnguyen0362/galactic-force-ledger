# place 587 — military requisitions

Implemented GOAL §12 as a permanent two-catalog military requisition system inside the Armory.

## Implementation

- `ReplicatedStorage.GF.Shared.Configs.Requisitions`: permanent **Frontline Arsenal** (free unlock) and **Siege Division** (1000 War Credits) catalogs, three tiers each, tier thresholds 600/1600 Credits spent within that requisition.
- `ServerScriptService.GF.Services.RequisitionService`: profile-local unlock/buy transaction core, preview/state rows, rank gates, tier gates, once-only entries, cache grant rollback, shared ownership checks, and shared Armory spend ledger.
- `ServerScriptService.GF.Services.ArmoryService`: `reqUnlock` and `reqBuy` actions; plain-Armory premium purchases now require both Siege Division access and the item's Siege tier. Standard Armory items remain rank-clearance accessible as GOAL §12 requires.
- `StarterPlayer.StarterPlayerScripts.StationArmoryUI`: requisition headers, progress (`TIER n · spend/next CR`), War Credit count, preview rows before unlock, separate tier/rank lock labels, buy/claim buttons.
- `ProfileService` persists `unlockedRequisitions`, `requisitionSpend`, and `purchasedEntries`.

## Canonical-data decisions

- Premium armor catalog prices are canonical at **GF-05 500 Credits** and **GF-06 750 Credits**; the old plain-Armory prices (2200/3200) were aligned down so Armory and requisition cannot disagree.
- Internal armor ids `TROPHY`/`BLACKSTAR` are retained for save compatibility, but their display names are now the spec identities **GF-05 Ash Sentinel** and **GF-06 Frost Warden**.
- GOAL does not specify a price for the premium tier-3 one-time Rare cache entry. It is implemented as a **free once-only claim** and recorded here instead of inventing a price.
- No Robux product, receipt processing, or real payment path was added.

## Probe

```text
[GF] boot: config check PASS (689 assertions)
[GF_REQ] PASS credits=4650 frontSpend=2050 siegeSpend=3300 scrap=44 cells=26
[GF_REQ_DONE]
```

The probe covered: catalog count and tier thresholds; synthetic any-order purchases; duplicate unlock not charging; rank refusal not charging; live Siege unlock spending exactly 1000 War Credits; premium access refusal before unlock; plain-Armory RL-09 tier-3 and GF-06 tier-2 refusals after unlock but before enough spend; GL-22 purchase/spend; shared SG-04 and RL-09 ownership preventing a second charge across surfaces; field/resupply/siege-kit resource grants and once-only behavior; tier 600/1600 crossings; one-time Rare cache grant; exact canonical premium armor names/costs; and state rows exposing requisition tier metadata. Live profile values were backed up and restored after the probe.

## Premium weapon numeric comparison

| weapon | ammunition | rpm | range | situational notes |
|---|---:|---:|---:|---|
| GL-22 Arcus | 4+16 | 50 | 180 | 13-stud blast; heavy burst but very low endurance |
| RL-09 Atlas | 1+7 | 24 | 260 | 10-stud blast; single-shot ultra-low endurance |
| AR-01 Service Rifle | 28+168 | 600 | 400 | general-purpose sustained fire |
| LMG-12 Suppressor | 75+225 | 660 | 420 | sustained suppression |

This verifies the lower-ammo/situational configuration, but it is not a live target-dummy TTK or splash-casualty comparison.

## Visual evidence

Studio screen captures in the playtest client:

- `v587_armory_scroll560` — armor rows show GF-05 500 CR / GF-06 750 CR and the Frontline Arsenal header/progress.
- `v587_requisitions_frontline` — Frontline rows preview costs/ranks and ownership, with Field Kit buyable and Resupply tier-locked.
- `v587_requisitions_siege` — Siege Division previews while locked with `UNLOCK 1000 WC`, separate entry rows and catalog prices.

## Remaining gaps

- Mock/test receipts and entitlement interfaces for any future approved Robux path remain absent (`S12-018` remains partial).
- Premium weapon comparison is numeric/config-level only; no live target-dummy TTK or splash-casualty test yet.
- Armor wearability was previously verified, but exact plate-shape variant conformance belongs to the separate armor-content audit.
