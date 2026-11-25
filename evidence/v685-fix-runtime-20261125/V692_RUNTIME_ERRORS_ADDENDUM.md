# v692 runtime-error addendum — 2026-11-25

## Deployment

v692 deployed all **125/125** mirror scripts with zero compile failures and saved as cloud version **692**. Raw log: `raw/deploy_v692_runtime_errors.log`.

## Runtime errors fixed

1. `StationWarTable.start` called `buildHologram` before the local function definition executed. Added a forward declaration and assigned the function later. Console now shows: `[GF] war table: crew, intel screens and squad slots online`.
2. Bastion Walker sweeping cannon delayed pulses could outlive the boss or its PrimaryPart. The pulse loop now breaks when the model/part is gone. The previous repeating `BastionWalker:398 attempt to index nil with 'Position'` error is absent from the fresh console tail.

Evidence: `raw/v692_console_tail.txt`.

## Important harness discovery

Directly requiring server modules from MCP `execute_script` does not reliably share the live game module state. A damage harness using that path returned `State.get(player)=nil` even though the live game itself was publishing vitals correctly. Future server-state verification must use real remotes, natural gameplay, workspace attributes, or explicit in-game instrumentation rather than assuming command-bar module state is authoritative.
