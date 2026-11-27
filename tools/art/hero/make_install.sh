#!/bin/sh
# usage: make_install.sh <assetId> [TemplateName=Hero_Asc_Rifleman] [dataFile=rifleman_data.luau]
#   -> install_<TemplateName>.luau (paste into execute_luau, Edit DM). Rifleman default also writes install_rifleman.luau.
cd "$(dirname "$0")"
NAME="${2:-Hero_Asc_Rifleman}"
DATAFILE="${3:-rifleman_data.luau}"
DATA=$(sed 's/^return {/local DATA = {/' "$DATAFILE")
OUT="install_${NAME}.luau"
awk -v id="$1" -v data="$DATA" -v name="$NAME" '{ if ($0=="__DATA__") print data; else { gsub("__ASSET_ID__", id); gsub("Hero_Asc_Rifleman", name); print } }' install_rifleman.tmpl.luau > "$OUT"
[ "$NAME" = "Hero_Asc_Rifleman" ] && cp "$OUT" install_rifleman.luau
echo wrote "$OUT"
