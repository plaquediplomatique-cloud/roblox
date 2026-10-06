#!/usr/bin/env bash
# Analyse statique stricte de tout le code Luau avec les vraies définitions de l'API Roblox.
#   1. génère sourcemap.json (Rojo) pour que luau-lsp résolve les require(script.Parent.X)
#   2. lance luau-lsp analyze en mode strict (cf. .luaurc)
# Usage : ./scripts/analyze.sh [chemins...]   (défaut : src)
set -euo pipefail
cd "$(dirname "$0")/.."

DEFS=".cache/globalTypes.d.luau"
DEFS_URL="https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"

if [[ ! -f "$DEFS" ]]; then
	mkdir -p .cache
	echo "[analyze] téléchargement des définitions Roblox…"
	curl -fsSL -o "$DEFS" "$DEFS_URL"
fi

rojo sourcemap default.project.json --output sourcemap.json --include-non-scripts

TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then
	TARGETS=(src)
fi

luau-lsp analyze \
	--sourcemap=sourcemap.json \
	--definitions=@roblox="$DEFS" \
	--base-luaurc=.luaurc \
	--formatter=plain \
	"${TARGETS[@]}"
