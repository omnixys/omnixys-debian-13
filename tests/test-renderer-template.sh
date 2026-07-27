#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT_DIR/templates/debian-preseed.cfg.template"
RENDERER="$ROOT_DIR/installer/debian-preseed/renderer.sh"

[[ -f "$TEMPLATE" ]] || { echo "template missing"; exit 1; }
[[ -f "$RENDERER" ]] || { echo "renderer missing"; exit 1; }

grep -q "__PASSWORD_HASH__" "$TEMPLATE"
grep -q "__PRESEED_EARLY_COMMAND__" "$TEMPLATE"
grep -q "__PARTMAN_METHOD__" "$TEMPLATE"
grep -q "__TASKSEL_FIRST__" "$TEMPLATE"
grep -q "__LATE_COMMAND__" "$TEMPLATE"
grep -q "grub-installer/bootdev string __TARGET_DISK__" "$TEMPLATE"

grep -q "sh /cdrom/omnixys-early.sh" "$RENDERER"
grep -q "set -x" "$RENDERER"
grep -q "exec >/var/log/omnixys-disk-detect.log 2>&1" "$RENDERER"

echo "Renderer template placeholders test passed"
