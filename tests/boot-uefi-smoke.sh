#!/usr/bin/env bash
set -Eeuo pipefail

ISO_PATH="${1:-}"
OVMF_CODE="${2:-/usr/share/OVMF/OVMF_CODE.fd}"
OUT_DIR="${3:-./artifacts/boot-tests}"

[[ -n "$ISO_PATH" ]] || { echo "usage: $0 <iso-path> [ovmf-code] [out-dir]"; exit 1; }
[[ -f "$ISO_PATH" ]] || { echo "iso not found: $ISO_PATH"; exit 1; }
[[ -f "$OVMF_CODE" ]] || { echo "ovmf not found: $OVMF_CODE"; exit 1; }

mkdir -p "$OUT_DIR"
cp "$OVMF_CODE" "$OUT_DIR/OVMF_CODE.fd"
truncate -s 64M "$OUT_DIR/OVMF_VARS.fd"
LOG="$OUT_DIR/uefi-boot.log"

set +e
timeout 60 qemu-system-x86_64 -m 2048 -cdrom "$ISO_PATH" -boot d -nographic -serial file:"$LOG" -monitor none -no-reboot \
  -drive if=pflash,format=raw,readonly=on,file="$OUT_DIR/OVMF_CODE.fd" \
  -drive if=pflash,format=raw,file="$OUT_DIR/OVMF_VARS.fd"
rc=$?
set -e

if [[ "$rc" -eq 124 ]]; then
  echo "UEFI boot smoke passed (VM stayed running for timeout window)"
  exit 0
fi

echo "UEFI boot smoke failed (exit code: $rc)"
exit 1
