# Debrief rank-up flourish (build 440)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## What was missing
`S09-041` asks for an XP rank-up animation in the debrief. The payload carried `rankUps` and nothing ever moved — the row printed a static line, if anything.

## Implemented
- `MissionHUD` debrief gained a rank-up label that appears when `rankUps > 0`, tweens its text size from 14 to 22 with a Back easing curve over 0.35 s, holds for 2.6 s, then fades out over 0.5 s and hides. It records `GF_RankUpPlayed` on the debrief frame.
- `RewardsService` respects `GF_ForceRankUps` so the branch can be exercised without grinding twenty levels.

## Measured
| Run | Label |
|---|---|
| Forced 2 rank-ups | first attempt printed **`RANK UP 11 → 15 (x2)`** — wrong |
| After fixing the arithmetic | **`RANK UP 13 → 15 (x2)`** |

The first version subtracted the delta twice: `fromRank` was already computed as `rank - rankUps`, and the formatter then subtracted `count` again. Both the label and the debrief text showed the mistake, which is exactly why it was worth reading the rendered string rather than trusting the code.

The debrief also rendered the salvage bonus line introduced at build 439: `Salvage bonus  +0 scrap  +0 cells  +0 tech` (zeros, because the run was solo).

## Limits
- **The animation itself was not observed** — only the label text and visibility at one instant. The grow/fade tweens and the 2.6 s hold are code, not evidence.
- Rank-ups were forced with a test attribute; no run earned a real threshold crossing.
- The multi-rank format (`x2`) has never corresponded to a real multi-level gain.
