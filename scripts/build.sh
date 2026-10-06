#!/usr/bin/env bash
# Construit la place jouable (build/AetherStrike.rbxl) à partir du projet Rojo.
# Ouvrir ensuite le fichier dans Roblox Studio, ou utiliser `rojo serve` pour la synchro live.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
rojo build default.project.json --output build/AetherStrike.rbxl
echo "[build] build/AetherStrike.rbxl prêt"
