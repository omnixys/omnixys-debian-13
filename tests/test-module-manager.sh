#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT_DIR/core/lib/modules.sh"

[[ -f "$LIB" ]] || { echo "module manager missing"; exit 1; }

grep -q "load_module" "$LIB"
grep -q "enable_module" "$LIB"
grep -q "disable_module" "$LIB"
grep -q "module_dependencies" "$LIB"
grep -q "module_priority" "$LIB"

echo "Module manager API test passed"
