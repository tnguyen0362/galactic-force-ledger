# place 588 — prototype monetization boundary

Server-only receipt/entitlement harness for `S12-018`. This does **not** enable monetization or invent a real product id: `SiegeDivisionAccess` is a disabled placeholder product with sentinel `productId = 0`, and `LivePaymentsEnabled = false`.

## Live server probes

Main probe:

```text
[GF] boot: config check PASS (701 assertions)
[GF_MON] PASS first=PurchaseGranted dup=true liveRefused=true receipts=2 entitlements=1 wc=20
[GF_MON_DONE]
```

The probe proved:

- malformed receipts are refused before mutation;
- wrong-player receipts are refused;
- unknown product ids are refused;
- a live-shaped placeholder receipt is refused while prototype live payments are disabled;
- a server-only mock receipt granted the non-random Siege Division access entitlement;
- War Credits were unchanged by receipt grants;
- replaying the same purchase id returned `PurchaseGranted` with `duplicate=true` and did not insert another receipt or entitlement row;
- a second distinct purchase id was recorded without duplicating the entitlement row;
- entitlement state exposed the test grant;
- boot validation increased to 701 assertions, including disabled/non-random/placeholder product checks.

Cleanup probe in a fresh play session:

```text
[GF] boot: config check PASS (701 assertions)
[GF_MONC] PASS clean receipts=0 testEntitlement=false
[GF_MONC_DONE]
```

The real test profile was backed up and restored after the transaction probe; the cleanup probe confirmed no `GF_TEST*` receipt or test entitlement persisted.

## Implementation

- `ReplicatedStorage.GF.Shared.Configs.Monetization`: approved prototype convenience catalog, placeholder-only and disabled.
- `ServerScriptService.GF.Services.MonetizationService`: server-only receipt validation, entitlement grant/query/state interfaces, purchase-id idempotency, MarketplaceService `ProcessReceipt` binding, and mock receipt helper.
- `ServerScriptService.GF.Services.ProfileService`: persisted `entitlements` and `processedReceipts` tables with migration defaults.
- `ServerScriptService.GF.Test.CheckRunner`: boot assertions enforcing the no-live-payment prototype boundary.

## Boundary and limitations

No player-facing purchase button invokes a real Robux charge. No real Roblox developer product was created or tested. The receipt harness validates platform-shaped receipt fields and product/player/catalog constraints, but real platform purchase behavior remains unverified until the owner explicitly authorizes a real product in a private test environment.
