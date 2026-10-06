#!/usr/bin/env bash
# Tests unitaires (Lune) de la logique pure de Hatchlings.
set -euo pipefail
cd "$(dirname "$0")/.."
lune run tests/run.luau
