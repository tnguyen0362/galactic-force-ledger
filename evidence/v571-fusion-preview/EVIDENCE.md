# place 571 — fusion preview evidence

A temporary real server `Script` created three Rare/AR `MatchTrigger` copies and three Legendary `SiegeChamber` copies, then exercised `AugmentService.fusionPreview` and `AugmentService.fuse`. All test items were removed afterward.

```text
[GF] boot: config check PASS (688 assertions)
[GF_FUSETEST] PASS preview=Rare->Epic outcomes=1 previewNoConsume=true legendaryRejected=Legendary augments cannot fuse protectedRejected=true result=LongBarrel
[GF_FUSECLEAN] removed=4
```

Verified: preview reports source/target rarity and possible outcomes without consuming inputs; Legendary fusion is rejected; a favorited input is rejected; confirmed fusion consumes three valid inputs and grants a direct Epic AR result.

The Armory FUSE button now requests a preview first and shows a CONFIRM/CANCEL row with outcome chances. UI click-path evidence is still pending.
