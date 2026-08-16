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
    -e "s|IDENTITY_DEVICE_RETRIES=5|IDENTITY_DEVICE_RETRIES=1|g" \
    -e "s|IDENTITY_DEVICE_RETRY_DELAY=1|IDENTITY_DEVICE_RETRY_DELAY=0|g" \
    "$src" >"$dst"
  chmod +x "$dst"
}

reset_sandbox() {
  # shellcheck disable=SC2115
  rm -rf "$SANDBOX/cdrom" "$SANDBOX/var/lib" "$SANDBOX/media" "$SANDBOX/dev" "$SANDBOX/var/log/installer"
  : >"$DEBCONF_LOG"
  : >"$SANDBOX/var/log/omnixys-early.log"
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
grep -q 'required identity file not found (IDENTITY_SOURCE=usb-env); aborting installation' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'identity device not found' "$SANDBOX/var/log/installer/omnixys-early.log"

# --- Case 3: usb-env + IDENTITY_REQUIRED=false + identity missing
# --- -> continues with build-time defaults (exit 0), no overrides applied
export IDENTITY_REQUIRED=false
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case3-early.sh"
reset_sandbox
run_early "$SANDBOX/case3-early.sh"
[[ ! -s "$DEBCONF_LOG" ]]
grep -q 'continuing with build-time defaults' "$SANDBOX/var/log/omnixys-early.log"
grep -q 'identity file not found; continuing with build-time defaults' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'identity device not found' "$SANDBOX/var/log/installer/omnixys-early.log"

# --- Case 4: USB OMNIXYS_ID present + embedded identity present
# --- -> USB must win (priority 1), embedded must NOT be selected
export IDENTITY_REQUIRED=true
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case4-early.sh"
reset_sandbox
mkdir -p "$SANDBOX/dev/disk/by-label" "$SANDBOX/media/omnixys-identity" "$SANDBOX/cdrom"
touch "$SANDBOX/dev/disk/by-label/OMNIXYS_ID"
cat >"$SANDBOX/media/omnixys-identity/identity.env" <<'EOF'
OMNIXYS_HOSTNAME=omnixys-usb-01
OMNIXYS_DOMAIN=usb.lab
OMNIXYS_SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA case4-secret-ssh-key@omnixys"
OMNIXYS_PASSWORD_HASH='$6$case4$secret$hash'
EOF
cat >"$SANDBOX/cdrom/identity.env" <<'EOF'
OMNIXYS_HOSTNAME=omnixys-embedded-01
OMNIXYS_PASSWORD_HASH='$6$embedded$secret$hash'
EOF
cat >"$SANDBOX/bin/mount" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$SANDBOX/bin/mount"
run_early "$SANDBOX/case4-early.sh"
grep -qF 'netcfg/get_hostname omnixys-usb-01' "$DEBCONF_LOG"
if grep -qF 'omnixys-embedded-01' "$DEBCONF_LOG"; then
  echo "case4: embedded identity must NOT win over USB" >&2
  exit 1
fi
grep -q 'identity source selected: usb-env' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'identity device detected: OMNIXYS_ID' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'identity device mount succeeded' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'identity.env found on mounted device' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'USB identity selected' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'hostname override applied: omnixys-usb-01' "$SANDBOX/var/log/installer/omnixys-early.log"
if grep -q 'embedded identity selected' "$SANDBOX/var/log/installer/omnixys-early.log"; then
  echo "case4: embedded must not be selected when USB wins" >&2
  exit 1
fi
# no secrets in either early log
if grep -qF '$6$case4$secret$hash' "$SANDBOX/var/log/installer/omnixys-early.log"; then
  echo "case4: password hash leaked into persistent early log" >&2
  exit 1
fi
if grep -qF 'case4-secret-ssh-key' "$SANDBOX/var/log/installer/omnixys-early.log"; then
  echo "case4: ssh key leaked into persistent early log" >&2
  exit 1
fi
if grep -qF '$6$case4$secret$hash' "$SANDBOX/var/log/omnixys-early.log"; then
  echo "case4: password hash leaked into ephemeral early log" >&2
  exit 1
fi

# --- Case 5: USB device present but mount fails
# --- -> correct logging + fallback to embedded identity (priority 2)
export IDENTITY_REQUIRED=true
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case5-early.sh"
reset_sandbox
mkdir -p "$SANDBOX/dev/disk/by-label" "$SANDBOX/media/omnixys-identity" "$SANDBOX/cdrom"
touch "$SANDBOX/dev/disk/by-label/OMNIXYS_ID"
printf 'OMNIXYS_HOSTNAME=stale-usb\n' >"$SANDBOX/media/omnixys-identity/identity.env"
printf 'OMNIXYS_HOSTNAME=omnixys-embedded-02\n' >"$SANDBOX/cdrom/identity.env"
cat >"$SANDBOX/bin/mount" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$SANDBOX/bin/mount"
run_early "$SANDBOX/case5-early.sh"
grep -qF 'netcfg/get_hostname omnixys-embedded-02' "$DEBCONF_LOG"
grep -q 'identity device mount failed' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'embedded identity selected' "$SANDBOX/var/log/installer/omnixys-early.log"
if grep -q 'USB identity selected' "$SANDBOX/var/log/installer/omnixys-early.log"; then
  echo "case5: USB must not be selected when mount fails" >&2
  exit 1
fi
if grep -qF 'stale-usb' "$DEBCONF_LOG"; then
  echo "case5: stale USB identity must not be applied when mount fails" >&2
  exit 1
fi

# --- Case 6: USB absent + embedded identity present
# --- -> embedded identity wins (priority 2)
export IDENTITY_REQUIRED=true
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case6-early.sh"
reset_sandbox
mkdir -p "$SANDBOX/cdrom"
printf 'OMNIXYS_HOSTNAME=omnixys-embedded-03\n' >"$SANDBOX/cdrom/identity.env"
run_early "$SANDBOX/case6-early.sh"
grep -qF 'netcfg/get_hostname omnixys-embedded-03' "$DEBCONF_LOG"
grep -q 'identity device not found' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'embedded identity selected' "$SANDBOX/var/log/installer/omnixys-early.log"

# --- Case 7: FAT32 USB medium mounted successfully via auto-detect
# --- -> USB identity loaded, hostname omnixys-03 applied
export IDENTITY_REQUIRED=true
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case7-early.sh"
reset_sandbox
mkdir -p "$SANDBOX/dev/disk/by-label" "$SANDBOX/media/omnixys-identity"
touch "$SANDBOX/dev/disk/by-label/OMNIXYS_ID"
cat >"$SANDBOX/media/omnixys-identity/identity.env" <<'EOF'
OMNIXYS_HOSTNAME=omnixys-03
OMNIXYS_DOMAIN=usb.lab
OMNIXYS_SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA case7@omnixys"
OMNIXYS_PASSWORD_HASH='$6$case7$secret$hash'
EOF
cat >"$SANDBOX/bin/mount" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$SANDBOX/bin/mount"
run_early "$SANDBOX/case7-early.sh"
grep -qF 'netcfg/get_hostname omnixys-03' "$DEBCONF_LOG"
grep -q 'identity device mount succeeded' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'USB identity selected' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'hostname override applied: omnixys-03' "$SANDBOX/var/log/installer/omnixys-early.log"

# --- Case 8: auto-detect mount fails, -t vfat fallback succeeds
# --- -> exact error logged, USB identity loaded, hostname omnixys-03 applied
export IDENTITY_REQUIRED=true
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case8-early.sh"
reset_sandbox
mkdir -p "$SANDBOX/dev/disk/by-label" "$SANDBOX/media/omnixys-identity"
touch "$SANDBOX/dev/disk/by-label/OMNIXYS_ID"
cat >"$SANDBOX/media/omnixys-identity/identity.env" <<'EOF'
OMNIXYS_HOSTNAME=omnixys-03
OMNIXYS_DOMAIN=usb.lab
OMNIXYS_SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA case8@omnixys"
OMNIXYS_PASSWORD_HASH='$6$case8$secret$hash'
EOF
cat >"$SANDBOX/bin/mount" <<'EOF'
#!/bin/sh
case " $* " in
  *"-t vfat"*) exit 0 ;;
esac
echo "mount: unknown filesystem type 'vfat'" >&2
exit 1
EOF
chmod +x "$SANDBOX/bin/mount"
run_early "$SANDBOX/case8-early.sh"
grep -qF 'netcfg/get_hostname omnixys-03' "$DEBCONF_LOG"
grep -qF "identity device mount (auto) failed: mount: unknown filesystem type 'vfat'" "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'identity device mounted via -t vfat' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'hostname override applied: omnixys-03' "$SANDBOX/var/log/installer/omnixys-early.log"

# --- Case 9: both auto and -t vfat mounts fail, embedded identity present
# --- -> exact mount errors persisted, fallback to embedded identity (priority 2)
export IDENTITY_REQUIRED=true
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case9-early.sh"
reset_sandbox
mkdir -p "$SANDBOX/dev/disk/by-label" "$SANDBOX/media/omnixys-identity" "$SANDBOX/cdrom"
touch "$SANDBOX/dev/disk/by-label/OMNIXYS_ID"
printf 'OMNIXYS_HOSTNAME=stale-usb-09\n' >"$SANDBOX/media/omnixys-identity/identity.env"
printf 'OMNIXYS_HOSTNAME=omnixys-embedded-09\n' >"$SANDBOX/cdrom/identity.env"
cat >"$SANDBOX/bin/mount" <<'EOF'
#!/bin/sh
echo "mount: unknown filesystem type 'vfat'" >&2
exit 1
EOF
chmod +x "$SANDBOX/bin/mount"
run_early "$SANDBOX/case9-early.sh"
grep -qF 'netcfg/get_hostname omnixys-embedded-09' "$DEBCONF_LOG"
grep -qF "identity device mount (auto) failed: mount: unknown filesystem type 'vfat'" "$SANDBOX/var/log/installer/omnixys-early.log"
grep -qF "identity device mount (-t vfat) failed: mount: unknown filesystem type 'vfat'" "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'identity device mount failed' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'embedded identity selected' "$SANDBOX/var/log/installer/omnixys-early.log"
if grep -qF 'stale-usb-09' "$DEBCONF_LOG"; then
  echo "case9: stale USB identity must not be applied when mount fails" >&2
  exit 1
fi

# --- Case 9b: both mounts fail, identity not required, no embedded identity
# --- -> continues with build-time defaults, exact error persisted
export IDENTITY_REQUIRED=false
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case9b-early.sh"
reset_sandbox
mkdir -p "$SANDBOX/dev/disk/by-label" "$SANDBOX/media/omnixys-identity"
touch "$SANDBOX/dev/disk/by-label/OMNIXYS_ID"
cat >"$SANDBOX/bin/mount" <<'EOF'
#!/bin/sh
echo "mount: unknown filesystem type 'vfat'" >&2
exit 1
EOF
chmod +x "$SANDBOX/bin/mount"
run_early "$SANDBOX/case9b-early.sh"
grep -q 'continuing with build-time defaults' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -qF "identity device mount (-t vfat) failed after module load: mount: unknown filesystem type 'vfat'" "$SANDBOX/var/log/installer/omnixys-early.log"

# --- Case 10: auto + vfat fail, modprobe loads vfat module, retry succeeds
# --- -> USB identity loaded, hostname omnixys-03 applied
export IDENTITY_REQUIRED=true
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case10-early.sh"
reset_sandbox
mkdir -p "$SANDBOX/dev/disk/by-label" "$SANDBOX/media/omnixys-identity"
touch "$SANDBOX/dev/disk/by-label/OMNIXYS_ID"
cat >"$SANDBOX/media/omnixys-identity/identity.env" <<'EOF'
OMNIXYS_HOSTNAME=omnixys-03
OMNIXYS_DOMAIN=usb.lab
OMNIXYS_SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA case10@omnixys"
OMNIXYS_PASSWORD_HASH='$6$case10$secret$hash'
EOF
cat >"$SANDBOX/bin/modprobe" <<'EOF'
#!/bin/sh
[ "$1" = "vfat" ] || exit 1
touch "$MODPROBE_MARKER"
exit 0
EOF
chmod +x "$SANDBOX/bin/modprobe"
cat >"$SANDBOX/bin/mount" <<'EOF'
#!/bin/sh
case " $* " in
  *"-t vfat"*)
    [ -e "$MODPROBE_MARKER" ] && exit 0
    ;;
esac
echo "mount: unknown filesystem type 'vfat'" >&2
exit 1
EOF
chmod +x "$SANDBOX/bin/mount"
export MODPROBE_MARKER="$SANDBOX/modprobe.called"
run_early "$SANDBOX/case10-early.sh"
unset MODPROBE_MARKER
grep -qF 'netcfg/get_hostname omnixys-03' "$DEBCONF_LOG"
grep -q 'vfat kernel module loaded via modprobe' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'identity device mounted via -t vfat after module load' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'hostname override applied: omnixys-03' "$SANDBOX/var/log/installer/omnixys-early.log"

echo "Identity mechanism tests passed"
