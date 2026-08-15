#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$ROOT_DIR/logs/build.log"

chmod +x "$ROOT_DIR/build.sh"
"$ROOT_DIR/build.sh" --config "$ROOT_DIR/configs/vm.env" --dry-run

[[ -f "$LOG_FILE" ]] || { echo "missing build log"; exit 1; }
grep -q "Ready to build" "$LOG_FILE"

echo "Dry-run readiness test passed"
