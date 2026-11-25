# v598 — mission lifecycle deep probe (spine3)

`[GF_SPINE3] PASS defenseCountdown=4 shipModel=true enemiesAliveAtExtract=5 aboard=false extractionState=idle missionTime=12.4s`

- Full phase sequence live: deploy -> in-mission active -> primary complete -> evac requested -> defense
  countdown publishing -> ship landed (visible dropship model in workspace) -> settlement.
- S09-006 behavioral proof: extraction completed with 5 enemies still alive - no kill-all requirement.
- GF_ExtractionState machine attribute exists (idle state observed post-settlement).
- aboard=false is a probe-geometry artifact (cabin volume checks); aboard mechanics covered by v582 evidence.
- Mission time 12.4s is probe-paced with objective completion forced and a 4s countdown override; it is NOT
  evidence about the authored 10-15min pacing target (S08-004) which needs a naturalistic full clear.
