#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT_DIR/templates/debian-preseed.cfg.template"

[[ -f "$TEMPLATE" ]] || { echo "template missing"; exit 1; }

grep -q "__PASSWORD_HASH__" "$TEMPLATE"
grep -q "__PRESEED_EARLY_COMMAND__" "$TEMPLATE"
grep -q "__PARTMAN_METHOD__" "$TEMPLATE"
grep -q "__TASKSEL_FIRST__" "$TEMPLATE"
grep -q "__LATE_COMMAND__" "$TEMPLATE"

echo "Renderer template placeholders test passed"
