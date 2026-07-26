#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for mod in core ssh docker tailscale ansible k3s custom; do
  [[ -f "$ROOT_DIR/modules/$mod/manifest.yaml" ]] || { echo "missing manifest for $mod"; exit 1; }
  [[ -f "$ROOT_DIR/modules/$mod/module.sh" ]] || { echo "missing module script for $mod"; exit 1; }
done

echo "Module scaffold tests passed"
