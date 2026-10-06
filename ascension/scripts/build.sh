#!/usr/bin/env bash
# Construit build/SmashAscension.rbxl (ouvrir dans Studio) depuis le projet Rojo.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build
rojo build ascension.project.json --output build/SmashAscension.rbxl
echo "[build] build/SmashAscension.rbxl prêt"
