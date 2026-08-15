#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2181
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDER="$ROOT_DIR/installer/debian-preseed/builder.sh"
[[ -f "$BUILDER" ]] || { echo "builder missing"; exit 1; }

# --- Stub core helpers so builder.sh functions can be unit tested in isolation
DIE_FIRED=0
die() { DIE_FIRED=1; return 1; }
info() { :; }
step() { :; }
warn() { :; }
ensure_dir() { mkdir -p "$1"; }
run_cmd() { "$@"; }

# shellcheck disable=SC1090
source "$BUILDER"

fail() { echo "$1" >&2; exit 1; }

# --- 1. Policy decision function ----------------------------------------------
unset IDENTITY_EMBED
if debian_identity_embed_enabled; then :; else fail "default IDENTITY_EMBED must be enabled"; fi

IDENTITY_EMBED=true
if debian_identity_embed_enabled; then :; else fail "IDENTITY_EMBED=true must be enabled"; fi

IDENTITY_EMBED=false
if debian_identity_embed_enabled; then fail "IDENTITY_EMBED=false must be disabled"; else :; fi

# --- 2. Structural presence in builder.sh -------------------------------------
grep -q 'debian_identity_embed_enabled()' "$BUILDER"
grep -q 'debian_iso_contains_path()' "$BUILDER"
grep -q 'debian_assert_no_identity_in_iso()' "$BUILDER"
grep -q 'debian_identity_embed_enabled &&' "$BUILDER"
grep -q 'debian_assert_no_identity_in_iso' "$BUILDER"

# --- 3. ISO containment + gate (requires xorriso) -----------------------------
# Skipped when xorriso is absent (covered in CI via the test-iso job).
if command -v xorriso >/dev/null 2>&1; then
  ISO_WORK="$(mktemp -d)"
  trap 'rm -rf "$ISO_WORK"' EXIT

  mkdir -p "$ISO_WORK/withid" "$ISO_WORK/noid"
  printf 'OMNIXYS_HOSTNAME=vm-test\n' >"$ISO_WORK/withid/identity.env"
  printf 'dummy\n' >"$ISO_WORK/withid/README"
  printf 'dummy\n' >"$ISO_WORK/noid/README"

  ( cd "$ISO_WORK/withid" && xorriso -as mkisofs -o "$ISO_WORK/with.iso" . ) >/dev/null 2>&1
  ( cd "$ISO_WORK/noid"   && xorriso -as mkisofs -o "$ISO_WORK/no.iso"   . ) >/dev/null 2>&1

  # contains_path: true when identity present, false otherwise
  ISO_OUTPUT_PATH="$ISO_WORK/with.iso"
  if debian_iso_contains_path "$ISO_OUTPUT_PATH" "/identity.env"; then :; else fail "with.iso should contain /identity.env"; fi

  ISO_OUTPUT_PATH="$ISO_WORK/no.iso"
  if debian_iso_contains_path "$ISO_OUTPUT_PATH" "/identity.env"; then fail "no.iso must NOT contain /identity.env"; else :; fi

  # --- 4. Release gate behavior -----------------------------------------------
  # The `die` stub sets DIE_FIRED without aborting, so each assertion checks the
  # flag (the real die would exit the installer).

  # embed enabled + identity present -> gate must NOT fire
  DIE_FIRED=0
  IDENTITY_EMBED=true
  export DRY_RUN=false
  export ISO_OUTPUT_PATH="$ISO_WORK/with.iso"
  set +e
  debian_assert_no_identity_in_iso
  set -e
  [[ $DIE_FIRED -eq 0 ]] || fail "unexpected die when IDENTITY_EMBED=true"

  # embed disabled + identity present in ISO -> gate must fire
  DIE_FIRED=0
  export IDENTITY_EMBED=false
  export ISO_OUTPUT_PATH="$ISO_WORK/with.iso"
  set +e
  debian_assert_no_identity_in_iso
  set -e
  [[ $DIE_FIRED -eq 1 ]] || fail "expected die when IDENTITY_EMBED=false + identity present"

  # embed disabled + identity absent from ISO -> gate must NOT fire
  DIE_FIRED=0
  export ISO_OUTPUT_PATH="$ISO_WORK/no.iso"
  set +e
  debian_assert_no_identity_in_iso
  set -e
  [[ $DIE_FIRED -eq 0 ]] || fail "unexpected die when identity absent"

  # embed disabled in dry-run -> gate must NOT fire (no final ISO yet)
  DIE_FIRED=0
  DRY_RUN=true
  export ISO_OUTPUT_PATH="$ISO_WORK/with.iso"
  set +e
  debian_assert_no_identity_in_iso
  set -e
  [[ $DIE_FIRED -eq 0 ]] || fail "gate must not fire in dry-run"
fi

echo "Builder identity-embed tests passed"
