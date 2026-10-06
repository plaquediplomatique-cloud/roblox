#!/usr/bin/env bash
# Analyse statique stricte (luau-lsp + définitions Roblox). Usage : ./scripts/analyze.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DEFS=".cache/globalTypes.d.luau"
if [[ ! -f "$DEFS" ]]; then
	mkdir -p .cache
	curl -fsSL -o "$DEFS" "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"
fi
rojo sourcemap default.project.json --output sourcemap.json --include-non-scripts
luau-lsp analyze --sourcemap=sourcemap.json --definitions=@roblox="$DEFS" --base-luaurc=.luaurc --formatter=plain src
