#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT_DIR/installer/debian-preseed/validator.sh"

[[ -f "$VALIDATOR" ]] || { echo "validator missing"; exit 1; }

grep -q "debian_validate_password()" "$VALIDATOR"
grep -q "Unsupported ARCH" "$VALIDATOR"
grep -q "Invalid LOCALE" "$VALIDATOR"
grep -q "APT_MIRROR" "$VALIDATOR"
grep -q "Unsupported IDENTITY_SOURCE" "$VALIDATOR"
grep -q "IDENTITY_FILE_PATH must start with /: " "$VALIDATOR"
grep -q "IDENTITY_DEVICE_LABEL must not be empty when IDENTITY_SOURCE=usb-env" "$VALIDATOR"

echo "Validator rules presence test passed"
