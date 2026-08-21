#!/usr/bin/env bash
# shellcheck disable=SC2034 # renderer globals are consumed by sourced functions
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDERER="$ROOT_DIR/installer/debian-preseed/renderer.sh"

die() { echo "die: $*" >&2; exit 1; }
# shellcheck disable=SC1090
source "$RENDERER"

assert_recipe() {
  local firmware="$1"
  local filesystem="$2"
  local recipe preseed
  FILESYSTEM="$filesystem"
  recipe="$(debian_compose_expert_recipe "$firmware")"
  preseed="$(debian_compose_expert_recipe_preseed "$firmware")"

  grep -q '^omnixys-erase ::$' <<<"$recipe"
  grep -q "filesystem{ $filesystem }" <<<"$recipe"
  grep -q 'mountpoint{ / }' <<<"$recipe"
  grep -q 'linux-swap' <<<"$recipe"
  [[ "$(grep -cE '[.]$' <<<"$recipe")" -eq 3 ]]
  grep -q '^d-i partman-auto/expert_recipe string \\$' <<<"$preseed"
  [[ "$(grep -cE '\\$' <<<"$preseed")" -eq "$(($(wc -l <<<"$preseed") - 1))" ]]
  grep -qE '[.]$' <<<"$preseed"

  case "$firmware" in
    uefi)
      grep -q 'method{ efi }' <<<"$recipe"
      grep -q 'mountpoint{ /boot/efi }' <<<"$recipe"
      ! grep -q 'method{ biosgrub }' <<<"$recipe"
      ;;
    bios)
      grep -q 'method{ biosgrub }' <<<"$recipe"
      ! grep -q 'method{ efi }' <<<"$recipe"
      ;;
  esac
}

for filesystem in ext4 xfs btrfs; do
  assert_recipe bios "$filesystem"
  assert_recipe uefi "$filesystem"
done

FILESYSTEM=ext4
PARTITION_MODE=lvm
debian_partition_mode_values
[[ "$PARTMAN_METHOD" == "lvm" ]]
[[ "$PARTMAN_RECIPE_DIRECTIVE" == "d-i partman-auto/choose_recipe select atomic" ]]

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
HOSTNAME='recipe-test'
DOMAIN=example.invalid
FULLNAME='Recipe Test'
USERNAME=recipe
PASSWORD_HASH='!'
LANGUAGE=en
COUNTRY=DE
LOCALE=en_US.UTF-8
KEYBOARD=de
TIMEZONE=Europe/Berlin
RESOLVED_TARGET_DISK=''
PRESEED_EARLY_COMMAND='sh /cdrom/omnixys-early.sh'
PARTMAN_EARLY_COMMAND='sh /cdrom/omnixys-partman.sh'
APT_MIRROR=deb.debian.org
SSH_PUBLIC_KEY=''
SSH_PASSWORD_AUTH=false
SSH_PERMIT_ROOT_LOGIN=no
INSTALL_OPENSSH=true
INSTALL_STANDARD_UTILITIES=true
TASKSEL_FIRST=standard
PKGSEL_INCLUDE=openssh-server
PKGSEL_UPGRADE=none
ANNA_MODULES=''
LATE_COMMAND=true
FINISH_ACTION='d-i debian-installer/exit/halt boolean true'

PARTITION_MODE=erase
FILESYSTEM=xfs
debian_partition_mode_values
debian_render_template "$ROOT_DIR/templates/debian-preseed.cfg.template" "$SANDBOX/erase.cfg"
grep -q '^d-i partman/early_command string sh /cdrom/omnixys-partman.sh$' "$SANDBOX/erase.cfg"
grep -q '^d-i partman-auto/expert_recipe string \\$' "$SANDBOX/erase.cfg"
grep -q 'filesystem{ xfs }' "$SANDBOX/erase.cfg"
if grep -q 'partman-auto/choose_recipe' "$SANDBOX/erase.cfg"; then
  echo "erase preseed unexpectedly selects a built-in recipe"
  exit 1
fi
if grep -Eq '__[A-Z0-9_]+__' "$SANDBOX/erase.cfg"; then
  echo "erase preseed contains unresolved placeholders"
  exit 1
fi

PARTITION_MODE=lvm
FILESYSTEM=ext4
debian_partition_mode_values
debian_render_template "$ROOT_DIR/templates/debian-preseed.cfg.template" "$SANDBOX/lvm.cfg"
grep -q '^d-i partman-auto/choose_recipe select atomic$' "$SANDBOX/lvm.cfg"
if grep -q 'partman-auto/expert_recipe' "$SANDBOX/lvm.cfg"; then
  echo "LVM preseed unexpectedly contains an expert recipe"
  exit 1
fi
if grep -Eq '__[A-Z0-9_]+__' "$SANDBOX/lvm.cfg"; then
  echo "LVM preseed contains unresolved placeholders"
  exit 1
fi

echo "Partman recipe tests passed"
