# Buying an owned item does not double-charge — but `buy` refuses silently (place 515)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. No source changes. **Batch stopped early at the owner's request.**

## What was tested

`S12-010` requires that owning an item is not charged twice, and that buying from either the armory or the shop updates the same ownership. The test
called `ArmoryService.buy` three times on a profile with 10,000 credits:

```
first  SG04  buy=nil why=nil   credits 10000 -> 10000
second SG04  buy=nil why=nil   credits 10000 -> 10000
       AR01  buy=nil why=nil   credits 10000 -> 10000
```

## What this does and does not show

**Shown:** repeated purchases of owned items **do not charge**. Credits were unchanged across all three calls, so the double-charge half of the row
holds for these items.

**Not shown:** whether a *first* purchase charges correctly, because the account already owned `SG04` and `AR01` (starter). Every call hit the
"already owned" path, so the test never exercised a real purchase. That is a gap in the test, not a finding about the code.

**Also observed — `buy` is silent:** it returns `nil` for both success and refusal with no reason string, unlike `equipAugment`, which returns
`(ok, why)` and is what made the compatibility work verifiable. A player clicking an item they already own gets no explanation from the service
layer. The armory UI may add its own messaging, but the server contract carries none.

## State left behind

- Test profile set to `credits = 10000` by the probe.
- No source was changed in this batch; the place was **not** saved, so version 515 remains the last saved state.

## Next step when work resumes

Pick an item the account does **not** own (an ability such as `Sentry` at 900 credits, or an unowned weapon after checking `ownedWeapons`) and verify
that a first purchase deducts exactly the catalogue price and adds ownership — then re-buy to confirm the refusal. That is the half of `S12-010` that
this run could not reach.
