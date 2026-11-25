# v605 — downed crawl + lockout verification

Spec deviation fixed: downed players were frozen at WalkSpeed 0; spec requires 5 studs/s crawl.

`[GF_DOWN] PASS crawlSpeed=5 fireAmmoWhileDowned=28 bleedoutTimeout=60`
- WalkSpeed exactly 5 while downed (crawl), JumpPower 0, bleedout timer (downedAt) started.
- Fire server-rejected while downed: ammo untouched (28).
- Bleedout timeout constant verified 60s per spec; solo-redeploy and bleedout branches read it.
- Revive restores movement and half shield/health.
