# Ability cast pipeline works; the v260 "unresolved" blocker was a measurement artefact (place 463)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client.

## What BLOCKED.md claimed

> **Ability casts from the client VM produced nothing at all (v260) — unresolved**
> `require(Services.State).get(player)` returns nil on the server, while `ProfileService.ensure(player)` returns a profile.
> So even a connected handler would take the "profile not ready" branch and reject. **This matters for players:** if
> `State.get` is nil when an ability key is pressed, the key does nothing.

Two separate things are going on, and only one of them was real.

### 1. The nil read was the tool-VM trap, not game state

`State.get(player)` was read from an MCP tool VM. A tool-VM `require` gets its **own** module instance, so `states[player]`
is empty there no matter what the game holds. Reproduced this session: after a successful live cast that built a dome, a tool
VM still returned `State.get -> false`.

Read from a real `Script` inside the game instead: `State.get(player)` returned a live state with `shield = 100`. So the
"profile not ready" branch was never being taken in play.

### 2. The code had already been hardened against it

`AbilityService.cast` now self-heals at lines 638–650: a nil state triggers `State.ensure(player)` and carries on rather
than refusing. The comment records the history — *"Refusing used to be a silent dead key; now the cast initialises the state
it needs and carries on."*

## Measured live

A probe `Script` in `ServerScriptService` (so it shared the live module instances), then a client-fired remote:

| Reading | Value |
|---|---|
| `State.get(player)` in the game VM | **non-nil**, `shield = 100` |
| Self-heal needed? (`CastStateSelfHealed`) | `nil` — never triggered |
| Client `UseAbility:FireServer({abilityId="DomeShield", position})` | sent |
| `GFDebug.AbilityCastRequests` | **1** |
| `GFDebug.LastCastRejected` | **nil** — not rejected |
| World effect | **`Workspace.DomeShield`, `DomeShieldRim`, and 14 `DomePost` parts created** |

The cast was accepted and produced a real object in the world, which is the thing the blocker said could not happen.

## Ability config measured against spec

`Configs/Abilities` holds **6** abilities, matching the six the specification names.

| ability | spec CD | config CD | spec radius | config radius | verdict |
|---|---|---|---|---|---|
| Airstrike | 90s | 90 | — | 40 | matches |
| Dome Shield | 70s | 70 | — | 18 | matches |
| Sentry | 100s | 100 | — | 60 | matches |
| Orbital Strike | 150s | 150 | — | 12 | matches |
| **Orbital Lance** | **165s** | **180** | 6 | 6 | **CD wrong** |
| **Reflective Barrier** | **85s** | **95** | **10** | **12** | **CD + radius wrong** |

`GOAL_2026-11-24.md` L77 also specifies Orbital Lance as *"total 420 distributed over 3 pulses"*; the config carries
`damage = 550` as a single value with no pulse split. L78 specifies Reflective Barrier as *"immediate/7s"*; the config sets
`duration = 6`.

**Not changed.** Cooldown, damage and radius are balance levers with a direct feel cost, unlike the war-points fix which had
no balance implication. Recorded on `S05-015` and `S05-016` for the owner to set, per `S16-113`.

## Not covered

- Only Dome Shield was cast. The other five keep their shared pipeline verified but their individual effects unproven.
- Dome duration (20 s), the 18-stud radius and whether direct outgoing fire works from inside the dome are unmeasured.
- `S05-008` (one dome per owner, replacement destroys the old) was not double-cast.
- Cooldown preservation across death and rejoin (`S05-007`) untested.
- The dome is a transient world object from a Play session; the place was not re-saved for this batch.
