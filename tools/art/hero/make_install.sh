#!/bin/sh
# usage: make_install.sh <assetId> [TemplateName=Hero_Asc_Rifleman] [dataFile=rifleman_data.luau] [artSource]
#   -> install_<TemplateName>.luau (paste into execute_luau, Edit DM). Rifleman default also writes install_rifleman.luau.
cd "$(dirname "$0")"
NAME="${2:-Hero_Asc_Rifleman}"
DATAFILE="${3:-rifleman_data.luau}"
SHORT="${NAME#Hero_Asc_}"
SRC="${4:-Blender squad v12 $SHORT (R15-width body, scaled helmet) + baked PBR atlas (BC/N/RM)}"
DATA=$(sed 's/^return {/local DATA = {/' "$DATAFILE")
OUT="install_${NAME}.luau"
awk -v id="$1" -v data="$DATA" -v name="$NAME" -v src="$SRC" '{ if ($0=="__DATA__") print data; else { gsub("__ASSET_ID__", id); gsub("__ART_SOURCE__", src); gsub("Hero_Asc_Rifleman", name); print } }' install_rifleman.tmpl.luau > "$OUT"
[ "$NAME" = "Hero_Asc_Rifleman" ] && cp "$OUT" install_rifleman.luau
echo wrote "$OUT"
