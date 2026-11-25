# place 561 — augment instance model evidence

Implementation saved to Roblox as place versions 559–561.

## Live server lifecycle probe

A temporary real server `Script` was inserted only for the probe, then removed. It ran inside the live server VM rather than the isolated MCP tool VM. Results:

```text
PASS grant1/2/3/4: four per-instance UIDs created
PASS duplicate uids distinct
PASS common trait count: 1
PASS quality quantized: 161
PASS equip uid
PASS rare has tradeoff: 2 traits
PASS reroll offer: cost 25
PASS reroll deduct once: 500 -> 475
PASS keep resolves pending
PASS keep preserves traits
PASS fusion succeeds: three Rare/Universal copies -> one Epic/Universal copy
PASS fusion inputs consumed
PASS favorite protects dismantle
PASS dismantle pays rare scrap: 18
PASS cache roll deterministic shape: 4 draws for Legendary cache
```

The later inventory inspection found the UI-driven fusion result directly in the profile:

```text
TargetDiscipline:aug_e5f8af9d0f0b46cbb3a481eabf67240e:src=fusion:aug_a0ff4929e56c4572ba71f2b6b82dc368+aug_ff4988cfd28f488da279622365c95e4b+aug_f966dc7313bb4e79ba63d9f6c48bf2c3
```

## Armory UI probe

The Armory was opened through the same replicated attribute path used for scripted QA. Client inspection confirmed:

```text
panel=true quickfeed=true quality=true rerollbtn=true
```

A reroll remote was fired through the same `SetLoadout` action the button uses. Client inspection of the pending offer row then confirmed:

```text
pending=true old=true new=true accept=true keep=true quality=true
```

## Boot regression

Every fresh playtest in this batch booted with:

```text
[GF] boot: config check PASS (688 assertions)
[GF] boot: services online (persistence=datastore)
```

## Scope limits

This batch implements the per-instance inventory foundation, exact trait display, reroll offer persistence path, dismantle/fusion core transactions and duplicate identity. It does not complete: cache-open crash journaling, full category-selection UX, bulk dismantle filters/preview/confirmation, signature variants, offline 100k Monte Carlo validation, all missing supported stat consumers, or exact canonical catalog renaming.
