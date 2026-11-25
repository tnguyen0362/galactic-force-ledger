# place 570 — bulk dismantle evidence

A temporary real server `Script` created two Common/Universal `StabilityCompensator` test copies, favorited one, ran `dismantleCandidates(profile,"Common","Universal")`, dismantled the preview UID set, then removed the remaining test item and reset test scrap.

```text
[GF_BULKTEST] PASS previewCount=2 skipped=2 scrap=16 favoriteProtected=true
[GF_BULKCLEAN] removed=1 scrap=0
[GF] boot: config check PASS (688 assertions)
```

The preview count includes pre-existing Common/Universal inventory entries, so it is larger than the two test copies. The important verified behavior is that the preview reports count/scrap/protected skips, dismantling uses the server-computed UID set rather than client-supplied IDs, exact rarity scrap is paid, and favorited items survive.

The Armory now has rarity and category filter buttons, a PREVIEW action, exact `count · scrap · protected` text, and a separate CONFIRM button. The UI compile-checks, but its click path still needs visual/client inspection evidence.
