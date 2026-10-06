#!/usr/bin/env bash
# Tests unitaires de Smash Ascension (logique pure, hors moteur, avec Lune).
set -euo pipefail
cd "$(dirname "$0")/../.."
lune run ascension/tests/run.luau
