# Mastery does persist; the attribute was lying. Publish-on-load added (place 469)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, multiple Play sessions. Place saved as **version 469**.

## The question I left open last batch

I recorded that the previous batch wrote 50 mastery XP to `SMG03` and a later server read it as **0**, and refused to call it
either a defect or a non-issue:

> *"Either the write missed the spec's ~60–90 s autosave window, or `weaponMastery` does not survive the DataStore round-trip,
> which would make mastery session-only."*

Neither. The XP had persisted the whole time; the **attribute** was the liar.

## What actually happened

`GF_Mastery_<weaponId>` was written in exactly one place: inside `ProfileService.addMastery`. Nothing published it on join. So on
a fresh server the attribute read `nil` until the player earned more mastery — even though `profile.weaponMastery[weaponId]`
held the real value.

Measured, in order:

| step | reading |
|---|---|
| server 1: attribute before any award | `0` |
| server 1: `addMastery(plr, "SMG03", 10)` | returned **60** — so the profile already held **50** |
| server 2 (after full stop/start): `ProfileService.get(plr).weaponMastery.SMG03` | **60** |
| server 2: `GF_Mastery_SMG03` attribute | **nil** |
| server 2: `masteryLevel` | 1 (correct: level 2 needs 100) |

`addMastery` returning 60 from a `+10` request is what disproved my own hypothesis: `current` was 50, therefore the value had
survived the previous session. The attribute simply had never been set on that server.

## The fix

In `ProfileService.load` — the single choke point every caller goes through, which already syncs `IntroSeen` — mastery is now
published for every weapon in the profile:

```lua
pcall(function()
    for weaponId, xp in pairs(migrated.weaponMastery or {}) do
        player:SetAttribute("GF_Mastery_" .. tostring(weaponId), xp)
    end
end)
```

Verified in a fresh server: on join, with no award this session, `attrXP=60` and `profileLevel=1`.

## Why this mattered more than it looks

This is the **seventh** false-negative mechanism this project has produced, and it is the same shape as the others: an
instrument that disagrees with real state. `HANDOFF.md` already carries the rule — *"attributes that mirror real module state,
and counters rather than last-value fields, are the fix."* This was a mirror that was only ever written from one direction.

Concretely: any HUD or Armory surface reading `GF_Mastery_<weapon>` would show nothing for a returning player, which reads as
lost progress. And it is what made me almost write off a working subsystem as broken.

## Still open on mastery

- `S10-039`: mastery progress is still not displayed in the debrief or the Armory.
- The level-5 second augment socket is unverified.
- "Track every **owned** weapon" is not enforced — any weapon id on session state can be credited.

## Limits

- Persistence verified for one account, one weapon, and a Studio-local DataStore. No cross-place or live-server test.
- The publish-on-load loop is unbounded by weapon count; with 8 weapons that is 8 attributes, which is fine, but it is not
  capped or pruned if the profile ever accumulates stale weapon ids.
