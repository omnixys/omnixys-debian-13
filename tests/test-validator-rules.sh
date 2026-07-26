#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT_DIR/installer/debian-preseed/validator.sh"

[[ -f "$VALIDATOR" ]] || { echo "validator missing"; exit 1; }

grep -q "PASSWORD must be at least 12 characters" "$VALIDATOR"
grep -q "Unsupported ARCH" "$VALIDATOR"
grep -q "Invalid LOCALE" "$VALIDATOR"
grep -q "APT_MIRROR" "$VALIDATOR"
grep -q "Unsupported IDENTITY_SOURCE" "$VALIDATOR"

echo "Validator rules presence test passed"
