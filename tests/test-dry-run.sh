#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$ROOT_DIR/logs/build.log"
PRESEED="$ROOT_DIR/work/debian-preseed/generated/preseed.cfg"
PARTMAN_SCRIPT="$ROOT_DIR/work/debian-preseed/generated/omnixys-partman.sh"

chmod +x "$ROOT_DIR/build.sh"
"$ROOT_DIR/build.sh" --config "$ROOT_DIR/configs/vm.env" --dry-run

[[ -f "$LOG_FILE" ]] || { echo "missing build log"; exit 1; }
grep -q "Ready to build" "$LOG_FILE"
grep -q '^d-i partman-auto/disk string $' "$PRESEED"
grep -q "^TARGET_DISK_MODE='auto'$" "$PARTMAN_SCRIPT"
grep -q "^TARGET_DISK=''$" "$PARTMAN_SCRIPT"
grep -q "^PARTITION_MODE='erase'$" "$PARTMAN_SCRIPT"
grep -q '^d-i partman/early_command string sh /cdrom/omnixys-partman.sh$' "$PRESEED"

echo "Dry-run readiness test passed"
