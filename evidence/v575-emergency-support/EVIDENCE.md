# place 575 — emergency withdrawal disables support

Changes in `AbilityService`:
- `cast` rejects every ability while `GF_EmergencyExtraction` is true (`"emergency withdrawal: support disabled"`).
- Airstrike and Orbital Strike re-check the emergency state at landing time (`cancelForEmergency`). An unlanded strike is cancelled with rejection feedback and `GF_LastStrikeCancelled`.
- Bug fix: `reportReject` was a `local function` declared after `airstrike`/`orbital`, so an out-of-range Airstrike or Orbital Strike called a nil global and errored instead of giving feedback. It is now declared before them.

Probe (temporary real-server Script):

```text
[GF] boot: config check PASS (688 assertions)
[GF_EMERG] PASS farOk=true far=out of range emergency=emergency withdrawal: support disabled domes=0 cancelled=Airstrike:ROBLOXISUS101
```

An already-placed dome or sentry is untouched and expires naturally, as GOAL allows. Not verified: the client-side display of the rejection feedback.
