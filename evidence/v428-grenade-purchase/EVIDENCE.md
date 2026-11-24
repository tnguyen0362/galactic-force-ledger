# Grenade ownership, purchase and the charge cap (build 428)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## What was wrong
- **No ownership check.** `GrenadeRuntime` accepted any `kind`, so a fresh profile could throw the requisition EMP grenade for free.
- **No purchase path** for grenades at all; `Economy.Grenades` carried `unlockRank` and nothing read it.
- **Charges defaulted to 2**, where the spec says both grenades carry 3 (`S04-053`), and EMP's rank was 5 rather than 4 with no cost.

## Implemented
- Config corrected: Frag `count 3, cost 0`; EMP `count 3, rank 4, cost 550`.
- `toss` refuses a kind the player does not own (`grenade not owned`) and still refuses at zero charges (`no charges`).
- `ArmoryService.buyGrenade` charges rank and cost, records `ownedGrenades`, publishes `GF_GrenadeBought`.
- `profile.ownedGrenades = { Frag = true }` by default; charge default raised to 3.

## Measured
| Check | Result |
|---|---|
| Throw EMP before buying | refused `grenade not owned`, charges unchanged at 3 |
| Buy EMP | `ok`, `GF_GrenadeBought = "EMP:550"` |
| Throw EMP ×3 after buying | charges 3 → 2 → 1 → 0 |
| 4th throw | refused `no charges` |

So the purchase gate, the ownership gate and the three-charge cap are all real and enforced server-side.

## Limits
- **Charges never refill.** There is no per-mission reset, so a player who throws three grenades has none for the rest of the session. The spec's "max 3" implies a per-mission supply.
- Frag's charge cap was not re-measured after the config change; only EMP was.
- The armory has no BUY button for grenades — only the remote path exists, so a player still cannot purchase EMP from the UI.
- Throw arc, fuse timing and preview remain unmeasured.
