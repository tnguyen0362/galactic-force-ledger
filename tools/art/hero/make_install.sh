#!/bin/sh
# usage: make_install.sh <assetId>  -> install_rifleman.luau (paste into execute_luau, Edit DM)
cd "$(dirname "$0")"
DATA=$(sed 's/^return {/local DATA = {/' rifleman_data.luau)
awk -v id="$1" -v data="$DATA" '{ if ($0=="__DATA__") print data; else { gsub("__ASSET_ID__", id); print } }' install_rifleman.tmpl.luau > install_rifleman.luau
echo wrote install_rifleman.luau
