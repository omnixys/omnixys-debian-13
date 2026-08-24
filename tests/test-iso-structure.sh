#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2181
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDER="$ROOT_DIR/installer/debian-preseed/builder.sh"
[[ -f "$BUILDER" ]] || { echo "builder missing"; exit 1; }

# --- Stub core helpers so builder.sh functions can be unit tested in isolation
# The real die exits the process; this stub records every message so negative
# scenarios can assert that the relevant reason was produced, even though the
# gated code path keeps running after a stubbed die.
DIE_FIRED=0
DIE_MSG=""
die() { DIE_FIRED=$((DIE_FIRED + 1)); DIE_MSG="$DIE_MSG | $*"; return 1; }
info() { :; }
step() { :; }
warn() { :; }
ensure_dir() { mkdir -p "$1"; }
run_cmd() { "$@"; }

# shellcheck disable=SC1090
source "$BUILDER"

fail() { echo "$1" >&2; exit 1; }

# --- 1. Structural presence in builder.sh --------------------------------------
grep -q 'debian_iso_listing()' "$BUILDER" || fail "debian_iso_listing is missing"
grep -q 'debian_tree_listing()' "$BUILDER" || fail "debian_tree_listing is missing"
grep -q 'debian_verify_work_tree_completeness()' "$BUILDER" \
  || fail "work tree completeness guard is missing"
grep -q 'debian_verify_iso_structure()' "$BUILDER" || fail "debian_verify_iso_structure is missing"
grep -qF -e '-indev "$ISO_SOURCE_PATH"' "$BUILDER" \
  || fail "package step must read the source ISO (-indev)"
grep -qF -e '-outdev "$ISO_OUTPUT_PATH"' "$BUILDER" \
  || fail "package step must write a fresh output ISO (-outdev)"
grep -q 'boot_image any replay' "$BUILDER" || fail "boot image replay is missing"
grep -q 'debian_verify_iso_structure' "$BUILDER" \
  || fail "structure verification is never invoked"
# The completeness guard must run before the remaster write pass.
guard_line="$(grep -nE '^[[:space:]]*debian_verify_work_tree_completeness[[:space:]]*$' "$BUILDER" | head -1 | cut -d: -f1)"
outdev_line="$(grep -nF -e '-outdev "$ISO_OUTPUT_PATH"' "$BUILDER" | head -1 | cut -d: -f1)"
if [[ -z "$guard_line" || -z "$outdev_line" || "$guard_line" -ge "$outdev_line" ]]; then
  fail "completeness guard must run before the cross-image remaster write"
fi

# --- 2. Behavioral checks (require xorriso) ------------------------------------
# Skipped when xorriso is absent (covered in CI via the test-installer job).
command -v xorriso >/dev/null 2>&1 || { echo "Builder ISO structure tests passed (xorriso absent, behavior skipped)"; exit 0; }

ISO_WORK="$(mktemp -d)"
trap 'rm -rf "$ISO_WORK"' EXIT

export DRY_RUN=false

make_fixture_tree() {
  local dir="$1"
  mkdir -p "$dir/dists/trixie" "$dir/pool/main" "$dir/.disk" "$dir/boot/grub" "$dir/docs"
  printf 'Suite: trixie\n' >"$dir/dists/trixie/Release"
  printf 'dummy package payload\n' >"$dir/pool/main/pkg.deb"
  printf 'Debian GNU/Linux testing\n' >"$dir/.disk/info"
  printf 'set timeout=5\n' >"$dir/boot/grub/grub.cfg"
  printf 'installer documentation\n' >"$dir/docs/readme.txt"
}

inject_omnixys_files() {
  local dir="$1"
  printf 'preseed\n' >"$dir/preseed.cfg"
  printf 'info\n' >"$dir/omnixys-installer-info.txt"
  printf '#!/bin/sh\necho early\n' >"$dir/omnixys-early.sh"
  printf '#!/bin/sh\necho partman\n' >"$dir/omnixys-partman.sh"
  printf '#!/bin/sh\necho late\n' >"$dir/omnixys-network-late.sh"
  printf 'templates\n' >"$dir/omnixys-identity.templates"
}

repack_copy_then_grow() {
  local tree="$1" out="$2"
  rm -f "$out"
  # Cross-image remaster mirroring the exact command shape of debian_package.
  xorriso -indev "$3" -outdev "$out" -boot_image any replay \
    -update_r "$tree" / -commit -end >/dev/null 2>&1
}

assert_listing_contains() {
  local iso="$1" path="$2" msg="$3"
  debian_iso_listing "$iso" | grep -Fxq "$path" || fail "$msg ($path not in $(basename "$iso"))"
}

# --- T1: roundtrip keeps every source path and passes the gate -----------------
make_fixture_tree "$ISO_WORK/src"
( cd "$ISO_WORK/src" && xorriso -as mkisofs -o "$ISO_WORK/source.iso" . ) >/dev/null 2>&1

export ISO_SOURCE_PATH="$ISO_WORK/source.iso"
export ISO_OUTPUT_PATH="$ISO_WORK/final.iso"

debian_extract_iso_tree "$ISO_WORK/tree"
inject_omnixys_files "$ISO_WORK/tree"
repack_copy_then_grow "$ISO_WORK/tree" "$ISO_OUTPUT_PATH" "$ISO_SOURCE_PATH"

DIE_FIRED=0
DIE_MSG=""
set +e
debian_verify_iso_structure
rc=$?
set -e
[[ $rc -eq 0 && $DIE_FIRED -eq 0 ]] || fail "gate rejected a complete remaster: $DIE_MSG"

comm -23 <(debian_iso_listing "$ISO_SOURCE_PATH") <(debian_iso_listing "$ISO_OUTPUT_PATH") >"$ISO_WORK/missing.txt"
[[ ! -s "$ISO_WORK/missing.txt" ]] || fail "roundtrip lost source content: $(paste -sd' ' "$ISO_WORK/missing.txt")"
for path in /dists/trixie/Release /pool/main/pkg.deb /.disk/info /boot/grub/grub.cfg /docs/readme.txt /preseed.cfg /omnixys-early.sh /omnixys-partman.sh /omnixys-network-late.sh /omnixys-identity.templates /omnixys-installer-info.txt; do
  assert_listing_contains "$ISO_OUTPUT_PATH" "$path" "roundtrip dropped path"
done

# --- T2: incomplete work tree must abort the remaster loudly --------------------
# xorriso -update_r mirrors the tree: ISO objects without a disk counterpart
# are deleted from the image. A file vanishing between extract and update must
# therefore make the completeness guard fail the build BEFORE any update.
export ISO_TREE_DIR="$ISO_WORK/tree"
rm "$ISO_TREE_DIR/docs/readme.txt"

DIE_FIRED=0
DIE_MSG=""
set +e
debian_verify_work_tree_completeness 2>/dev/null
set -e
[[ $DIE_FIRED -ge 1 ]] || fail "completeness guard accepted a tree missing source paths"
grep -q '/docs/readme.txt' <<<"$DIE_MSG" \
  || fail "guard failure does not name the missing path: $DIE_MSG"

# Restore the tree; the guard must pass again afterwards.
printf 'installer documentation\n' >"$ISO_TREE_DIR/docs/readme.txt"
DIE_FIRED=0
set +e
debian_verify_work_tree_completeness 2>/dev/null
set -e
[[ $DIE_FIRED -eq 0 ]] || fail "completeness guard rejected the restored complete tree: $DIE_MSG"

# --- T3: source lacking the repository layout must be rejected ------------------
mkdir -p "$ISO_WORK/broken-src/pool/main" "$ISO_WORK/broken-src/.disk" "$ISO_WORK/broken-src/boot/grub"
printf 'dummy\n' >"$ISO_WORK/broken-src/pool/main/pkg.deb"
printf 'marker\n' >"$ISO_WORK/broken-src/.disk/info"
printf 'set timeout=5\n' >"$ISO_WORK/broken-src/boot/grub/grub.cfg"
( cd "$ISO_WORK/broken-src" && xorriso -as mkisofs -o "$ISO_WORK/broken.iso" . ) >/dev/null 2>&1

DIE_FIRED=0
DIE_MSG=""
export ISO_SOURCE_PATH="$ISO_WORK/broken.iso"
export ISO_OUTPUT_PATH="$ISO_WORK/broken.iso"
set +e
debian_verify_iso_structure 2>/dev/null
set -e
[[ $DIE_FIRED -ge 1 ]] || fail "gate accepted a source ISO without dists layout"
grep -q '/dists/' <<<"$DIE_MSG" || fail "gate failure does not mention the missing repository layout: $DIE_MSG"

# --- T4: missing injected file must be rejected ---------------------------------
export ISO_SOURCE_PATH="$ISO_WORK/source.iso"
rm "$ISO_WORK/tree/omnixys-partman.sh"
repack_copy_then_grow "$ISO_WORK/tree" "$ISO_OUTPUT_PATH" "$ISO_SOURCE_PATH"

DIE_FIRED=0
DIE_MSG=""
set +e
debian_verify_iso_structure 2>/dev/null
set -e
[[ $DIE_FIRED -ge 1 ]] || fail "gate accepted a remaster missing an injected script"
grep -q 'omnixys-partman.sh' <<<"$DIE_MSG" || fail "gate failure does not name the missing injected file: $DIE_MSG"

# --- T5: syntactically broken injected script must be rejected -------------------
inject_omnixys_files "$ISO_WORK/tree"
printf '#!/bin/sh\nif; then broken\n' >"$ISO_WORK/tree/omnixys-network-late.sh"
repack_copy_then_grow "$ISO_WORK/tree" "$ISO_OUTPUT_PATH" "$ISO_SOURCE_PATH"

DIE_FIRED=0
DIE_MSG=""
set +e
debian_verify_iso_structure 2>/dev/null
set -e
[[ $DIE_FIRED -ge 1 ]] || fail "gate accepted a remaster with a syntactically broken script"
grep -q 'omnixys-network-late.sh' <<<"$DIE_MSG" || fail "gate failure does not name the broken script: $DIE_MSG"

echo "Builder ISO structure tests passed"
