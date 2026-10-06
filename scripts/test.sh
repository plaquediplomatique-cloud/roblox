#!/usr/bin/env bash
# Tests unitaires de la logique pure (maths de hitbox, spread déterministe, balistique,
# springs, rate-limiter, validation réseau, MMR/rangs, algorithme de matchmaking, règles de round).
# Exécutés hors Roblox avec Lune (https://lune-org.github.io/docs), qui fournit les types
# Roblox (Vector3, CFrame, Color3…) via @lune/roblox.
set -euo pipefail
cd "$(dirname "$0")/.."
lune run tests/run.luau
