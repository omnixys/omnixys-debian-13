#!/usr/bin/env bash
# shellcheck disable=SC2016 # test fixture: intentional literal '$' in grep/hash patterns
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDERER="$ROOT_DIR/installer/debian-preseed/renderer.sh"

[[ -f "$RENDERER" ]] || { echo "renderer missing"; exit 1; }

die() { echo "die: $*" >&2; exit 1; }
info() { :; }
step() { :; }
warn() { :; }
ensure_dir() { mkdir -p "$1"; }

# shellcheck disable=SC1090
source "$RENDERER"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

export ROOT_DIR
export INSTALLER_VERSION=1.0.0
export DEBIAN_MAJOR=13
export ARCH=amd64
export APT_MIRROR=deb.debian.org
export HOSTNAME=omnixys-vm-01
export DOMAIN=vm.local
export FULLNAME="VM Admin"
export USERNAME=vmadmin
export PASSWORD=ChangeThisStrongPass123!
# shellcheck disable=SC2016
export PASSWORD_HASH='$6$build$time$defaults'
export LANGUAGE=en
export COUNTRY=DE
export LOCALE=en_US.UTF-8
export KEYBOARD=de
export TIMEZONE=Europe/Berlin
export TARGET_DISK_MODE=manual
export TARGET_DISK=/dev/vda
export PARTITION_MODE=erase
export ERASE_DISK=true
export FILESYSTEM=btrfs
export INSTALL_OPENSSH=true
export INSTALL_STANDARD_UTILITIES=true
export INSTALL_FIRMWARE=false
export INSTALL_UPDATES=true
export SSH_PUBLIC_KEY="ssh-ed25519 AAAA build-default@omnixys"
export SSH_PASSWORD_AUTH=false
export SSH_PERMIT_ROOT_LOGIN=no
export SUDO_NOPASSWD=true
export REBOOT_AFTER_INSTALL=false
export IDENTITY_SOURCE=usb-env
export IDENTITY_REQUIRED=false
export IDENTITY_FILE_PATH=/identity.env
export IDENTITY_DEVICE_LABEL=OMNIXYS_ID

export BACKEND_WORK_DIR="$SANDBOX"
export GENERATED_DIR="$SANDBOX/generated"
ensure_dir "$GENERATED_DIR"

# --- Render the real preseed + early script (IDENTITY_REQUIRED=false) ---
debian_resolve_password_hash
debian_partition_mode_values
debian_resolve_target_disk
debian_render_early_script
debian_compose_preseed_early_command
# Globals consumed by debian_render_template(); exported so they are
# recognized as externally-used by shellcheck and visible to the renderer.
export TASKSEL_FIRST PKGSEL_INCLUDE PKGSEL_UPGRADE ANNA_MODULES FINISH_ACTION LATE_COMMAND
TASKSEL_FIRST="$(debian_compose_tasksel)"
PKGSEL_INCLUDE="$(debian_compose_pkgsel)"
PKGSEL_UPGRADE="$(debian_compose_pkgsel_upgrade)"
ANNA_MODULES="$(debian_compose_anna_modules)"
FINISH_ACTION="$(debian_compose_finish_action)"
LATE_COMMAND="$(debian_compose_late_command)"
debian_render_template \
  "$ROOT_DIR/templates/debian-preseed.cfg.template" \
  "$GENERATED_DIR/preseed.cfg"

PRESEED="$GENERATED_DIR/preseed.cfg"
EARLY="$GENERATED_DIR/omnixys-early.sh"

# --- Rendered preseed carries build-time defaults that the identity
# --- mechanism overrides at runtime (HOSTNAME, DOMAIN, FULLNAME,
# --- USERNAME, PASSWORD_HASH via early debconf-set; SSH key, username,
# --- hostname via late command from identity.env).
grep -q 'd-i netcfg/get_hostname string omnixys-vm-01' "$PRESEED"
grep -q 'd-i netcfg/get_domain string vm.local' "$PRESEED"
grep -q 'd-i passwd/user-fullname string VM Admin' "$PRESEED"
grep -q 'd-i passwd/username string vmadmin' "$PRESEED"
grep -q 'd-i passwd/user-password-crypted password ' "$PRESEED"
grep -q 'd-i preseed/early_command string sh /cdrom/omnixys-early.sh' "$PRESEED"

grep -q 'debconf-set netcfg/get_hostname "$OMNIXYS_HOSTNAME"' "$EARLY"
grep -q 'debconf-set netcfg/get_domain "$OMNIXYS_DOMAIN"' "$EARLY"
grep -q 'debconf-set passwd/user-fullname "$OMNIXYS_FULLNAME"' "$EARLY"
grep -q 'debconf-set passwd/username "$OMNIXYS_USERNAME"' "$EARLY"
grep -q 'debconf-set passwd/user-password-crypted "$OMNIXYS_PASSWORD_HASH"' "$EARLY"
grep -q 'OMNIXYS_SSH_PUBLIC_KEY' "$PRESEED"
grep -q 'OMNIXYS_USERNAME' "$PRESEED"
grep -q 'OMNIXYS_HOSTNAME' "$PRESEED"

grep -q 'identity is required but missing' "$EARLY" && { echo "old abort message still present"; exit 1; }
grep -q 'required identity file not found (IDENTITY_SOURCE=usb-env); aborting installation' "$EARLY"
grep -q 'continuing with build-time defaults' "$EARLY"

grep -q 'debian_compose_identity_early_command' "$RENDERER" && { echo "dead duplicate function still present"; exit 1; }

# --- Sandbox stub infrastructure ---
mkdir -p "$SANDBOX/bin" "$SANDBOX/var/log"
cat >"$SANDBOX/bin/debconf-set" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$DEBCONF_LOG"
EOF
chmod +x "$SANDBOX/bin/debconf-set"
export DEBCONF_LOG="$SANDBOX/debconf.log"
export PATH="$SANDBOX/bin:$PATH"

sandboxize() {
  local src="$1" dst="$2"
  sed \
    -e "s|/cdrom|$SANDBOX/cdrom|g" \
    -e "s|/var/lib/omnixys|$SANDBOX/var/lib/omnixys|g" \
    -e "s|/media/omnixys-identity|$SANDBOX/media/omnixys-identity|g" \
    -e "s|/var/log|$SANDBOX/var/log|g" \
    -e "s|/dev/disk/by-label|$SANDBOX/dev/disk/by-label|g" \
    "$src" >"$dst"
  chmod +x "$dst"
}

reset_sandbox() {
  # shellcheck disable=SC2115
  rm -rf "$SANDBOX/cdrom" "$SANDBOX/var/lib" "$SANDBOX/media"
  : >"$DEBCONF_LOG"
}

run_early() {
  local script="$1"
  "$script" >"$SANDBOX/run.out" 2>&1 || return $?
}

# --- Case 1: usb-env + IDENTITY_REQUIRED=true + identity present
# --- -> overrides are applied via debconf-set
export IDENTITY_REQUIRED=true
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case1-early.sh"
reset_sandbox
mkdir -p "$SANDBOX/cdrom"
cat >"$SANDBOX/cdrom/identity.env" <<'EOF'
OMNIXYS_HOSTNAME=omnixys-node-01
OMNIXYS_DOMAIN=node.lab
OMNIXYS_FULLNAME="Node Admin"
OMNIXYS_USERNAME=ops
OMNIXYS_SSH_PUBLIC_KEY="ssh-ed25519 AAAA identity@omnixys"
OMNIXYS_PASSWORD_HASH='$6$rounds=656000$id$example'
EOF
run_early "$SANDBOX/case1-early.sh"
grep -qF 'netcfg/get_hostname omnixys-node-01' "$DEBCONF_LOG"
grep -qF 'netcfg/get_domain node.lab' "$DEBCONF_LOG"
grep -qF 'passwd/user-fullname Node Admin' "$DEBCONF_LOG"
grep -qF 'passwd/username ops' "$DEBCONF_LOG"
grep -qF 'passwd/user-password-crypted $6$rounds=656000$id$example' "$DEBCONF_LOG"
[[ -f "$SANDBOX/var/lib/omnixys/identity.env" ]]

# --- Case 2: usb-env + IDENTITY_REQUIRED=true + identity missing
# --- -> installation aborts (non-zero exit), no overrides applied
export IDENTITY_REQUIRED=true
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case2-early.sh"
reset_sandbox
set +e
run_early "$SANDBOX/case2-early.sh"
rc=$?
set -e
if [ "$rc" -ne 1 ]; then
  echo "case2: expected exit code 1, got $rc" >&2
  exit 1
fi
[[ ! -s "$DEBCONF_LOG" ]]
grep -q 'required identity file not found (IDENTITY_SOURCE=usb-env); aborting installation' "$SANDBOX/var/log/omnixys-early.log"

# --- Case 3: usb-env + IDENTITY_REQUIRED=false + identity missing
# --- -> continues with build-time defaults (exit 0), no overrides applied
export IDENTITY_REQUIRED=false
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case3-early.sh"
reset_sandbox
run_early "$SANDBOX/case3-early.sh"
[[ ! -s "$DEBCONF_LOG" ]]
grep -q 'continuing with build-time defaults' "$SANDBOX/var/log/omnixys-early.log"

echo "Identity mechanism tests passed"
