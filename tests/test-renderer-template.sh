#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT_DIR/templates/debian-preseed.cfg.template"
RENDERER="$ROOT_DIR/installer/debian-preseed/renderer.sh"
VM_CONFIG="$ROOT_DIR/configs/vm.env"

[[ -f "$TEMPLATE" ]] || { echo "template missing"; exit 1; }
[[ -f "$RENDERER" ]] || { echo "renderer missing"; exit 1; }
[[ -f "$VM_CONFIG" ]] || { echo "VM config missing"; exit 1; }

grep -q "__PASSWORD_HASH__" "$TEMPLATE"
grep -q "__PRESEED_EARLY_COMMAND__" "$TEMPLATE"
grep -q "__PARTMAN_EARLY_COMMAND__" "$TEMPLATE"
grep -q "__PARTMAN_METHOD__" "$TEMPLATE"
grep -q "__PARTMAN_RECIPE_DIRECTIVE__" "$TEMPLATE"
grep -q "__TASKSEL_FIRST__" "$TEMPLATE"
grep -q "__LATE_COMMAND__" "$TEMPLATE"
grep -q "grub-installer/bootdev string __TARGET_DISK__" "$TEMPLATE"

grep -q "sh /cdrom/omnixys-early.sh" "$RENDERER"
grep -q "sh /cdrom/omnixys-partman.sh" "$RENDERER"
grep -q "debian_render_partman_script" "$RENDERER"
grep -q "method{ biosgrub }" "$RENDERER"
grep -q "method{ efi }" "$RENDERER"
if grep -q "omnixys-disk-detect.sh" "$RENDERER"; then
  echo "legacy disk-detect renderer is still present"
  exit 1
fi
if grep -q 'RESOLVED_TARGET_DISK="/dev/sda"' "$RENDERER"; then
  echo "unsafe automatic bootstrap disk is still present"
  exit 1
fi

grep -q '^TARGET_DISK_MODE=manual$' "$VM_CONFIG"
grep -q '^TARGET_DISK=/dev/vda$' "$VM_CONFIG"
grep -q '^PARTITION_MODE=erase$' "$VM_CONFIG"

echo "Renderer template placeholders test passed"
