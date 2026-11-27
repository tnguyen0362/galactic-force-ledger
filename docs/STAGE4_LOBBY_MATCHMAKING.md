# STAGE 4 — Lobby, Hybrid Matchmaking & Emergency Dispatch — Design
**Author:** beta | **Date:** 2026-11-28 | **Authority:** Counteroffensive master assignment §7, §71-89
**Status:** design — implementation proceeds per the sequencing section

---

## 1. What the mandate requires (extracted)

- **40-player lobby** (§71) — place configuration, not code
- **Four physical deployment terminals** replacing the central war table as the deploy architecture (§72) — the table may persist as theater display, never as the interaction point
- **Hybrid matchmaking: global + local** (§78-82) — squad formation within the dense lobby first, cross-server global fallback; a public squad browser UI; honest search-time estimates; cancel anytime
- **Emergency Dispatch** (§7, §83-85) — player-initiated global reinforcement: a squad in trouble raises a beacon visible across ALL servers; responders join mid-mission; Y/Triangle binding in lobby context for quick-response
- **Deploy flow** (§86) — 15s warning, ready-acceleration, solo-immediate — ALREADY CORRECT in SquadService, preserve
- **Reserved-server missions** (§88) — multi-place teleport architecture

## 2. Architecture decision: the hybrid model

**Local-first, global-fallback.** Rationale: at 40 players per lobby, the lobby itself is the densest matching pool — most players should find squads in-server with zero cross-server friction. Global matching exists for off-peak population and specific operation/difficulty niches.

```
SQUAD FORMATION
  lobby-local: SquadService in-memory membership (exists — leader election, deploy timing correct)
  cross-server join: listings carry the leader's jobId; joining = TeleportService:TeleportToJobId
                     to the leader's lobby server, then local squad join after arrival
LISTINGS (global memory store)
  GF_PublicSquads SortedMap: squadId → {leader, leaderJobId, operationId, region, difficulty,
    capacity, taken, state, createdAt} TTL 90s, heartbeat refresh every 45s while forming
  atomic seat reservation: UpdateAsync on the SAME store (fixing the GF_SquadListings mismatch —
  that dead path is deleted, not repaired)
QUICK DEPLOY (global matching)
  per-player queue entry published to MemoryStore (not in-memory — cross-server visibility)
  matching pass runs wherever queues are read: compatible entries (difficulty overlap, operation
  overlap, rank band) form an ad-hoc squad in the LOWEST-population suitable lobby... 
  SIMPLIFICATION v1: match = the oldest compatible leader-candidate becomes host in their current
  server; others teleport-join. no hidden minimum population — solo launch always available
MISSION EXECUTION
  v1 (now): missions run in-instance as today — the deployed squad teleports within the server
  v2 (owner-gated): reserved mission servers via second place; TeleportFlowService activates
```

## 3. Emergency Dispatch design

Direction of discovery per the mandate: **the responders find the beacon globally**, not the host's server only.

```
BEACON LIFECYCLE
  1. squad in-mission (or forming) raises dispatch: host action or auto-offer on squad-wipe-near
  2. beacon publishes to MemoryStore GF_EmergencyDispatch hashmap: beaconId →
     {hostJobId, hostUserId, operationId, region, difficulty, seatsOpen, privacy, expiresAt,
      missionAge, catchUpPayBasis}
     TTL 120s, heartbeat while open
  3. every lobby server polls the store every 5s; beacons surface in the squad browser UI
     AND as the Y/Triangle quick-response prompt (lobby context): press-and-hold Y joins the
     most urgent compatible beacon (nearest expiry, seats open, unlocked difficulty)
  4. responder flow: atomic seat reservation (UpdateAsync) → teleport to hostJobId →
     arrival lands in-mission by drop pod (DispatchService's existing pod-arrival — preserve)
  5. catch-up pay: responders earn a pro-rated share + response bonus (existing catch-up pay
     logic in DispatchService — extend cross-server)
CANCEL/EXPIRE: beacon TTL natural death; host close on mission end; join failure releases seat
```

## 4. Four-terminal lobby layout

The war table stays as a **theater display** (it dresses the room and shows war state) but loses
all deploy interaction. Four terminals — one per theater front arc (the connected region graph
split into 4 arcs of 2 regions each):

```
  T1 VERDANT ARC:  VerdantReach, ThornBasin
  T2 ASHEN ARC:    AshenDivide, RedMesa
  T3 FROST ARC:    Frostline, WhiteRidge
  T4 IRON ARC:     IronMarch, FoundryBelt
```

Each terminal: a physical console in the station (code-built geometry now, art pass coordinated
with claude later), proximity prompt opens the deploy UI PRE-FILTERED to its arc's regions.
The deploy UI itself is shared — terminal identity is just the initial region filter. This keeps
one UI implementation while making the physical distribution real: players spread across the room
by theater interest, and each terminal is a meaningful place.

## 5. What is implementable now vs owner/Studio-gated

| item | status |
|---|---|
| MemoryStore squad lifecycle + heartbeat + atomic seats | implementable now, pure code |
| squad browser data flow + filters | implementable now |
| cross-server join teleport (same-place jobId) | implementable now |
| quick-deploy global matching drain | implementable now |
| Emergency Dispatch global beacon + quick-response join | implementable now |
| four-terminal geometry + arc-filtered interaction | implementable now (art pass later) |
| 40-player cap | OWNER/STUDIO — place configuration |
| reserved-server mission teleport | OWNER — second place creation (creator dashboard) |
| in-engine verification | STUDIO window required |

## 6. Sequencing

1. MatchmakingService rebuild: correct store usage, heartbeat, jobId-carrying listings,
   seat-reservation correctness, quick-deploy global drain — server logic + headless-verifiable
2. DispatchService globalization: MemoryStore beacons, cross-server respond flow
3. Terminal geometry + arc filtering in the deploy UI (uses the Stage 3 operation-centric UI)
4. Client wiring: squad browser surface, Y/Triangle quick-response binding (context-dependent
   per the input audit — lobby context only, never conflicts with mission SwapWeapon)
5. Studio verification window when available

## 7. Honest constraints

- Cross-server join teleport in the same place is REAL Roblox capability (TeleportToJobId) —
  not a hack. But it costs the joining player a server hop (~5-15s load). The UI must say so.
- MemoryStore is eventually consistent: seat races are handled by UpdateAsync atomicity, but
  listing freshness is TTL-bound. A joiner can arrive at a squad that just filled — the arrival
  flow must handle the miss gracefully (return to browser with a clear message, never a dead end).
- Match-quality matching (rank bands, latency) is v2 — v1 matches on difficulty+operation only,
  documented honestly in the UI estimate text.


## 8. CRITICAL ARCHITECTURAL FORK (discovered during implementation scoping)

SquadService is a **single-squad-per-server** model: one members table, one leader, one shared
resource pool. the prototype's implicit constraint — one squad, one mission, one server. the
mandate's 40-player lobby requires multiple concurrent forming squads per server. analysis:

- the shared-resource consumers (SquadService.add × 7 across loot/optional/reward paths) resolve
  no squad context today — multi-squad means per-squad pools keyed off player membership
- deploy execution is per-player; squad-coordinated deploy is a thin layer over it
- in the TARGET architecture (reserved mission servers), single-squad-per-MISSION-server is
  actually correct — the multi-squad complexity lives only in the lobby layer
- in the INTERIM architecture (in-instance missions), two squads deploying concurrently would
  collide in the same mission space — the deepest reason the prototype is single-squad

**decision (beta, owner authority):** implement the additive global data layer NOW (listings,
browser data, quick-deploy matching, global dispatch) — verifiable, zero disruption to the
working loop. DEFER the multi-squad lobby rebuild until the reserved-server architecture lands
(owner-gated second place), because in-instance concurrent missions are incoherent anyway —
multi-squad without reserved servers buys complexity for a broken end state. the squad data
model built now uses squadIds throughout so the later migration is additive, not another rebuild.
single-squad-per-server interim constraint documented in the browser UI honestly.
