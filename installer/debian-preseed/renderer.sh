#!/usr/bin/env bash

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

shell_single_quote() {
  local escaped
  escaped="$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
  printf "'%s'" "$escaped"
}

debian_render_template() {
  local template="$1"
  local output="$2"

  local esc_fullname esc_ssh_key esc_late_command esc_tasksel esc_pkgsel esc_anna_modules esc_finish_action esc_preseed_early_command esc_partman_early_command
  esc_fullname="$(escape_sed_replacement "$FULLNAME")"
  esc_ssh_key="$(escape_sed_replacement "${SSH_PUBLIC_KEY:-}")"
  esc_late_command="$(escape_sed_replacement "$LATE_COMMAND")"
  esc_tasksel="$(escape_sed_replacement "$TASKSEL_FIRST")"
  esc_pkgsel="$(escape_sed_replacement "$PKGSEL_INCLUDE")"
  esc_anna_modules="$(escape_sed_replacement "$ANNA_MODULES")"
  esc_finish_action="$(escape_sed_replacement "$FINISH_ACTION")"
  esc_preseed_early_command="$(escape_sed_replacement "$PRESEED_EARLY_COMMAND")"
  esc_partman_early_command="$(escape_sed_replacement "${PARTMAN_EARLY_COMMAND:-sh /cdrom/omnixys-partman.sh}")"

  sed \
    -e "s|__HOSTNAME__|$HOSTNAME|g" \
    -e "s|__DOMAIN__|$DOMAIN|g" \
    -e "s|__FULLNAME__|$esc_fullname|g" \
    -e "s|__USERNAME__|$USERNAME|g" \
    -e "s|__PASSWORD_HASH__|$PASSWORD_HASH|g" \
    -e "s|__LANGUAGE__|$LANGUAGE|g" \
    -e "s|__COUNTRY__|$COUNTRY|g" \
    -e "s|__LOCALE__|$LOCALE|g" \
    -e "s|__KEYBOARD__|$KEYBOARD|g" \
    -e "s|__TIMEZONE__|$TIMEZONE|g" \
    -e "s|__TARGET_DISK__|$RESOLVED_TARGET_DISK|g" \
    -e "s|__PRESEED_EARLY_COMMAND__|$esc_preseed_early_command|g" \
    -e "s|__PARTMAN_EARLY_COMMAND__|$esc_partman_early_command|g" \
    -e "s|__FILESYSTEM__|$FILESYSTEM|g" \
    -e "s|__PARTMAN_METHOD__|$PARTMAN_METHOD|g" \
    -e "s|__APT_MIRROR__|$APT_MIRROR|g" \
    -e "s|__SSH_PUBLIC_KEY__|$esc_ssh_key|g" \
    -e "s|__SSH_PASSWORD_AUTH__|$SSH_PASSWORD_AUTH|g" \
    -e "s|__SSH_PERMIT_ROOT_LOGIN__|$SSH_PERMIT_ROOT_LOGIN|g" \
    -e "s|__INSTALL_OPENSSH__|$INSTALL_OPENSSH|g" \
    -e "s|__INSTALL_STANDARD_UTILITIES__|$INSTALL_STANDARD_UTILITIES|g" \
    -e "s|__TASKSEL_FIRST__|$esc_tasksel|g" \
    -e "s|__PKGSEL_INCLUDE__|$esc_pkgsel|g" \
    -e "s|__PKGSEL_UPGRADE__|$PKGSEL_UPGRADE|g" \
    -e "s|__ANNA_MODULES__|$esc_anna_modules|g" \
    -e "s|__LATE_COMMAND__|$esc_late_command|g" \
    -e "s|__FINISH_ACTION__|$esc_finish_action|g" \
    "$template" | while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == "__PARTMAN_RECIPE_DIRECTIVE__" ]]; then
        printf '%s\n' "$PARTMAN_RECIPE_DIRECTIVE"
      else
        printf '%s\n' "$line"
      fi
    done >"$output"
}

debian_compose_tasksel() {
  local tasksel=""
  if [[ "$INSTALL_STANDARD_UTILITIES" == "true" ]]; then
    tasksel="standard"
  fi
  printf '%s' "$tasksel"
}

debian_compose_pkgsel() {
  local include_pkgs=""
  if [[ "$INSTALL_OPENSSH" == "true" ]]; then
    include_pkgs="openssh-server"
  fi
  if [[ "$INSTALL_FIRMWARE" == "true" ]]; then
    include_pkgs="${include_pkgs:+$include_pkgs }firmware-linux firmware-misc-nonfree"
  fi
  printf '%s' "$include_pkgs"
}

debian_compose_anna_modules() {
  case "$FILESYSTEM" in
    xfs) echo "partman-xfs" ;;
    btrfs) echo "partman-btrfs" ;;
    *) echo "" ;;
  esac
}

debian_compose_late_command() {
  local cmd
  local ssh_password_auth_value="no"
  local sudo_nopasswd="${SUDO_NOPASSWD:-true}"
  if [[ "$SSH_PASSWORD_AUTH" == "true" ]]; then
    ssh_password_auth_value="yes"
  fi

  cmd="in-target sed -ri 's|^#?PermitRootLogin[[:space:]]+.*|PermitRootLogin ${SSH_PERMIT_ROOT_LOGIN}|' /etc/ssh/sshd_config; "
  cmd+="in-target sed -ri 's|^#?PasswordAuthentication[[:space:]]+.*|PasswordAuthentication ${ssh_password_auth_value}|' /etc/ssh/sshd_config; "
  cmd+="in-target systemctl enable ssh || true"
  cmd+="; in-target apt-get update"
  cmd+="; in-target DEBIAN_FRONTEND=noninteractive apt-get -y upgrade"

  # Start with build-time values as unconditional defaults.
  cmd+="; INSTALL_USER=\"${USERNAME}\""
  cmd+="; INSTALL_SSH_KEY=\"${SSH_PUBLIC_KEY:-}\""
  cmd+="; INSTALL_HOSTNAME=\"${HOSTNAME}\""

  # Allow identity.env runtime overrides when present (e.g. USB-based identity).
  cmd+="; if [ -r /var/lib/omnixys/identity.env ]; then . /var/lib/omnixys/identity.env; [ -n \"\${OMNIXYS_USERNAME:-}\" ] && INSTALL_USER=\"\$OMNIXYS_USERNAME\"; [ -n \"\${OMNIXYS_SSH_PUBLIC_KEY:-}\" ] && INSTALL_SSH_KEY=\"\$OMNIXYS_SSH_PUBLIC_KEY\"; [ -n \"\${OMNIXYS_HOSTNAME:-}\" ] && INSTALL_HOSTNAME=\"\$OMNIXYS_HOSTNAME\"; fi"

  if [[ "$sudo_nopasswd" == "true" ]]; then
    cmd+="; in-target env INSTALL_USER=\"\$INSTALL_USER\" sh -c 'printf \"%s\\n\" \"\$INSTALL_USER ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/90-omnixys-nopasswd'"
    cmd+="; in-target chmod 440 /etc/sudoers.d/90-omnixys-nopasswd"
    cmd+="; in-target visudo -cf /etc/sudoers.d/90-omnixys-nopasswd"
  fi

  cmd+="; if [ -n \"\$INSTALL_HOSTNAME\" ]; then in-target sh -c \"printf '%s\\n' \\\"\$INSTALL_HOSTNAME\\\" > /etc/hostname\"; in-target hostnamectl set-hostname \"\$INSTALL_HOSTNAME\" >/dev/null 2>&1 || true; fi"
  cmd+="; if [ -n \"\$INSTALL_SSH_KEY\" ]; then in-target env INSTALL_USER=\"\$INSTALL_USER\" INSTALL_SSH_KEY=\"\$INSTALL_SSH_KEY\" sh -c 'mkdir -p /home/\$INSTALL_USER/.ssh; printf %s \"\$INSTALL_SSH_KEY\" > /home/\$INSTALL_USER/.ssh/authorized_keys; chown -R \$INSTALL_USER:\$INSTALL_USER /home/\$INSTALL_USER/.ssh; chmod 700 /home/\$INSTALL_USER/.ssh; chmod 600 /home/\$INSTALL_USER/.ssh/authorized_keys'; fi"

  # Keep network rendering in a standalone installer-context script. This
  # avoids passing values through preseed -> sh -c -> in-target -> sh -c.
  cmd+="; sh /cdrom/omnixys-network-late.sh"

  if [[ "$REBOOT_AFTER_INSTALL" == "true" ]]; then
    # Reduce reboot-loops into installer by ejecting/unmounting install media before reboot.
    cmd+="; echo 'Omnixys: Installation complete. Remove boot media now.' >/dev/tty1 || true"
    cmd+="; sync"
    cmd+="; umount /cdrom >/dev/null 2>&1 || true"
    cmd+="; eject -m /cdrom >/dev/null 2>&1 || eject >/dev/null 2>&1 || true"
    cmd+="; sleep 5"
  fi

  printf '%s' "$cmd"
}

debian_render_network_late_script() {
  local out="$GENERATED_DIR/omnixys-network-late.sh"
  local network_if static_ip static_routers static_dns
  network_if="$(shell_single_quote "${NETWORK_INTERFACE:-}")"
  static_ip="$(shell_single_quote "${STATIC_IP:-}")"
  static_routers="$(shell_single_quote "${STATIC_ROUTERS:-}")"
  static_dns="$(shell_single_quote "${STATIC_DNS:-}")"
  cat >"$out" <<EOF
#!/bin/sh
set -eu

TARGET_ROOT="\${OMNIXYS_TARGET_ROOT:-/target}"
IDENTITY_ENV="\${OMNIXYS_IDENTITY_ENV:-/var/lib/omnixys/identity.env}"
INSTALL_NETWORK_IF=$network_if
INSTALL_STATIC_IP=$static_ip
INSTALL_STATIC_ROUTERS=$static_routers
INSTALL_STATIC_DNS=$static_dns

log_info() {
  printf 'omnixys-network: %s\\n' "\$*" >&2
}

fail() {
  log_info "ERROR: \$*"
  exit 1
}

validate_ipv4() {
  printf '%s\\n' "\$1" | awk -F. '
    NF != 4 { exit 1 }
    {
      for (i = 1; i <= 4; i++) {
        if (\$i !~ /^[0-9]+\$/ || \$i < 0 || \$i > 255) exit 1
      }
    }
  '
}

validate_ipv4_list() {
  [ -n "\$1" ] || return 1
  for address in \$1; do
    validate_ipv4 "\$address" || return 1
  done
}

validate_static_ip() {
  address="\${1%/*}"
  prefix="\${1#*/}"
  [ "\$address" != "\$1" ] || return 1
  validate_ipv4 "\$address" || return 1
  case "\$prefix" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "\$prefix" -le 32 ]
}

if [ -r "\$IDENTITY_ENV" ]; then
  # Runtime identity is trusted installer input and overrides build defaults.
  # shellcheck disable=SC1090
  . "\$IDENTITY_ENV"
  [ "\${OMNIXYS_NETWORK_INTERFACE+x}" != "x" ] || INSTALL_NETWORK_IF="\$OMNIXYS_NETWORK_INTERFACE"
  [ "\${OMNIXYS_STATIC_IP+x}" != "x" ] || INSTALL_STATIC_IP="\$OMNIXYS_STATIC_IP"
  [ "\${OMNIXYS_STATIC_ROUTERS+x}" != "x" ] || INSTALL_STATIC_ROUTERS="\$OMNIXYS_STATIC_ROUTERS"
  [ "\${OMNIXYS_STATIC_DNS+x}" != "x" ] || INSTALL_STATIC_DNS="\$OMNIXYS_STATIC_DNS"
fi

network_value_count=0
for value in "\$INSTALL_NETWORK_IF" "\$INSTALL_STATIC_IP" "\$INSTALL_STATIC_ROUTERS" "\$INSTALL_STATIC_DNS"; do
  [ -z "\$value" ] || network_value_count=\$((network_value_count + 1))
  # shellcheck disable=SC2016
  case "\$value" in
    *'\$INSTALL_'*|*'\${INSTALL_'*) fail 'unresolved INSTALL_* expression in network configuration' ;;
  esac
done

config="\$TARGET_ROOT/etc/dhcpcd.conf"
begin_marker='# BEGIN OMNIXYS STATIC NETWORK'
end_marker='# END OMNIXYS STATIC NETWORK'
mkdir -p "\$TARGET_ROOT/etc"
tmp="\${config}.omnixys.tmp.\$\$"
trap 'rm -f "\$tmp"' EXIT HUP INT TERM

if [ -f "\$config" ]; then
  awk -v begin="\$begin_marker" -v end="\$end_marker" '
    \$0 == begin { managed = 1; next }
    \$0 == end { managed = 0; next }
    !managed { print }
  ' "\$config" >"\$tmp"
else
  : >"\$tmp"
fi

if grep -Eq '\\$\\{?INSTALL_|INSTALL_STATIC|INSTALL_NETWORK' "\$tmp"; then
  fail 'unresolved network variable already present in target configuration'
fi

case "\$network_value_count" in
  0)
    if [ -f "\$config" ]; then
      cat "\$tmp" >"\$config"
    fi
    rm -f "\$tmp"
    trap - EXIT HUP INT TERM
    log_info 'DHCP selected; no static configuration written'
    exit 0
    ;;
  4) ;;
  *) fail 'static network configuration requires interface, IP/CIDR, router and DNS' ;;
esac

printf '%s\\n' "\$INSTALL_NETWORK_IF" | grep -Eq '^[[:alnum:]_.:-]{1,15}\$' || fail 'invalid network interface'
validate_static_ip "\$INSTALL_STATIC_IP" || fail 'invalid static IPv4/CIDR'
validate_ipv4_list "\$INSTALL_STATIC_ROUTERS" || fail 'invalid static router list'
validate_ipv4_list "\$INSTALL_STATIC_DNS" || fail 'invalid static DNS list'

{
  printf '\\n%s\\n' "\$begin_marker"
  printf 'interface %s\\n' "\$INSTALL_NETWORK_IF"
  printf 'static ip_address=%s\\n' "\$INSTALL_STATIC_IP"
  printf 'static routers=%s\\n' "\$INSTALL_STATIC_ROUTERS"
  printf 'static domain_name_servers=%s\\n' "\$INSTALL_STATIC_DNS"
  printf '%s\\n' "\$end_marker"
} >>"\$tmp"

if grep -Eq '\\$\\{?INSTALL_|INSTALL_STATIC|INSTALL_NETWORK' "\$tmp"; then
  fail 'unresolved network variable remained in target configuration'
fi

cat "\$tmp" >"\$config"
chmod 0644 "\$config"
rm -f "\$tmp"
trap - EXIT HUP INT TERM
log_info 'static dhcpcd configuration written and validated'
EOF
  chmod +x "$out"
}

debian_compose_pkgsel_upgrade() {
  if [[ "$INSTALL_UPDATES" == "true" ]]; then
    echo "safe-upgrade"
  else
    echo "none"
  fi
}

debian_compose_finish_action() {
  if [[ "$REBOOT_AFTER_INSTALL" == "true" ]]; then
    echo "d-i finish-install/reboot_in_progress note"
  else
    echo "d-i debian-installer/exit/halt boolean true"
  fi
}

debian_resolve_password_hash() {
  if [[ -n "${PASSWORD_HASH:-}" ]]; then
    return 0
  fi

  if [[ -n "${PASSWORD:-}" ]]; then
    PASSWORD_HASH="$(openssl passwd -6 "$PASSWORD")"
    return 0
  fi

  if [[ "$IDENTITY_SOURCE" != "none" && "$IDENTITY_REQUIRED" == "true" ]]; then
    PASSWORD_HASH='!'
    return 0
  fi

  die "Unable to resolve PASSWORD_HASH: set PASSWORD, PASSWORD_HASH, or provide required runtime identity"
}

debian_partition_mode_values() {
  case "$PARTITION_MODE" in
    erase)
      PARTMAN_METHOD="regular"
      if [[ "$TARGET_DISK_MODE" == "auto" ]]; then
        PARTMAN_RECIPE_DIRECTIVE="$(debian_compose_expert_recipe_preseed bios)"
      else
        PARTMAN_RECIPE_DIRECTIVE="d-i partman-auto/choose_recipe select atomic"
      fi
      ;;
    lvm)
      PARTMAN_METHOD="lvm"
      PARTMAN_RECIPE_DIRECTIVE="d-i partman-auto/choose_recipe select atomic"
      ;;
    *)
      die "Unsupported PARTITION_MODE in renderer: $PARTITION_MODE"
      ;;
  esac
}

debian_compose_expert_recipe() {
  local firmware="$1"
  case "$firmware" in
    uefi)
      cat <<EOF
omnixys-erase ::
768 788 1024 free
  \$primary{ }
  \$iflabel{ gpt }
  \$reusemethod{ }
  method{ efi }
  format{ }
  mountpoint{ /boot/efi } .
8000 10000 -1 $FILESYSTEM
  \$primary{ }
  method{ format }
  format{ }
  use_filesystem{ }
  filesystem{ $FILESYSTEM }
  mountpoint{ / } .
500 550 100% linux-swap
  \$reusemethod{ }
  method{ swap }
  format{ } .
EOF
      ;;
    bios)
      cat <<EOF
omnixys-erase ::
1 1 1 free
  \$primary{ }
  \$iflabel{ gpt }
  \$reusemethod{ }
  method{ biosgrub } .
8000 10000 -1 $FILESYSTEM
  \$primary{ }
  method{ format }
  format{ }
  use_filesystem{ }
  filesystem{ $FILESYSTEM }
  mountpoint{ / } .
500 550 100% linux-swap
  \$reusemethod{ }
  method{ swap }
  format{ } .
EOF
      ;;
    *) die "Unsupported firmware recipe: $firmware" ;;
  esac
}

debian_compose_expert_recipe_preseed() {
  local firmware="$1"
  local recipe line
  recipe="$(debian_compose_expert_recipe "$firmware")"
  printf 'd-i partman-auto/expert_recipe string \\\n'
  while [[ "$recipe" == *$'\n'* ]]; do
    line="${recipe%%$'\n'*}"
    printf '  %s \\\n' "$line"
    recipe="${recipe#*$'\n'}"
  done
  printf '  %s\n' "$recipe"
}

debian_render_partman_script() {
  local out="$GENERATED_DIR/omnixys-partman.sh"
  {
    printf '%s\n' '#!/bin/sh' 'set -eu'
    printf 'PARTITION_MODE=%s\n' "$(shell_single_quote "$PARTITION_MODE")"
    printf 'TARGET_DISK_MODE=%s\n' "$(shell_single_quote "$TARGET_DISK_MODE")"
    printf 'TARGET_DISK=%s\n' "$(shell_single_quote "${TARGET_DISK:-}")"
    printf 'TARGET_DISK_BY_ID=%s\n' "$(shell_single_quote "${TARGET_DISK_BY_ID:-}")"
    printf 'IDENTITY_DEVICE_LABEL=%s\n' "$(shell_single_quote "${IDENTITY_DEVICE_LABEL:-OMNIXYS_ID}")"
    printf '%s\n' '# shellcheck disable=SC2016 # partman recipe tokens are literal'
    printf 'UEFI_RECIPE=%s\n' "$(shell_single_quote "$(debian_compose_expert_recipe uefi)")"
    printf '%s\n' '# shellcheck disable=SC2016 # partman recipe tokens are literal'
    printf 'BIOS_RECIPE=%s\n' "$(shell_single_quote "$(debian_compose_expert_recipe bios)")"
    cat <<'EOF'

DEV_ROOT="${OMNIXYS_DEV_ROOT:-/dev}"
SYS_BLOCK_ROOT="${OMNIXYS_SYS_BLOCK_ROOT:-/sys/block}"
PROC_MOUNTS="${OMNIXYS_PROC_MOUNTS:-/proc/mounts}"
EFI_ROOT="${OMNIXYS_EFI_ROOT:-/sys/firmware/efi}"
TEST_MODE="${OMNIXYS_PARTMAN_TEST_MODE:-false}"
WIPE_LOG="${OMNIXYS_WIPE_LOG:-}"
DEV_ROOT="$(readlink -f "$DEV_ROOT" 2>/dev/null || printf '%s' "$DEV_ROOT")"
SYS_BLOCK_ROOT="$(readlink -f "$SYS_BLOCK_ROOT" 2>/dev/null || printf '%s' "$SYS_BLOCK_ROOT")"

if [ -n "${OMNIXYS_PARTMAN_LOG:-}" ]; then
  exec >"$OMNIXYS_PARTMAN_LOG" 2>&1
else
  mkdir -p /var/log/installer
  exec >/var/log/installer/omnixys-partman.log 2>&1
fi

log_info() {
  printf 'omnixys-partman: %s\n' "$*"
}

fail() {
  log_info "ERROR: $*"
  exit 1
}

normalize_parent() {
  dev="$1"
  case "$dev" in
    /dev/nvme*n*p[0-9]*) printf '%s\n' "${dev%p[0-9]*}" ;;
    /dev/mmcblk*p[0-9]*) printf '%s\n' "${dev%p[0-9]*}" ;;
    /dev/nvme*n[0-9]|/dev/mmcblk[0-9]*) printf '%s\n' "$dev" ;;
    /dev/sd[a-z][0-9]*|/dev/vd[a-z][0-9]*|/dev/xvd[a-z][0-9]*) printf '%s\n' "${dev%%[0-9]*}" ;;
    *) printf '%s\n' "$dev" ;;
  esac
}

is_ignored_base() {
  case "$1" in
    loop*|ram*|fd*|sr*) return 0 ;;
    *) return 1 ;;
  esac
}

device_path() {
  printf '%s/%s\n' "${DEV_ROOT%/}" "${1#/dev/}"
}

device_exists() {
  path="$(device_path "$1")"
  if [ "$TEST_MODE" = "true" ]; then
    [ -e "$path" ]
  else
    [ -b "$path" ]
  fi
}

EXCLUDED=""
add_excluded() {
  parent="$(normalize_parent "$1")"
  reason="$2"
  case "$parent" in
    /dev/*)
      record="${parent}|${reason}"
      if ! printf '%b' "$EXCLUDED" | grep -Fxq "$record"; then
        EXCLUDED="${EXCLUDED}${record}\n"
      fi
      ;;
  esac
}

is_excluded() {
  printf '%b' "$EXCLUDED" | awk -F '|' -v disk="$1" '$1 == disk { found=1 } END { exit !found }'
}

log_excluded() {
  log_info "Excluded disks:"
  if [ -z "$EXCLUDED" ]; then
    log_info "  (none)"
    return 0
  fi
  printf '%b' "$EXCLUDED" | while IFS='|' read -r disk reason; do
    [ -n "$disk" ] || continue
    log_info "  $disk -> $reason"
  done
}

log_disk_list() {
  heading="$1"
  disks="$2"
  log_info "$heading:"
  if [ -z "$disks" ]; then
    log_info "  (none)"
    return 0
  fi
  printf '%s\n' "$disks" | while IFS= read -r disk; do
    [ -n "$disk" ] || continue
    log_info "  $disk"
  done
}

collect_mounted_exclusions() {
  [ -r "$PROC_MOUNTS" ] || fail "mount table unavailable: $PROC_MOUNTS"
  while read -r source mountpoint fstype rest; do
    case "$source" in
      /dev/*)
        if [ "$mountpoint" = "/cdrom" ]; then
          add_excluded "$source" "parent of /cdrom"
        elif [ "$mountpoint" = "/hd-media" ]; then
          add_excluded "$source" "parent of /hd-media"
        elif [ "$fstype" = "iso9660" ]; then
          add_excluded "$source" "ISO9660 filesystem mounted at $mountpoint"
        else
          add_excluded "$source" "mounted at $mountpoint ($fstype)"
        fi
        ;;
    esac
  done <"$PROC_MOUNTS"

  label_path="${DEV_ROOT%/}/disk/by-label/$IDENTITY_DEVICE_LABEL"
  identity_resolved=""
  if [ -e "$label_path" ]; then
    identity_resolved="$(readlink -f "$label_path" 2>/dev/null || true)"
  elif [ "$DEV_ROOT" = "/dev" ] && command -v findfs >/dev/null 2>&1; then
    identity_resolved="$(findfs "LABEL=$IDENTITY_DEVICE_LABEL" 2>/dev/null || true)"
  fi
  if [ -n "$identity_resolved" ]; then
    case "$identity_resolved" in
      "${DEV_ROOT%/}"/*)
        identity_resolved="${identity_resolved#"${DEV_ROOT%/}"}"
        add_excluded "/dev$identity_resolved" "OMNIXYS_ID label"
        ;;
      /dev/*) add_excluded "$identity_resolved" "OMNIXYS_ID label" ;;
    esac
  fi
}

is_usb_disk() {
  disk="$1"
  base="${disk#/dev/}"
  sys_device="$(readlink -f "$SYS_BLOCK_ROOT/$base/device" 2>/dev/null || true)"
  case "$sys_device" in
    */usb*/*|*/usb*) USB_REASON="USB sysfs path: $sys_device"; return 0 ;;
  esac
  if command -v udevadm >/dev/null 2>&1 && udevadm info --query=property --name="$(device_path "$disk")" 2>/dev/null | grep -q '^ID_BUS=usb$'; then
    USB_REASON="ID_BUS=usb"
    return 0
  fi
  return 1
}

is_safe_internal() {
  disk="$1"
  base="${disk#/dev/}"
  if is_ignored_base "$base"; then
    add_excluded "$disk" "ignored device class"
    return 1
  fi
  if ! device_exists "$disk"; then
    add_excluded "$disk" "device missing or not a block device"
    return 1
  fi
  is_excluded "$disk" && return 1
  if [ ! -r "$SYS_BLOCK_ROOT/$base/removable" ]; then
    add_excluded "$disk" "missing removable sysfs attribute"
    return 1
  fi
  removable="$(cat "$SYS_BLOCK_ROOT/$base/removable" 2>/dev/null || true)"
  case "$removable" in
    0) ;;
    1) add_excluded "$disk" "removable=1"; return 1 ;;
    *) add_excluded "$disk" "invalid removable value: ${removable:-empty}"; return 1 ;;
  esac
  USB_REASON=""
  if is_usb_disk "$disk"; then
    add_excluded "$disk" "$USB_REASON"
    return 1
  fi
  return 0
}

collect_internal_pool() {
  collect_mounted_exclusions
  all_disks="$(list-devices disk 2>/dev/null || true)"
  log_disk_list "Detected disks" "$all_disks"
  if [ -z "$all_disks" ]; then
    log_excluded
    log_disk_list "Internal disks" ""
    fail "No eligible internal installation disk found (list-devices returned no disks)"
  fi
  INTERNAL_POOL=""
  for disk in $all_disks; do
    parent="$(normalize_parent "$disk")"
    if [ "$parent" != "$disk" ]; then
      add_excluded "$disk" "not a whole disk"
    elif is_safe_internal "$disk"; then
      INTERNAL_POOL="${INTERNAL_POOL}${disk}\n"
    fi
  done
  INTERNAL_POOL="$(printf '%b' "$INTERNAL_POOL" | sed '/^$/d' | sort -u)"
  log_excluded
  log_disk_list "Internal disks" "$INTERNAL_POOL"
  [ -n "$INTERNAL_POOL" ] || fail "No eligible internal installation disk found"
}

disk_size_sectors() {
  disk="$1"
  base="${disk#/dev/}"
  size_file="${SYS_BLOCK_ROOT}/${base}/size"

  [ -r "$size_file" ] || return 1

  size="$(cat "$size_file")"
  case "$size" in
    ''|*[!0-9]*) return 1 ;;
  esac

  [ "$size" -gt 0 ] || return 1

  printf '%s\n' "$size"
}

select_system_disk() {
  TARGET=""
  BEST=""
  for disk in $INTERNAL_POOL; do
    [ -n "$disk" ] || continue
    size="$(disk_size_sectors "$disk")" || {
      log_info "Skipping system-disk candidate with invalid size: $disk"
      continue
    }
    if [ -z "$BEST" ] || [ "$size" -lt "$BEST" ]; then
      BEST="$size"
      TARGET="$disk"
    fi
  done
  [ -n "$TARGET" ] || fail "unable to select system disk (no candidate with a valid size)"
  is_safe_internal "$TARGET" || fail "selected system disk is no longer safe: $TARGET"
  log_info "Selected system disk: $TARGET"
}

partitions_present() {
  disk="$1"
  base="${disk#/dev/}"
  for entry in "$SYS_BLOCK_ROOT/$base"/*; do
    [ -e "$entry" ] || continue
    [ ! -r "$entry/partition" ] || return 0
  done
  return 1
}

reread_partition_table() {
  disk="$1"
  path="$(device_path "$disk")"
  log_info "Partition-table reread start: $disk"
  if [ "$TEST_MODE" = "true" ]; then
    [ "${OMNIXYS_FAIL_REREAD_DISK:-}" != "$disk" ] || fail "partition table reread failed: $disk"
    [ "${OMNIXYS_STALE_PARTITIONS_DISK:-}" != "$disk" ] || fail "stale partitions remain after reread: $disk"
    log_info "Partition-table reread result: success ($disk)"
    return 0
  fi

  reread_ok="false"
  if command -v blockdev >/dev/null 2>&1 && blockdev --rereadpt "$path"; then
    reread_ok="true"
    log_info "Partition-table reread method: blockdev --rereadpt"
  elif command -v partprobe >/dev/null 2>&1 && partprobe "$path"; then
    reread_ok="true"
    log_info "Partition-table reread method: partprobe"
  fi
  [ "$reread_ok" = "true" ] || fail "partition table reread failed: $disk"

  if command -v udevadm >/dev/null 2>&1; then
    udevadm settle 2>/dev/null || true
  fi
  retry=0
  while partitions_present "$disk" && [ "$retry" -lt 5 ]; do
    sleep 1
    retry=$((retry + 1))
  done
  partitions_present "$disk" && fail "stale partitions remain after reread: $disk"
  log_info "Partition-table reread result: success ($disk)"
}

wipe_disk() {
  disk="$1"
  is_safe_internal "$disk" || fail "refusing to wipe protected or unsafe disk: $disk"
  log_info "Wipe start: $disk"
  if [ "$TEST_MODE" = "true" ]; then
    [ -n "$WIPE_LOG" ] || fail "test mode requires OMNIXYS_WIPE_LOG"
    printf '%s\n' "$disk" >>"$WIPE_LOG"
    [ "${OMNIXYS_FAIL_WIPE_DISK:-}" != "$disk" ] || fail "simulated wipe failure: $disk"
    log_info "Wipe method: simulated ($disk)"
    log_info "Wipe result: success ($disk)"
    reread_partition_table "$disk"
    return 0
  fi

  path="$(device_path "$disk")"
  log_info "wiping partition tables and signatures on $disk"
  if command -v wipefs >/dev/null 2>&1; then
    wipefs --all --force "$path" || fail "wipefs failed: $disk"
  fi
  if command -v blkdiscard >/dev/null 2>&1 && blkdiscard -f "$path"; then
    log_info "Wipe method: blkdiscard ($disk)"
  else
    dd if=/dev/zero of="$path" bs=512 count=32768 conv=fsync || fail "head wipe failed: $disk"
    sectors="$(cat "$SYS_BLOCK_ROOT/${disk#/dev/}/size" 2>/dev/null || true)"
    case "$sectors" in
      ''|*[!0-9]*) fail "invalid disk size for tail wipe: $disk" ;;
    esac
    [ "$sectors" -gt 32768 ] || fail "disk too small for safe tail wipe: $disk"
    tail_seek=$((sectors - 32768))
    dd if=/dev/zero of="$path" bs=512 seek="$tail_seek" count=32768 conv=fsync || fail "tail wipe failed: $disk"
    log_info "Wipe method: head/tail dd ($disk)"
  fi
  sync
  log_info "Wipe result: success ($disk)"
  reread_partition_table "$disk"
}

set_recipe() {
  [ "$PARTITION_MODE" = "erase" ] || return 0
  [ "$TARGET_DISK_MODE" = "auto" ] || {
    log_info "Selected recipe: atomic (built-in)"
    return 0
  }
  if [ -d "$EFI_ROOT" ]; then
    recipe="$UEFI_RECIPE"
    recipe_name="UEFI/GPT"
  else
    recipe="$BIOS_RECIPE"
    recipe_name="BIOS/GPT"
  fi
  debconf-set partman-auto/expert_recipe "$recipe" || fail "unable to set expert recipe"
  log_info "Selected recipe: $recipe_name"
}

set_target() {
  target="$1"
  device_exists "$target" || fail "target is not a block device: $target"
  debconf-set partman-auto/disk "$target" || fail "unable to set partman target: $target"
  log_info "partman-auto/disk: $target"
  debconf-set grub-installer/bootdev "$target" || fail "unable to set grub target: $target"
  log_info "grub-installer/bootdev: $target"
}

validate_explicit_target() {
  target="$1"
  log_info "Detected disks:"
  log_info "  $target (explicit target)"
  collect_mounted_exclusions
  if [ "$(normalize_parent "$target")" != "$target" ]; then
    add_excluded "$target" "not a whole disk"
    log_excluded
    log_disk_list "Internal disks" ""
    fail "target is not a whole disk: $target"
  fi
  if ! is_safe_internal "$target"; then
    log_excluded
    log_disk_list "Internal disks" ""
    fail "explicit target is protected or unsafe: $target"
  fi
}

log_explicit_target() {
  target="$1"
  log_excluded
  log_info "Internal disks:"
  log_info "  $target"
  log_disk_list "Wipe candidates" ""
  log_info "Selected system disk: $target"
}

log_info "Partition mode: $PARTITION_MODE"
log_info "Target disk mode: $TARGET_DISK_MODE"
set_recipe
case "$TARGET_DISK_MODE" in
  auto)
    collect_internal_pool
    if [ "$PARTITION_MODE" = "erase" ]; then
      log_disk_list "Wipe candidates" "$INTERNAL_POOL"
      printf '%s\n' "$INTERNAL_POOL" | while IFS= read -r disk; do
        wipe_disk "$disk"
      done
    else
      log_disk_list "Wipe candidates" ""
    fi
    select_system_disk
    set_target "$TARGET"
    ;;
  by-id)
    by_id_path="$TARGET_DISK_BY_ID"
    if [ "$DEV_ROOT" != "/dev" ]; then
      by_id_path="$(device_path "$TARGET_DISK_BY_ID")"
    fi
    resolved="$(readlink -f "$by_id_path" 2>/dev/null || true)"
    case "$resolved" in
      "${DEV_ROOT%/}"/*)
        resolved="${resolved#"${DEV_ROOT%/}"}"
        resolved="/dev$resolved"
        ;;
    esac
    [ -n "$resolved" ] || fail "by-id target not resolvable"
    validate_explicit_target "$resolved"
    log_explicit_target "$resolved"
    set_target "$resolved"
    ;;
  manual)
    validate_explicit_target "$TARGET_DISK"
    log_explicit_target "$TARGET_DISK"
    set_target "$TARGET_DISK"
    ;;
  *) fail "unsupported target disk mode: $TARGET_DISK_MODE" ;;
esac
EOF
  } >"$out"
  chmod +x "$out"
}

debian_render_early_script() {
  local out="$GENERATED_DIR/omnixys-early.sh"
  local identity_hostname identity_domain identity_fullname identity_username identity_ssh_key identity_password_hash
  local identity_network_if identity_static_ip identity_static_routers identity_static_dns
  identity_hostname="$(shell_single_quote "$HOSTNAME")"
  identity_domain="$(shell_single_quote "${DOMAIN:-}")"
  identity_fullname="$(shell_single_quote "$FULLNAME")"
  identity_username="$(shell_single_quote "$USERNAME")"
  identity_ssh_key="$(shell_single_quote "${SSH_PUBLIC_KEY:-}")"
  identity_password_hash="$(shell_single_quote "$PASSWORD_HASH")"
  identity_network_if="$(shell_single_quote "${NETWORK_INTERFACE:-}")"
  identity_static_ip="$(shell_single_quote "${STATIC_IP:-}")"
  identity_static_routers="$(shell_single_quote "${STATIC_ROUTERS:-}")"
  identity_static_dns="$(shell_single_quote "${STATIC_DNS:-}")"
  cat >"$out" <<EOF
#!/bin/sh
# shellcheck disable=SC2317 # helper functions are invoked indirectly via run_step "\$@"
mkdir -p /var/log/installer
exec >/var/log/installer/omnixys-early.log 2>&1

IDENTITY_SOURCE="${IDENTITY_SOURCE:-none}"
IDENTITY_REQUIRED="${IDENTITY_REQUIRED:-false}"
IDENTITY_FILE_PATH="${IDENTITY_FILE_PATH:-/identity.env}"
IDENTITY_DEVICE_LABEL="${IDENTITY_DEVICE_LABEL:-OMNIXYS-ID}"
IDENTITY_CONFIRM="${IDENTITY_CONFIRM:-true}"
IDENTITY_CONFIRM_TIMEOUT=5
IDENTITY_CONSOLE="\${OMNIXYS_IDENTITY_CONSOLE:-/dev/console}"
IDENTITY_CONSOLE_INPUT="\${OMNIXYS_IDENTITY_CONSOLE_INPUT:-\$IDENTITY_CONSOLE}"
PROC_MOUNTS="\${OMNIXYS_PROC_MOUNTS:-/proc/mounts}"
# Detection never relies on stable Linux device names; the retry window also
# tolerates USB media that enumerate late during installer start-up.
IDENTITY_DEVICE_RETRIES="\${OMNIXYS_IDENTITY_RETRIES:-10}"
IDENTITY_DEVICE_RETRY_DELAY="\${OMNIXYS_IDENTITY_RETRY_DELAY:-1}"

OMNIXYS_HOSTNAME=$identity_hostname
OMNIXYS_DOMAIN=$identity_domain
OMNIXYS_FULLNAME=$identity_fullname
OMNIXYS_USERNAME=$identity_username
OMNIXYS_SSH_PUBLIC_KEY=$identity_ssh_key
# shellcheck disable=SC2016
OMNIXYS_PASSWORD_HASH=$identity_password_hash
OMNIXYS_NETWORK_INTERFACE=$identity_network_if
OMNIXYS_STATIC_IP=$identity_static_ip
OMNIXYS_STATIC_ROUTERS=$identity_static_routers
OMNIXYS_STATIC_DNS=$identity_static_dns

log_info() {
  printf 'omnixys: %s\\n' "\$*" >>/var/log/installer/omnixys-early.log 2>/dev/null || true
}

notify_console() {
  # Best-effort visibility on the installer console; never fatal.
  if [ -w "\$IDENTITY_CONSOLE" ]; then
    printf '\\n%s\\n' "\$*" >>"\$IDENTITY_CONSOLE" 2>/dev/null || true
  fi
  if command -v logger >/dev/null 2>&1; then
    logger -t omnixys-early -- "\$*" >/dev/null 2>&1 || true
  fi
}

abort_install() {
  log_info "ABORT: \$*"
  notify_console "Omnixys: Installation abgebrochen - \$*"
  exit 1
}

STEP_COUNT=0
run_step() {
  desc="\$1"; shift
  STEP_COUNT=\$((STEP_COUNT + 1))
  log_info "STEP \$STEP_COUNT start: \$desc (cmd: \$*)"
  rc=0
  "\$@" || rc=\$?
  if [ "\$rc" -eq 0 ]; then
    log_info "STEP \$STEP_COUNT ok: \$desc"
  else
    log_info "STEP \$STEP_COUNT FAILED rc=\$rc: \$desc (cmd: \$*)"
  fi
  return \$rc
}

detect_identity_device() {
  IDENTITY_DEVICE=""
  BY_LABEL="/dev/disk/by-label/\$IDENTITY_DEVICE_LABEL"
  n=0
  while [ "\$n" -lt "\$IDENTITY_DEVICE_RETRIES" ]; do
    if [ -e "\$BY_LABEL" ]; then
      IDENTITY_DEVICE="\$BY_LABEL"
      log_info "identity device detected: \$IDENTITY_DEVICE_LABEL"
      return 0
    fi
    n=\$((n + 1))
    if [ "\$n" -lt "\$IDENTITY_DEVICE_RETRIES" ] && [ "\$IDENTITY_DEVICE_RETRY_DELAY" -gt 0 ] 2>/dev/null; then
      sleep "\$IDENTITY_DEVICE_RETRY_DELAY"
    fi
  done

  log_info "identity device not detected via /dev/disk/by-label/\$IDENTITY_DEVICE_LABEL; trying label resolver fallback"
  if command -v findfs >/dev/null 2>&1; then
    RES="\$(findfs "LABEL=\$IDENTITY_DEVICE_LABEL" 2>/dev/null || true)"
    if [ -n "\$RES" ]; then
      IDENTITY_DEVICE="\$RES"
      log_info "identity device resolved via findfs"
      return 0
    fi
  fi
  if [ -z "\$IDENTITY_DEVICE" ] && command -v blkid >/dev/null 2>&1; then
    RES="\$(blkid -L "\$IDENTITY_DEVICE_LABEL" 2>/dev/null || true)"
    if [ -n "\$RES" ]; then
      IDENTITY_DEVICE="\$RES"
      log_info "identity device resolved via blkid -L"
      return 0
    fi
  fi
  if [ -z "\$IDENTITY_DEVICE" ] && command -v blkid >/dev/null 2>&1; then
    # Whole-disk media without a partition table must be found as well, so the
    # scan covers partitioned and partition-less device names alike.
    for cand in \\
/dev/sd[a-z][0-9]* /dev/sd[a-z] \\
/dev/vd[a-z][0-9]* /dev/vd[a-z] \\
/dev/xvd[a-z][0-9]* /dev/xvd[a-z] \\
/dev/nvme[0-9]*n[0-9]*p[0-9]* /dev/nvme[0-9]*n[0-9] \\
/dev/mmcblk[0-9]*p[0-9]* /dev/mmcblk[0-9]*; do
      [ -b "\$cand" ] || continue
      if blkid "\$cand" 2>/dev/null | grep -qF "LABEL=\"\$IDENTITY_DEVICE_LABEL\""; then
        IDENTITY_DEVICE="\$cand"
        log_info "identity device resolved via blkid scan"
        return 0
      fi
    done
  fi

  log_info "identity device not found"
  return 1
}

cdrom_backing_device() {
  # Print the block device that backs /cdrom according to the mount table.
  # Never assume a fixed device name; resolve it at runtime instead.
  dev=""
  if [ ! -r "\$PROC_MOUNTS" ]; then
    log_info "mount table unavailable for /cdrom resolution: \$PROC_MOUNTS"
    return 1
  fi
  # Third variable swallows the remaining mount options (POSIX read appends
  # leftover fields to the last variable).
  while read -r m_src m_mnt _; do
    if [ "\$m_mnt" = "/cdrom" ]; then
      case "\$m_src" in
        # Match absolute and sandbox-relative block device paths alike; the
        # equality check below remains the actual safety decision.
        */dev/*) dev="\$m_src"; break ;;
      esac
    fi
  done <"\$PROC_MOUNTS"
  [ -n "\$dev" ] || return 1
  printf '%s\\n' "\$dev"
  return 0
}

identity_is_install_medium() {
  cdrom_dev="\$(cdrom_backing_device)" || return 1
  id_real="\$(readlink -f "\$IDENTITY_DEVICE" 2>/dev/null || printf '%s' "\$IDENTITY_DEVICE")"
  cd_real="\$(readlink -f "\$cdrom_dev" 2>/dev/null || printf '%s' "\$cdrom_dev")"
  [ -n "\$id_real" ] && [ "\$id_real" = "\$cd_real" ]
}

# Mount the identity device read-only. In the early d-i initramfs context the
# vfat/fat kernel module is often not loaded yet, so an auto-detect mount can
# fail even though the device is present. Fall back to an explicit -t vfat
# attempt and try to load the module before giving up. Only tools shipped in
# the installer initramfs are used (mount, lsmod, modprobe, grep).
mount_identity_device() {
  err=""

  # Hard safety boundary: never touch the medium that debian-installer itself
  # is running from. If the labeled identity device resolves to the same block
  # device as /cdrom, refuse to mount and fall back to the next source.
  if identity_is_install_medium; then
    cdrom_dev="\$(cdrom_backing_device)"
    log_info "refusing to mount identity device: \$IDENTITY_DEVICE resolves to installation medium backing \$cdrom_dev"
    return 1
  fi

  if err="\$(mount -o ro "\$IDENTITY_DEVICE" /media/omnixys-identity 2>&1)"; then
    return 0
  fi
  log_info "identity device mount (auto) failed: \$err"

  if err="\$(mount -t vfat -o ro "\$IDENTITY_DEVICE" /media/omnixys-identity 2>&1)"; then
    log_info "identity device mounted via -t vfat"
    return 0
  fi
  log_info "identity device mount (-t vfat) failed: \$err"

  if command -v lsmod >/dev/null 2>&1 && lsmod 2>/dev/null | grep -qE '^(vfat|fat) '; then
    log_info "vfat/fat kernel module already loaded"
  elif command -v modprobe >/dev/null 2>&1; then
    if modprobe vfat 2>>/var/log/installer/omnixys-early.log; then
      log_info "vfat kernel module loaded via modprobe"
    else
      log_info "modprobe vfat failed"
    fi
  fi

  if err="\$(mount -t vfat -o ro "\$IDENTITY_DEVICE" /media/omnixys-identity 2>&1)"; then
    log_info "identity device mounted via -t vfat after module load"
    return 0
  fi
  log_info "identity device mount (-t vfat) failed after module load: \$err"

  return 1
}

run_identity_confirm_dialog() {
  [ "\$IDENTITY_CONFIRM" = "true" ] || return 0

  shell_quote_value() {
    printf '%s' "\$1" | sed "s/'/'\\\\\\\\''/g"
  }

  save_identity_values() {
    {
      printf "OMNIXYS_HOSTNAME='%s'\\n" "\$(shell_quote_value "\$OMNIXYS_HOSTNAME")"
      printf "OMNIXYS_DOMAIN='%s'\\n" "\$(shell_quote_value "\$OMNIXYS_DOMAIN")"
      printf "OMNIXYS_FULLNAME='%s'\\n" "\$(shell_quote_value "\$OMNIXYS_FULLNAME")"
      printf "OMNIXYS_USERNAME='%s'\\n" "\$(shell_quote_value "\$OMNIXYS_USERNAME")"
      printf "OMNIXYS_SSH_PUBLIC_KEY='%s'\\n" "\$(shell_quote_value "\${OMNIXYS_SSH_PUBLIC_KEY:-}")"
      printf "OMNIXYS_PASSWORD_HASH='%s'\\n" "\$(shell_quote_value "\${OMNIXYS_PASSWORD_HASH:-}")"
      printf "OMNIXYS_NETWORK_INTERFACE='%s'\\n" "\$(shell_quote_value "\$OMNIXYS_NETWORK_INTERFACE")"
      printf "OMNIXYS_STATIC_IP='%s'\\n" "\$(shell_quote_value "\$OMNIXYS_STATIC_IP")"
      printf "OMNIXYS_STATIC_ROUTERS='%s'\\n" "\$(shell_quote_value "\$OMNIXYS_STATIC_ROUTERS")"
      printf "OMNIXYS_STATIC_DNS='%s'\\n" "\$(shell_quote_value "\$OMNIXYS_STATIC_DNS")"
    } >/var/lib/omnixys/identity.env
    chmod 0600 /var/lib/omnixys/identity.env
  }

  request_identity_edit() {
    if [ ! -r "\$IDENTITY_CONSOLE_INPUT" ] || [ ! -w "\$IDENTITY_CONSOLE" ]; then
      log_info "installer console unavailable; identity values automatically confirmed"
      return 1
    fi

    network_summary="DHCP"
    if [ -n "\${OMNIXYS_NETWORK_INTERFACE:-}" ]; then
      network_summary="\$OMNIXYS_NETWORK_INTERFACE \$OMNIXYS_STATIC_IP; Router \$OMNIXYS_STATIC_ROUTERS; DNS \$OMNIXYS_STATIC_DNS"
    fi
    password_summary="nicht gesetzt"
    [ -z "\${OMNIXYS_PASSWORD_HASH:-}" ] || password_summary="gesetzt"

    if ! printf '\\nOmnixys identity configuration\\nHostname: %s\\nDomain: %s\\nName: %s\\nBenutzer: %s\\nPasswort: %s\\nNetzwerk: %s\\n\\nE + Enter innerhalb von %s Sekunden: Werte bearbeiten.\\nOhne Eingabe werden die Werte automatisch uebernommen.\\n' \
      "\${OMNIXYS_HOSTNAME:-}" "\${OMNIXYS_DOMAIN:-}" "\${OMNIXYS_FULLNAME:-}" "\${OMNIXYS_USERNAME:-}" \
      "\$password_summary" "\$network_summary" "\$IDENTITY_CONFIRM_TIMEOUT" >"\$IDENTITY_CONSOLE"; then
      log_info "installer console write failed; identity values automatically confirmed"
      return 1
    fi

    reply=""
    reply_file="/var/lib/omnixys/.identity-reply.\$\$"
    rm -f "\$reply_file"
    (
      if IFS= read -r console_reply <"\$IDENTITY_CONSOLE_INPUT"; then
        umask 077
        printf '%s\n' "\$console_reply" >"\$reply_file"
      fi
    ) &
    reader_pid=\$!
    elapsed=0
    while kill -0 "\$reader_pid" 2>/dev/null && [ "\$elapsed" -lt "\$IDENTITY_CONFIRM_TIMEOUT" ]; do
      sleep 1
      elapsed=\$((elapsed + 1))
    done

    if kill -0 "\$reader_pid" 2>/dev/null; then
      kill "\$reader_pid" 2>/dev/null || true
      wait "\$reader_pid" 2>/dev/null || true
    else
      wait "\$reader_pid" 2>/dev/null || true
    fi

    if [ -r "\$reply_file" ] && IFS= read -r reply <"\$reply_file"; then
      rm -f "\$reply_file"
      case "\$reply" in
        e|E|edit|EDIT|bearbeiten|BEARBEITEN)
          log_info "identity edit requested from installer console"
          return 0
          ;;
        *)
          log_info "identity values confirmed from installer console"
          return 1
          ;;
      esac
    fi
    rm -f "\$reply_file"

    log_info "identity values automatically confirmed after 5 seconds without input"
    return 1
  }

  if ! request_identity_edit; then
    save_identity_values
    log_info "identity confirmation: values saved without editing"
    return 0
  fi

  if [ ! -r /usr/share/debconf/confmodule ]; then
    log_info "debconf confmodule unavailable; cannot display required identity dialog"
    return 1
  fi
  if [ ! -r /cdrom/omnixys-identity.templates ]; then
    log_info "identity debconf templates unavailable; cannot display required identity dialog"
    return 1
  fi

  # Use the active Debian Installer frontend inherited from preseed_command.
  # shellcheck disable=SC1091
  . /usr/share/debconf/confmodule
  db_x_loadtemplatefile /cdrom/omnixys-identity.templates omnixys || return 1
  db_settitle omnixys/identity-title || true
  log_info "identity edit dialog starting (native debconf frontend)"

  ask_identity_value() {
    question="\$1"
    current="\$2"
    db_set "\$question" "\$current" || return 1
    db_fset "\$question" seen false || true
    db_input critical "\$question" || true
    db_go || return 1
    db_get "\$question" || return 1
    ANSWER="\$RET"
  }

  ask_identity_value omnixys/hostname "\${OMNIXYS_HOSTNAME:-}" || return 1
  OMNIXYS_HOSTNAME="\$ANSWER"
  ask_identity_value omnixys/domain "\${OMNIXYS_DOMAIN:-}" || return 1
  OMNIXYS_DOMAIN="\$ANSWER"
  ask_identity_value omnixys/fullname "\${OMNIXYS_FULLNAME:-}" || return 1
  OMNIXYS_FULLNAME="\$ANSWER"
  ask_identity_value omnixys/username "\${OMNIXYS_USERNAME:-}" || return 1
  OMNIXYS_USERNAME="\$ANSWER"

  ask_identity_value omnixys/ssh-public-key "\${OMNIXYS_SSH_PUBLIC_KEY:-}" || return 1
  OMNIXYS_SSH_PUBLIC_KEY="\$ANSWER"

  pw_set="nicht gesetzt"
  if [ -n "\${OMNIXYS_PASSWORD_HASH:-}" ]; then
    pw_set="gesetzt"
  fi
  db_subst omnixys/password-status STATUS "\$pw_set" || true
  db_fset omnixys/password-status seen false || true
  db_input critical omnixys/password-status || true
  db_go || return 1

  ask_identity_value omnixys/network-interface "\${OMNIXYS_NETWORK_INTERFACE:-}" || return 1
  OMNIXYS_NETWORK_INTERFACE="\$ANSWER"
  ask_identity_value omnixys/static-ip "\${OMNIXYS_STATIC_IP:-}" || return 1
  OMNIXYS_STATIC_IP="\$ANSWER"
  ask_identity_value omnixys/static-routers "\${OMNIXYS_STATIC_ROUTERS:-}" || return 1
  OMNIXYS_STATIC_ROUTERS="\$ANSWER"
  ask_identity_value omnixys/static-dns "\${OMNIXYS_STATIC_DNS:-}" || return 1
  OMNIXYS_STATIC_DNS="\$ANSWER"

  save_identity_values
  log_info "identity edit dialog: values saved"
}

run_identity_step() {
  apply_identity_debconf() {
    log_hostname="\${1:-false}"
    if [ -n "\${OMNIXYS_HOSTNAME:-}" ]; then
      if debconf-set netcfg/get_hostname "\$OMNIXYS_HOSTNAME"; then
        if [ "\$log_hostname" = "true" ]; then
          log_info "hostname configuration applied"
        fi
      fi
    fi
    if [ -n "\${OMNIXYS_DOMAIN:-}" ]; then
      debconf-set netcfg/get_domain "\$OMNIXYS_DOMAIN" || true
    fi
    if [ -n "\${OMNIXYS_FULLNAME:-}" ]; then
      debconf-set passwd/user-fullname "\$OMNIXYS_FULLNAME" || true
    fi
    if [ -n "\${OMNIXYS_USERNAME:-}" ]; then
      debconf-set passwd/username "\$OMNIXYS_USERNAME" || true
    fi
    if [ -n "\${OMNIXYS_PASSWORD_HASH:-}" ]; then
      debconf-set passwd/user-password-crypted "\$OMNIXYS_PASSWORD_HASH" || true
    fi
  }

  mkdir -p /var/lib/omnixys /media/omnixys-identity
  if [ "\$IDENTITY_SOURCE" != "usb-env" ]; then
    log_info "identity source selected: none; using build-time defaults"
    if ! run_step "identity confirmation dialog" run_identity_confirm_dialog; then
      abort_install "identity confirmation failed (source=none)"
    fi
    if [ "\$IDENTITY_CONFIRM" = "true" ]; then
      apply_identity_debconf false
    fi
    return 0
  fi

  log_info "identity source selected: usb-env"
  IDENTITY_FILE=""
  IDENTITY_MOUNTED="false"
  IDENTITY_LOADED="false"
  IDENTITY_DETECTED="false"
  mkdir -p /var/lib/omnixys /media/omnixys-identity

  IDENTITY_DEVICE=""
  if run_step "identity device detection (label=\$IDENTITY_DEVICE_LABEL)" detect_identity_device; then
    IDENTITY_DETECTED="true"
  fi
  if [ "\$IDENTITY_DETECTED" = "true" ]; then
    if run_step "identity device mount (\$IDENTITY_DEVICE)" mount_identity_device; then
      IDENTITY_MOUNTED="true"
      log_info "identity device mount succeeded: \$IDENTITY_DEVICE"
      if [ -r "/media/omnixys-identity\$IDENTITY_FILE_PATH" ]; then
        IDENTITY_FILE="/media/omnixys-identity\$IDENTITY_FILE_PATH"
        log_info "identity.env found on mounted device"
        log_info "USB identity selected"
      else
        log_info "USB identity.env not found on mounted device (looked for: /media/omnixys-identity\$IDENTITY_FILE_PATH)"
      fi
    else
      log_info "identity device mount failed: \$IDENTITY_DEVICE (see mount attempts above)"
    fi
  fi

  if [ -z "\$IDENTITY_FILE" ] && [ -r "/cdrom\$IDENTITY_FILE_PATH" ]; then
    IDENTITY_FILE="/cdrom\$IDENTITY_FILE_PATH"
    log_info "embedded identity selected"
  fi

  if [ -z "\$IDENTITY_FILE" ]; then
    if [ "\$IDENTITY_REQUIRED" = "true" ]; then
      log_info "required identity file not found (search summary: label=\$IDENTITY_DEVICE_LABEL detected=\$IDENTITY_DETECTED mounted=\$IDENTITY_MOUNTED usb-file=/media/omnixys-identity\$IDENTITY_FILE_PATH embedded=/cdrom\$IDENTITY_FILE_PATH)"
      abort_install "required identity file \$IDENTITY_FILE_PATH not found (IDENTITY_SOURCE=usb-env, IDENTITY_DEVICE_LABEL=\$IDENTITY_DEVICE_LABEL, USB device detected=\$IDENTITY_DETECTED, embedded copy on /cdrom absent)"
    fi
    log_info "identity file not found; prompting for interactive input"

    if ! run_step "identity confirmation dialog (no identity file)" run_identity_confirm_dialog; then
      abort_install "identity confirmation failed (no identity file present)"
    fi

    if [ "\$IDENTITY_CONFIRM" = "true" ]; then
      apply_identity_debconf true
    fi
  else
    if ! run_step "copy identity file from \$IDENTITY_FILE" cp "\$IDENTITY_FILE" /var/lib/omnixys/identity.env 2>>/var/log/installer/omnixys-early.log; then
      log_info "FAILED to copy identity file from \$IDENTITY_FILE"
      IDENTITY_FILE=""
      if [ "\$IDENTITY_REQUIRED" = "true" ]; then
        abort_install "required identity file could not be copied from \$IDENTITY_FILE to /var/lib/omnixys/identity.env"
      fi
      if ! run_step "identity confirmation dialog (copy fallback)" run_identity_confirm_dialog; then
        abort_install "identity confirmation failed (identity file copy failed)"
      fi
      if [ "\$IDENTITY_CONFIRM" = "true" ]; then
        apply_identity_debconf false
      fi
    else
      log_info "identity sourcing start"
      if ! sh -n /var/lib/omnixys/identity.env 2>>/var/log/installer/omnixys-early.log; then
        log_info "identity sourcing failed"
        if [ "\$IDENTITY_REQUIRED" = "true" ]; then
          abort_install "required identity file has invalid shell syntax: /var/lib/omnixys/identity.env"
        fi
      else
        # shellcheck disable=SC1091
        if ! . /var/lib/omnixys/identity.env 2>>/var/log/installer/omnixys-early.log; then
          log_info "identity sourcing failed"
          if [ "\$IDENTITY_REQUIRED" = "true" ]; then
            abort_install "required identity file could not be sourced: /var/lib/omnixys/identity.env"
          fi
        else
          IDENTITY_LOADED="true"
          log_info "identity sourcing completed"
        fi
      fi

      if ! run_step "identity confirmation dialog (identity loaded)" run_identity_confirm_dialog; then
        abort_install "identity confirmation failed (identity file was loaded successfully)"
      fi

      if [ "\$IDENTITY_LOADED" = "true" ] || [ "\$IDENTITY_CONFIRM" = "true" ]; then
        apply_identity_debconf true
      fi
    fi
  fi

  if [ "\$IDENTITY_MOUNTED" = "true" ]; then
    umount /media/omnixys-identity >/dev/null 2>&1 || true
  fi
}

run_identity_step
exit 0
EOF
  chmod +x "$out"
}

debian_compose_preseed_early_command() {
  PRESEED_EARLY_COMMAND="sh /cdrom/omnixys-early.sh"
}

debian_compose_partman_early_command() {
  PARTMAN_EARLY_COMMAND="sh /cdrom/omnixys-partman.sh"
}

debian_resolve_target_disk() {
  TARGET_DISK_MODE="${TARGET_DISK_MODE:-manual}"
  case "$TARGET_DISK_MODE" in
    manual)
      RESOLVED_TARGET_DISK="$TARGET_DISK"
      ;;
    by-id)
      RESOLVED_TARGET_DISK=""
      ;;
    auto)
      RESOLVED_TARGET_DISK=""
      ;;
    *)
      die "Unsupported TARGET_DISK_MODE in renderer: $TARGET_DISK_MODE"
      ;;
  esac

  info "Disk mode: $TARGET_DISK_MODE"
  info "Preseed partman-auto/disk value: $RESOLVED_TARGET_DISK"
}

debian_render_metadata() {
  local out="$1"
  local commit="unknown"
  local build_date
  local builder="${USER:-unknown}"

  build_date="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if command -v git >/dev/null 2>&1; then
    commit="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  fi

  cat >"$out" <<EOF
Installer: Omnixys Installer Framework ${INSTALLER_VERSION}
Backend: debian-preseed
Base ISO: Debian ${DEBIAN_MAJOR}.x (${ARCH})
Build Date: ${build_date}
Git Commit: ${commit}
Builder: ${builder}
EOF
}

debian_render() {
  BACKEND_WORK_DIR="$ROOT_DIR/work/debian-preseed"
  GENERATED_DIR="$BACKEND_WORK_DIR/generated"
  ensure_dir "$GENERATED_DIR"

  step "debian-preseed render: resolving password hash"
  debian_resolve_password_hash

  debian_partition_mode_values
  debian_resolve_target_disk
  debian_render_early_script
  debian_render_partman_script
  debian_render_network_late_script
  debian_compose_preseed_early_command
  debian_compose_partman_early_command
  TASKSEL_FIRST="$(debian_compose_tasksel)"
  PKGSEL_INCLUDE="$(debian_compose_pkgsel)"
  PKGSEL_UPGRADE="$(debian_compose_pkgsel_upgrade)"
  ANNA_MODULES="$(debian_compose_anna_modules)"
  FINISH_ACTION="$(debian_compose_finish_action)"
  LATE_COMMAND="$(debian_compose_late_command)"

  step "debian-preseed render: generating preseed.cfg"
  debian_render_template \
    "$ROOT_DIR/templates/debian-preseed.cfg.template" \
    "$GENERATED_DIR/preseed.cfg"

  step "debian-preseed render: generating metadata"
  debian_render_metadata "$GENERATED_DIR/installer-info.txt"
}
