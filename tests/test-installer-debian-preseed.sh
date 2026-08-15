#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/installer/debian-preseed"

for f in backend.sh validator.sh renderer.sh builder.sh bootloader.sh manifest.yaml; do
  [[ -f "$BACKEND_DIR/$f" ]] || { echo "missing $f"; exit 1; }
done

echo "Debian Preseed backend scaffold tests passed"
