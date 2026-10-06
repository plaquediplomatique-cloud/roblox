#!/usr/bin/env bash
# Analyse stricte de Smash Ascension (luau-lsp + définitions Roblox), 0 erreur attendue.
set -euo pipefail
cd "$(dirname "$0")/../.."
DEFS=".cache/globalTypes.d.luau"
if [[ ! -f "$DEFS" ]]; then
	mkdir -p .cache
	curl -fsSL -o "$DEFS" "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"
fi
rojo sourcemap ascension.project.json --output ascension.sourcemap.json --include-non-scripts
luau-lsp analyze \
	--sourcemap=ascension.sourcemap.json \
	--definitions=@roblox="$DEFS" \
	--base-luaurc=.luaurc \
	--formatter=plain \
	"${@:-ascension/src}"
