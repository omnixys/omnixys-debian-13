#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDER="$ROOT_DIR/installer/debian-preseed/builder.sh"

[[ -f "$BUILDER" ]] || { echo "builder missing"; exit 1; }

grep -q "debian_detect_bootloader_files" "$BUILDER"
grep -q "xorriso" "$BUILDER"
grep -q "boot/grub/grub.cfg" "$BUILDER"
grep -q "isolinux/txt.cfg" "$BUILDER"

echo "Builder remaster test passed"
