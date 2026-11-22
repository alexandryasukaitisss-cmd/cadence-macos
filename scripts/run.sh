#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build_app.sh"
open "${CADENCE_APP_DIR:-$ROOT/build/Cadence.app}"
