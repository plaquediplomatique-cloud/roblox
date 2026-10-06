#!/usr/bin/env bash
# Construit build/Hatchlings.rbxl (ouvrir dans Studio) — ou `rojo serve` pour la synchro live.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
rojo build default.project.json --output build/Hatchlings.rbxl
echo "[build] build/Hatchlings.rbxl prêt"
