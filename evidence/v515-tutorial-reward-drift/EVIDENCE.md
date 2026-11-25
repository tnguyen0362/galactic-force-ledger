# Tutorial completion grants 200/400 — spec says 350/410 plus a cache and starter items (place 515)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level inspection of `TutorialService` and `ProfileService`. No place changes.

## What completion actually does

```lua
local function finish(player)
    workspace:SetAttribute("Tutorial_Complete", true)
    local profile = ProfileService.ensure(player)
    if profile then
        profile.tutorialCompleted = true
        ProfileService.markDirty(player)
        ProfileService.award(player, 200, 400)      -- credits, xp
    end
    ReplicatedStorage.GF.Remotes.MissionEvent:FireAllClients({ kind = "tutorial-complete" })
end
```

`ProfileService.award(player, credits, xp)` adds to `profile.credits` and `profile.xp` and recomputes rank.

## The drift, quantified

| | spec (`S10-009`) | build |
|---|---|---|
| Credits | **350** | **200** |
| XP | **410** | **400** |
| Common cache | **1** | none |
| Starter items | **yes** | none |

Both numbers are short and two of the four reward components are absent.

## `S01-027`: the completion flag has no consumer

> *"Completion unlocks Easy/Normal, gives first cache and starter equipment."*

A search for `tutorialCompleted` and `Tutorial_Complete` across server and client returns **10 hits, all writers or UI displays**:

- `TutorialService` writes it (start/finish/reset)
- `ProfileService` declares it and uses it for a migration decision (`introWatched` → resume tutorial)
- `TutorialUI` and `CinematicUI` read the *workspace attribute* to display state

**Nothing reads it to gate a difficulty, grant a cache, or offer a weapon pick.** So the three things the row asks for do not happen: no difficulty unlock, no first cache, no starter equipment.

Worth being precise about one of them: "unlocks Easy/Normal" may be **vacuously** satisfied if Easy/Normal are never locked in the first place — the difficulty config has no tutorial dependency. Either way, the *grant* framing of the row is unmet.

## `S12-009` and the free starter set

Catalogue items at cost 0: `AR01`, `P01`, `Airstrike`, `DomeShield`, `OrbitalLance`, `ReflectiveBarrier`. The last two are rank-10 unlocks, not starter gifts. So starter-free equipment **does** exist as priced items — but the tutorial's *"first-time choose AR/SMG/LMG free"* pick is not implemented, which is the mechanism by which a player would obtain `SMG-03` (600) or `LMG-12` (1400) at no cost.

## Monetisation: nothing paid exists

A search across server, client and replicated code for `MarketplaceService`, `DeveloperProduct`, `GamePass`, `PromptPurchase` and `robux` returns **zero references**. So:

- `S12-016` (experimental boss abilities gameplay-earned) — **vacuously satisfied**: nothing can be bought.
- `S12-017` (no paid animations, skins or exclusive power) — **vacuously satisfied** for the same reason.
- The spec's **premium requisition (Siege Division)** cannot exist as specified, since there is no purchase plumbing at all.

## Method note

My first pass searched `TutorialService` for `grant|credits|reward|ownedWeapons` and returned **zero lines**, which read as "it grants nothing". The award is spelled `ProfileService.award(...)`. **Searching for the wrong vocabulary produced a false negative for the seventh time this session** — the same class of error, one layer up from reading a value I hadn't printed.

## Not tested

The tutorial was not played through, so this is code-read rather than measured behaviour; the `Tutorial_Complete` attribute firing was not observed live.
