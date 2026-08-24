#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDER="$ROOT_DIR/installer/debian-preseed/builder.sh"

[[ -f "$BUILDER" ]] || { echo "builder missing" >&2; exit 1; }

die() { echo "$*" >&2; exit 1; }
info() { :; }
step() { :; }
warn() { :; }
ensure_dir() { mkdir -p "$1"; }
run_cmd() { "$@"; }
debian_boot_params() { printf '%s\n' 'auto=true priority=critical file=/cdrom/preseed.cfg'; }

# shellcheck disable=SC1090
source "$BUILDER"

fail() { echo "$*" >&2; exit 1; }

assert_branding() {
  local version="$1" expected_label="$2"
  INSTALLER_VERSION="$version"
  debian_resolve_iso_branding
  [[ "$ISO_VOLUME_ID" == "$expected_label" ]] || fail "$version produced $ISO_VOLUME_ID, expected $expected_label"
  [[ "$BOOT_MENU_TITLE" == "Omnixys Debian Installer $version" ]] || fail "incorrect boot title for $version"
}

assert_branding 1.2.1 OMNIXYS121
assert_branding 1.2.2 OMNIXYS122
assert_branding 2.0.0 OMNIXYS200
assert_branding 1.2.1-beta.1 OMNIXYS121
assert_branding 1.2.1+build.5 OMNIXYS121

if ( INSTALLER_VERSION=foo; debian_resolve_iso_branding ) >/dev/null 2>&1; then
  fail "invalid INSTALLER_VERSION unexpectedly resolved"
fi

command -v xorriso >/dev/null 2>&1 || { echo "ISO branding tests passed (xorriso absent, artifact checks skipped)"; exit 0; }

ISO_WORK="$(mktemp -d)"
trap 'chmod -R u+w "$ISO_WORK" 2>/dev/null || true; rm -rf "$ISO_WORK"' EXIT

make_fixture_tree() {
  local dir="$1"
  mkdir -p "$dir/dists/trixie" "$dir/pool/main" "$dir/.disk" "$dir/boot/grub/theme" "$dir/isolinux"
  printf 'Suite: trixie\n' >"$dir/dists/trixie/Release"
  printf 'payload\n' >"$dir/pool/main/pkg.deb"
  printf 'Debian fixture\n' >"$dir/.disk/info"
  cat >"$dir/boot/grub/grub.cfg" <<'EOF'
menuentry 'Graphical install' {
  linux /install/vmlinuz --- quiet
}
menuentry 'Install' {
  linux /install/vmlinuz --- quiet
}
EOF
  cat >"$dir/boot/grub/theme/1" <<'EOF'
title-text: "Debian GNU/Linux 13.6.0"
+ label {text = "Debian GNU/Linux UEFI Installer menu"}
EOF
  cat >"$dir/isolinux/menu.cfg" <<'EOF'
menu title Debian GNU/Linux installer menu (BIOS mode)
EOF
  cat >"$dir/isolinux/gtk.cfg" <<'EOF'
menu label ^Graphical install
EOF
  cat >"$dir/isolinux/txt.cfg" <<'EOF'
menu label ^Install
append initrd=/install/initrd.gz --- quiet
EOF
  printf 'include menu.cfg\n' >"$dir/isolinux/isolinux.cfg"
}

make_fixture_tree "$ISO_WORK/source-tree"
( cd "$ISO_WORK/source-tree" && xorriso -as mkisofs -o "$ISO_WORK/source.iso" . ) >/dev/null 2>&1

ISO_SOURCE_PATH="$ISO_WORK/source.iso"
ISO_TREE_DIR="$ISO_WORK/tree"
ISO_OUTPUT_PATH="$ISO_WORK/final.iso"
# shellcheck disable=SC2034 # consumed by sourced builder helpers
DRY_RUN=false
# shellcheck disable=SC2034 # consumed by sourced builder helpers
ARCH=amd64
# shellcheck disable=SC2034 # consumed by sourced builder helpers
INSTALLER_VERSION=1.2.1
debian_resolve_iso_branding
debian_extract_iso_tree "$ISO_TREE_DIR"
debian_patch_boot_configs "$ISO_TREE_DIR"
xorriso -indev "$ISO_SOURCE_PATH" -outdev "$ISO_OUTPUT_PATH" -volid "$ISO_VOLUME_ID" \
  -boot_image any replay -update_r "$ISO_TREE_DIR" / -commit -end >/dev/null 2>&1

xorriso -indev "$ISO_OUTPUT_PATH" -pvd_info 2>/dev/null | grep -Eqi 'Volume id[[:space:]]*:[[:space:]]*OMNIXYS121' \
  || fail "final ISO has incorrect Volume ID"

extract_and_assert() {
  local iso_path="$1" iso_file="$2" expected="$3"
  local extracted
  extracted="$ISO_WORK/$(basename "$iso_file")"
  xorriso -osirrox on -indev "$iso_path" -extract "$iso_file" "$extracted" >/dev/null 2>&1
  grep -Fq "$expected" "$extracted" || fail "$iso_file misses: $expected"
}

extract_and_assert "$ISO_OUTPUT_PATH" /boot/grub/grub.cfg 'Install Omnixys (graphical)'
extract_and_assert "$ISO_OUTPUT_PATH" /boot/grub/grub.cfg "Install Omnixys"
extract_and_assert "$ISO_OUTPUT_PATH" /boot/grub/theme/1 'Omnixys Debian Installer 1.2.1'
extract_and_assert "$ISO_OUTPUT_PATH" /isolinux/menu.cfg 'Omnixys Debian Installer 1.2.1 (BIOS mode)'
extract_and_assert "$ISO_OUTPUT_PATH" /isolinux/gtk.cfg 'Install Omnixys (graphical)'
extract_and_assert "$ISO_OUTPUT_PATH" /isolinux/txt.cfg 'Install Omnixys'

if xorriso -osirrox on -indev "$ISO_OUTPUT_PATH" -extract /boot/grub/grub.cfg "$ISO_WORK/grub.cfg" >/dev/null 2>&1; then
  grep -Eq 'linux /install/vmlinuz auto=true priority=critical file=/cdrom/preseed\.cfg +--- quiet' "$ISO_WORK/grub.cfg" \
    || fail "GRUB installer parameters changed unexpectedly"
fi

# arm64 has no ISOLINUX or theme header. Its real UEFI path is GRUB, so verify
# the emitted title and branded entries in a separate final ISO artifact.
cp -R "$ISO_WORK/source-tree" "$ISO_WORK/arm-source-tree"
( cd "$ISO_WORK/arm-source-tree" && xorriso -as mkisofs -o "$ISO_WORK/arm-source.iso" . ) >/dev/null 2>&1

ISO_SOURCE_PATH="$ISO_WORK/arm-source.iso"
ISO_TREE_DIR="$ISO_WORK/arm-tree"
ISO_OUTPUT_PATH="$ISO_WORK/arm-final.iso"
# shellcheck disable=SC2034 # consumed by sourced builder helpers
ARCH=arm64
debian_extract_iso_tree "$ISO_TREE_DIR"
debian_patch_boot_configs "$ISO_TREE_DIR"
xorriso -indev "$ISO_SOURCE_PATH" -outdev "$ISO_OUTPUT_PATH" -volid "$ISO_VOLUME_ID" \
  -boot_image any replay -update_r "$ISO_TREE_DIR" / -commit -end >/dev/null 2>&1

xorriso -indev "$ISO_OUTPUT_PATH" -pvd_info 2>/dev/null | grep -Eqi 'Volume id[[:space:]]*:[[:space:]]*OMNIXYS121' \
  || fail "final arm64 ISO has incorrect Volume ID"
xorriso -osirrox on -indev "$ISO_OUTPUT_PATH" -extract /boot/grub/grub.cfg "$ISO_WORK/arm-grub.cfg" >/dev/null 2>&1
grep -Fq "echo 'Omnixys Debian Installer 1.2.1'" "$ISO_WORK/arm-grub.cfg" \
  || fail "arm64 GRUB misses the Omnixys title"
grep -Fq 'Install Omnixys (graphical)' "$ISO_WORK/arm-grub.cfg" \
  || fail "arm64 GRUB misses graphical Omnixys install entry"
grep -Fq "'Install Omnixys'" "$ISO_WORK/arm-grub.cfg" \
  || fail "arm64 GRUB misses text Omnixys install entry"

echo "ISO branding tests passed"
