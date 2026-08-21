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
export IDENTITY_CONFIRM=false

export BACKEND_WORK_DIR="$SANDBOX"
export GENERATED_DIR="$SANDBOX/generated"
ensure_dir "$GENERATED_DIR"

# --- Render the real preseed + early script (IDENTITY_REQUIRED=false) ---
debian_resolve_password_hash
debian_partition_mode_values
debian_resolve_target_disk
debian_render_early_script
debian_render_network_late_script
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
NETWORK_LATE="$GENERATED_DIR/omnixys-network-late.sh"

if command -v dash >/dev/null 2>&1; then
  dash -n "$EARLY" "$NETWORK_LATE"
else
  sh -n "$EARLY" "$NETWORK_LATE"
fi
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$EARLY" "$NETWORK_LATE"
fi

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
grep -q 'sh /cdrom/omnixys-network-late.sh' "$PRESEED"

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
grep -q 'prompting for interactive input' "$EARLY"
if grep -Eq 'read[[:space:]].*-[^[:space:]]*t' "$EARLY"; then
  echo "generated early script uses non-POSIX read timeout" >&2
  exit 1
fi

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
    -e "s|/usr/share/debconf|$SANDBOX/usr/share/debconf|g" \
    -e "s|/dev/console|$SANDBOX/dev/console|g" \
    -e "s|/dev/disk/by-label|$SANDBOX/dev/disk/by-label|g" \
    -e "s|IDENTITY_CONFIRM_TIMEOUT=5|IDENTITY_CONFIRM_TIMEOUT=1|g" \
    -e "s|IDENTITY_DEVICE_RETRIES=5|IDENTITY_DEVICE_RETRIES=1|g" \
    -e "s|IDENTITY_DEVICE_RETRY_DELAY=1|IDENTITY_DEVICE_RETRY_DELAY=0|g" \
    "$src" >"$dst"
  chmod +x "$dst"
}

reset_sandbox() {
  # shellcheck disable=SC2115
  rm -rf "$SANDBOX/cdrom" "$SANDBOX/var/lib" "$SANDBOX/media" "$SANDBOX/dev" "$SANDBOX/var/log/installer"
  : >"$DEBCONF_LOG"
}

run_early() {
  local script="$1"
  local rc=0
  if command -v dash >/dev/null 2>&1; then
    dash "$script" >"$SANDBOX/run.out" 2>&1 || rc=$?
  else
    "$script" >"$SANDBOX/run.out" 2>&1 || rc=$?
  fi
  [[ "$rc" -eq 0 ]] || return "$rc"
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
grep -q 'required identity file not found (IDENTITY_SOURCE=usb-env); aborting installation' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'identity device not found' "$SANDBOX/var/log/installer/omnixys-early.log"

# --- Case 3: usb-env + IDENTITY_REQUIRED=false + identity missing + IDENTITY_CONFIRM=false
# --- -> continues with build defaults (exit 0), no overrides applied
export IDENTITY_REQUIRED=false
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case3-early.sh"
reset_sandbox
run_early "$SANDBOX/case3-early.sh"
[[ ! -s "$DEBCONF_LOG" ]]
grep -q 'identity file not found; prompting for interactive input' "$SANDBOX/var/log/installer/omnixys-early.log"
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
grep -q 'hostname configuration applied' "$SANDBOX/var/log/installer/omnixys-early.log"
if grep -q 'embedded identity selected' "$SANDBOX/var/log/installer/omnixys-early.log"; then
  echo "case4: embedded must not be selected when USB wins" >&2
  exit 1
fi
# no secrets in the persistent early log
if grep -qF '$6$case4$secret$hash' "$SANDBOX/var/log/installer/omnixys-early.log"; then
  echo "case4: password hash leaked into persistent early log" >&2
  exit 1
fi
if grep -qF 'case4-secret-ssh-key' "$SANDBOX/var/log/installer/omnixys-early.log"; then
  echo "case4: ssh key leaked into persistent early log" >&2
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
grep -q 'hostname configuration applied' "$SANDBOX/var/log/installer/omnixys-early.log"

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
grep -q 'hostname configuration applied' "$SANDBOX/var/log/installer/omnixys-early.log"

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
grep -q 'identity file not found; prompting for interactive input' "$SANDBOX/var/log/installer/omnixys-early.log"
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
grep -q 'hostname configuration applied' "$SANDBOX/var/log/installer/omnixys-early.log"

# --- Case 11: Bash-ism regression ---
# --- -> generated early script must not contain += or ${!...} ---
export IDENTITY_REQUIRED=true
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case11-early.sh"
if grep -q '+=' "$SANDBOX/case11-early.sh"; then
  echo "case11: generated script contains bash += operator" >&2
  exit 1
fi
if grep -q '${!' "$SANDBOX/case11-early.sh"; then
  echo "case11: generated script contains bash \${!...} indirect expansion" >&2
  exit 1
fi

# --- Case 12: exec ordering ---
# --- -> mkdir must appear before exec in the generated script ---
export IDENTITY_REQUIRED=false
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case12-early.sh"
mkdir_line=$(grep -n "mkdir -p $SANDBOX/var/log/installer" "$SANDBOX/case12-early.sh" | head -1 | cut -d: -f1)
exec_line=$(grep -n "exec >$SANDBOX/var/log/installer" "$SANDBOX/case12-early.sh" | head -1 | cut -d: -f1)
if [ -z "$mkdir_line" ] || [ -z "$exec_line" ]; then
  echo "case12: mkdir or exec line not found in generated script" >&2
  exit 1
fi
if [ "$mkdir_line" -ge "$exec_line" ]; then
  echo "case12: mkdir (line $mkdir_line) must come before exec (line $exec_line)" >&2
  exit 1
fi

# --- Case 13: sourcing error handling ---
# --- -> corrupted optional identity.env: error logged, no override applied ---
export IDENTITY_REQUIRED=false
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case13-early.sh"
reset_sandbox
mkdir -p "$SANDBOX/cdrom"
printf '%s\n' 'OMNIXYS_HOSTNAME="unterminated' >"$SANDBOX/cdrom/identity.env"
run_early "$SANDBOX/case13-early.sh"
grep -q 'identity sourcing start' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'identity sourcing failed' "$SANDBOX/var/log/installer/omnixys-early.log"
if grep -qF 'netcfg/get_hostname' "$DEBCONF_LOG"; then
  echo "case13: debconf-set must not be called when sourcing fails" >&2
  exit 1
fi

# --- Case 14: cp failure handling ---
# --- -> read-only destination: error logged, identity not applied ---
export IDENTITY_REQUIRED=true
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case14-early.sh"
reset_sandbox
mkdir -p "$SANDBOX/cdrom" "$SANDBOX/var/lib/omnixys"
printf 'OMNIXYS_HOSTNAME=should-not-apply\n' >"$SANDBOX/cdrom/identity.env"
chmod 444 "$SANDBOX/var/lib/omnixys"
set +e
run_early "$SANDBOX/case14-early.sh"
rc=$?
set -e
[[ "$rc" -eq 1 ]]
grep -q 'FAILED to copy identity file' "$SANDBOX/var/log/installer/omnixys-early.log"
if grep -qF 'netcfg/get_hostname' "$DEBCONF_LOG"; then
  echo "case14: debconf-set must not be called when cp fails" >&2
  exit 1
fi
chmod 755 "$SANDBOX/var/lib/omnixys"

install_debconf_stub() {
  mkdir -p "$SANDBOX/usr/share/debconf" "$SANDBOX/cdrom"
  cp "$ROOT_DIR/templates/omnixys-identity.templates" "$SANDBOX/cdrom/omnixys-identity.templates"
  cat >"$SANDBOX/usr/share/debconf/confmodule" <<'DBEOF'
db_x_loadtemplatefile() { printf 'load %s\n' "$*" >>"$DEBCONF_UI_LOG"; }
db_settitle() { printf 'title %s\n' "$*" >>"$DEBCONF_UI_LOG"; }
db_set() { DB_LAST_QUESTION="$1"; DB_LAST_VALUE="$2"; printf 'set %s %s\n' "$1" "$2" >>"$DEBCONF_UI_LOG"; }
db_fset() { printf 'fset %s\n' "$*" >>"$DEBCONF_UI_LOG"; }
db_input() { printf 'input %s\n' "$*" >>"$DEBCONF_UI_LOG"; }
db_go() { printf 'go\n' >>"$DEBCONF_UI_LOG"; }
db_get() {
  RET="$DB_LAST_VALUE"
  printf 'get %s\n' "$1" >>"$DEBCONF_UI_LOG"
}
db_subst() { printf 'subst %s\n' "$*" >>"$DEBCONF_UI_LOG"; }
DBEOF
}

export DEBCONF_UI_LOG="$SANDBOX/debconf-ui.log"
export OMNIXYS_IDENTITY_CONSOLE_INPUT="$SANDBOX/dev/console-input"

request_identity_edit() {
  mkdir -p "$SANDBOX/dev"
  : >"$SANDBOX/dev/console"
  printf 'E\n' >"$OMNIXYS_IDENTITY_CONSOLE_INPUT"
}

# --- Case 15: IDENTITY_CONFIRM=true + IDENTITY_SOURCE=none ---
# --- -> native d-i dialog is shown with build defaults and saves identity.env
export IDENTITY_SOURCE=none
export IDENTITY_REQUIRED=false
export IDENTITY_CONFIRM=true
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case15-early.sh"
reset_sandbox
: >"$DEBCONF_UI_LOG"
install_debconf_stub
request_identity_edit
run_early "$SANDBOX/case15-early.sh"
if [[ ! -f "$SANDBOX/var/lib/omnixys/identity.env" ]]; then
  cat "$SANDBOX/var/log/installer/omnixys-early.log" >&2
  cat "$DEBCONF_UI_LOG" >&2
  echo "case15: native dialog did not save identity.env" >&2
  exit 1
fi
grep -q 'load .*omnixys-identity.templates omnixys' "$DEBCONF_UI_LOG" || {
  sed -n '1,120p' "$SANDBOX/var/log/installer/omnixys-early.log" >&2
  echo "case15: edit gate did not open the native dialog" >&2
  exit 1
}
grep -q 'input critical omnixys/hostname' "$DEBCONF_UI_LOG"
grep -q 'input critical omnixys/ssh-public-key' "$DEBCONF_UI_LOG"
grep -q 'identity edit dialog: values saved' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q "OMNIXYS_HOSTNAME='omnixys-vm-01'" "$SANDBOX/var/lib/omnixys/identity.env"
grep -qF 'netcfg/get_hostname omnixys-vm-01' "$DEBCONF_LOG"

# --- Case 16: existing identity values prefill the native dialog ---
export IDENTITY_SOURCE=usb-env
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case16-early.sh"
reset_sandbox
: >"$DEBCONF_UI_LOG"
install_debconf_stub
request_identity_edit
cat >"$SANDBOX/cdrom/identity.env" <<'EOF'
OMNIXYS_HOSTNAME=dialog-node
OMNIXYS_DOMAIN=dialog.local
OMNIXYS_FULLNAME="Dialog Admin"
OMNIXYS_USERNAME=dialog
OMNIXYS_PASSWORD_HASH='$6$dialog$secret$hash'
EOF
run_early "$SANDBOX/case16-early.sh"
grep -q 'set omnixys/hostname dialog-node' "$DEBCONF_UI_LOG"
grep -q 'identity edit requested from installer console' "$SANDBOX/var/log/installer/omnixys-early.log"
if grep -qF '$6$dialog$secret$hash' "$SANDBOX/var/log/installer/omnixys-early.log"; then
  echo "case16: password hash leaked into early log" >&2
  exit 1
fi

# --- Case 16b: no console input automatically confirms after the timeout ---
export IDENTITY_SOURCE=none
debian_render_early_script
sandboxize "$EARLY" "$SANDBOX/case16b-early.sh"
reset_sandbox
: >"$DEBCONF_UI_LOG"
mkdir -p "$SANDBOX/dev"
: >"$SANDBOX/dev/console"
mkfifo "$OMNIXYS_IDENTITY_CONSOLE_INPUT"
(sleep 3 >"$OMNIXYS_IDENTITY_CONSOLE_INPUT") &
console_writer_pid=$!
timeout_started=$SECONDS
run_early "$SANDBOX/case16b-early.sh"
timeout_elapsed=$((SECONDS - timeout_started))
kill "$console_writer_pid" 2>/dev/null || true
wait "$console_writer_pid" 2>/dev/null || true
if ((timeout_elapsed >= 3)); then
  echo "case16b: console gate waited for input instead of timing out" >&2
  exit 1
fi
grep -q 'identity values automatically confirmed after 5 seconds without input' "$SANDBOX/var/log/installer/omnixys-early.log"
grep -q 'identity confirmation: values saved without editing' "$SANDBOX/var/log/installer/omnixys-early.log"
[[ -f "$SANDBOX/var/lib/omnixys/identity.env" ]]
[[ ! -s "$DEBCONF_UI_LOG" ]]

# --- Case 17: static network values reach the final target configuration ---
export IDENTITY_CONFIRM=false
export NETWORK_INTERFACE=eth0
export STATIC_IP=192.168.2.101/24
export STATIC_ROUTERS=192.168.2.1
export STATIC_DNS="192.168.2.1 1.1.1.1"
debian_render_network_late_script
LATE_COMMAND="$(debian_compose_late_command)"
debian_render_template "$ROOT_DIR/templates/debian-preseed.cfg.template" "$PRESEED"
grep -q 'sh /cdrom/omnixys-network-late.sh' "$PRESEED"
if grep -q 'static ip_address=' "$PRESEED"; then
  echo "case17: inline dhcpcd rendering remains in preseed.cfg" >&2
  exit 1
fi
STATIC_TARGET="$SANDBOX/case17-target"
mkdir -p "$STATIC_TARGET/etc"
OMNIXYS_TARGET_ROOT="$STATIC_TARGET" OMNIXYS_IDENTITY_ENV="$SANDBOX/missing-identity.env" "$NETWORK_LATE"
grep -q '^interface eth0$' "$STATIC_TARGET/etc/dhcpcd.conf"
grep -q '^static ip_address=192.168.2.101/24$' "$STATIC_TARGET/etc/dhcpcd.conf"
grep -q '^static routers=192.168.2.1$' "$STATIC_TARGET/etc/dhcpcd.conf"
grep -q '^static domain_name_servers=192.168.2.1 1.1.1.1$' "$STATIC_TARGET/etc/dhcpcd.conf"
if grep -qE '\$\{?INSTALL_|INSTALL_STATIC|INSTALL_NETWORK' "$STATIC_TARGET/etc/dhcpcd.conf"; then
  echo "case17: unresolved network variable reached target dhcpcd.conf" >&2
  exit 1
fi

# --- Case 18: runtime identity overrides build-time network defaults ---
RUNTIME_TARGET="$SANDBOX/case18-target"
mkdir -p "$RUNTIME_TARGET/etc"
cat >"$SANDBOX/case18-identity.env" <<'EOF'
OMNIXYS_NETWORK_INTERFACE=enp1s0
OMNIXYS_STATIC_IP=10.20.30.40/24
OMNIXYS_STATIC_ROUTERS=10.20.30.1
OMNIXYS_STATIC_DNS="10.20.30.1 9.9.9.9"
EOF
OMNIXYS_TARGET_ROOT="$RUNTIME_TARGET" OMNIXYS_IDENTITY_ENV="$SANDBOX/case18-identity.env" "$NETWORK_LATE"
grep -q '^interface enp1s0$' "$RUNTIME_TARGET/etc/dhcpcd.conf"
grep -q '^static ip_address=10.20.30.40/24$' "$RUNTIME_TARGET/etc/dhcpcd.conf"

# Explicitly empty runtime keys can switch static build defaults back to DHCP.
CLEAR_TARGET="$SANDBOX/case18-clear-target"
mkdir -p "$CLEAR_TARGET/etc"
cat >"$SANDBOX/case18-clear-identity.env" <<'EOF'
OMNIXYS_NETWORK_INTERFACE=
OMNIXYS_STATIC_IP=
OMNIXYS_STATIC_ROUTERS=
OMNIXYS_STATIC_DNS=
EOF
OMNIXYS_TARGET_ROOT="$CLEAR_TARGET" OMNIXYS_IDENTITY_ENV="$SANDBOX/case18-clear-identity.env" "$NETWORK_LATE"
[[ ! -f "$CLEAR_TARGET/etc/dhcpcd.conf" ]]

# --- Case 19: DHCP leaves no Omnixys static block ---
unset NETWORK_INTERFACE STATIC_IP STATIC_ROUTERS STATIC_DNS
debian_render_network_late_script
DHCP_TARGET="$SANDBOX/case19-target"
mkdir -p "$DHCP_TARGET/etc"
printf '# base dhcpcd configuration\n' >"$DHCP_TARGET/etc/dhcpcd.conf"
OMNIXYS_TARGET_ROOT="$DHCP_TARGET" OMNIXYS_IDENTITY_ENV="$SANDBOX/missing-identity.env" "$NETWORK_LATE"
grep -q '^# base dhcpcd configuration$' "$DHCP_TARGET/etc/dhcpcd.conf"
if grep -q '^static ' "$DHCP_TARGET/etc/dhcpcd.conf"; then
  echo "case19: DHCP unexpectedly contains static configuration" >&2
  exit 1
fi

# --- Case 20: partial static configuration fails closed ---
export NETWORK_INTERFACE=eth0
debian_render_network_late_script
set +e
OMNIXYS_TARGET_ROOT="$SANDBOX/case20-target" OMNIXYS_IDENTITY_ENV="$SANDBOX/missing-identity.env" "$NETWORK_LATE" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]]

# --- Case 21: unresolved INSTALL_* expression fails closed ---
export STATIC_IP='$INSTALL_STATIC_IP'
export STATIC_ROUTERS=192.168.2.1
export STATIC_DNS=192.168.2.1
debian_render_network_late_script
set +e
OMNIXYS_TARGET_ROOT="$SANDBOX/case21-target" OMNIXYS_IDENTITY_ENV="$SANDBOX/missing-identity.env" "$NETWORK_LATE" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]]

unset NETWORK_INTERFACE STATIC_IP STATIC_ROUTERS STATIC_DNS
debian_render_network_late_script
shellcheck "$EARLY" "$NETWORK_LATE"

echo "Identity mechanism tests passed"
