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
grep -q "debian_validate_network_config()" "$VALIDATOR"
grep -q "debian_validate_installer_version()" "$VALIDATOR"

bash -c '
  die() { echo "$*" >&2; exit 1; }
  source "$1"
  NETWORK_INTERFACE=""
  STATIC_IP=""
  STATIC_ROUTERS=""
  STATIC_DNS=""
  debian_validate_network_config
' _ "$VALIDATOR"

bash -c '
  die() { echo "$*" >&2; exit 1; }
  source "$1"
  NETWORK_INTERFACE=enp1s0
  STATIC_IP=192.168.2.103/24
  STATIC_ROUTERS=192.168.2.1
  STATIC_DNS="192.168.2.1 1.1.1.1"
  debian_validate_network_config
' _ "$VALIDATOR"

if bash -c '
  die() { echo "$*" >&2; exit 1; }
  source "$1"
  NETWORK_INTERFACE=enp1s0
  STATIC_IP=192.168.2.103/24
  STATIC_ROUTERS=""
  STATIC_DNS=1.1.1.1
  debian_validate_network_config
' _ "$VALIDATOR" >/dev/null 2>&1; then
  echo "partial static network configuration unexpectedly validated" >&2
  exit 1
fi

for version in 1.2.1 1.2.1-beta.1 1.2.1+build.5; do
  bash -c '
    die() { echo "$*" >&2; exit 1; }
    source "$1"
    INSTALLER_VERSION="$2"
    debian_validate_installer_version
  ' _ "$VALIDATOR" "$version"
done

if bash -c '
  die() { echo "$*" >&2; exit 1; }
  source "$1"
  INSTALLER_VERSION=foo
  debian_validate_installer_version
' _ "$VALIDATOR" >/dev/null 2>&1; then
  echo "invalid INSTALLER_VERSION unexpectedly validated" >&2
  exit 1
fi

echo "Validator rules presence test passed"
