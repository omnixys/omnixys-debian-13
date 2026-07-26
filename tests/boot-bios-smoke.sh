#!/usr/bin/env bash
set -Eeuo pipefail

ISO_PATH="${1:-}"
OUT_DIR="${2:-./artifacts/boot-tests}"

[[ -n "$ISO_PATH" ]] || { echo "usage: $0 <iso-path> [out-dir]"; exit 1; }
[[ -f "$ISO_PATH" ]] || { echo "iso not found: $ISO_PATH"; exit 1; }

mkdir -p "$OUT_DIR"
LOG="$OUT_DIR/bios-boot.log"

set +e
timeout 60 qemu-system-x86_64 -m 2048 -cdrom "$ISO_PATH" -boot d -nographic -serial file:"$LOG" -monitor none -no-reboot
rc=$?
set -e

if [[ "$rc" -eq 124 ]]; then
  echo "BIOS boot smoke passed (VM stayed running for timeout window)"
  exit 0
fi

echo "BIOS boot smoke failed (exit code: $rc)"
exit 1
