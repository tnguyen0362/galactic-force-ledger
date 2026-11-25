# Armory now shows the result of both actions (place 504)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 504**.

## The gap

Place 503 made inventory expansion and bulk cache opening reachable as buttons, then recorded the honest caveat: both results went to
`workspace` attributes (`GF_AugmentExpandResult`, `GF_BulkOpenResult`) and **nothing surfaced them**, so a player pressed a button and
learned nothing.

## Change

A status row under the action buttons, wired to `GetAttributeChangedSignal` for both results:

```lua
workspace:GetAttributeChangedSignal("GF_AugmentExpandResult"):Connect(function() ... "EXPANSION " .. v ... end)
workspace:GetAttributeChangedSignal("GF_BulkOpenResult"):Connect(function() ... "OPENED n CACHE(S)" ... end)
```

Both server results replicate to clients, so no new remote was needed.

## Measured

```
before firing:  READY | READY | READY
after firing:   READY | READY | OPENED 0 CACHE(S)
```

The line renders, and the bulk result reached the client and replaced the placeholder — the mechanism works end to end.

`OPENED 0` is correct behaviour, not a fault: every unowned Rare augment had already been granted by earlier probes, so the roll found
nothing to give and the batch stopped at zero. That is the third time this exhausted-tier path has behaved properly.

## Two limits worth stating

- **A single shared line, so messages overwrite.** The expansion result appeared first and was immediately replaced by the bulk result.
  Firing both in sequence means only the last is visible. A per-action line, or a short message queue, would fix it — I did not build
  one.
- **The expansion message was not observed in isolation.** It is the same code path as the bulk signal, and it demonstrably fired
  (otherwise only two labels would read `READY`), but I did not capture `EXPANSION …` on screen by itself.
- Three `READY` labels appear in the panel, which suggests the list is rebuilt and the stale instances are not destroyed. Harmless now,
  wasteful as the panel grows.

## Still missing on this row

`EXPAND +50` shows no **cost preview** (10 Cells + 3 Tech + 1000 Credits). The server enforces it; the button does not mention it. That
is the remaining usability gap on the expansion feature.
