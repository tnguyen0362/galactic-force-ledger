#!/bin/sh
# usage: make_install_player.sh <assetId>  -> install_player_kit.luau (paste into execute_luau, Edit DM)
cd "$(dirname "$0")"
DATA=$(sed 's/^return {/local DATA = {/' player_kit_data.luau)
awk -v id="$1" -v data="$DATA" '{ if ($0=="__DATA__") print data; else { gsub("__ASSET_ID__", id); print } }' install_player_kit.tmpl.luau > install_player_kit.luau
echo wrote install_player_kit.luau
