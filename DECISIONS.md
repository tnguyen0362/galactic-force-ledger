# DECISIONS

**Moved.** The single source of truth is `.goal/DECISIONS.md` (now through D15).
Historical root-only entries are preserved at `.goal/legacy-DECISIONS.md`.

Do not append here; split decision logs produce contradictory rationales.

## D-21 ArmoryService is the single writer of loadout state
Purchases and equips go through `ArmoryService` only; `CombatService` reads the profile and never mutates it. Rejected the alternative of letting the client tell the server "now carry weapon X" — `CombatService.equip` accepting an arbitrary id from the client is exactly how the 3000-credit ER-16 was free, so the ownership check now lives server-side next to the config lookup, and the armory selection is pushed by the server rather than requested by the client.

## Template-driven objectives instead of three services
One `ObjectiveService` dispatching on `mission.objectiveTemplate`, rather than three objective services.
Reason: the relay was already 80% of the machinery (ground snap, terminal interact, publish, complete
FX); the templates differ in **object built** and **completion rule**, not in plumbing. Three services
would triple the surface the deploy path has to keep in sync.
Consequence accepted: `complete()` gates its explosion FX on template id, so a new template must say
whether it explodes.
