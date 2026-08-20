#!/usr/bin/env bash

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

debian_render_template() {
  local template="$1"
  local output="$2"

  local esc_fullname esc_ssh_key esc_late_command esc_tasksel esc_pkgsel esc_anna_modules esc_finish_action esc_preseed_early_command
  esc_fullname="$(escape_sed_replacement "$FULLNAME")"
  esc_ssh_key="$(escape_sed_replacement "${SSH_PUBLIC_KEY:-}")"
  esc_late_command="$(escape_sed_replacement "$LATE_COMMAND")"
  esc_tasksel="$(escape_sed_replacement "$TASKSEL_FIRST")"
  esc_pkgsel="$(escape_sed_replacement "$PKGSEL_INCLUDE")"
  esc_anna_modules="$(escape_sed_replacement "$ANNA_MODULES")"
  esc_finish_action="$(escape_sed_replacement "$FINISH_ACTION")"
  esc_preseed_early_command="$(escape_sed_replacement "$PRESEED_EARLY_COMMAND")"

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
    -e "s|__FILESYSTEM__|$FILESYSTEM|g" \
    -e "s|__PARTMAN_METHOD__|$PARTMAN_METHOD|g" \
    -e "s|__PARTMAN_RECIPE__|$PARTMAN_RECIPE|g" \
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
    "$template" >"$output"
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

  # Static IP configuration via dhcpcd – only when all four network variables are set.
  cmd+="; INSTALL_NETWORK_IF=\"${NETWORK_INTERFACE:-}\""
  cmd+="; INSTALL_STATIC_IP=\"${STATIC_IP:-}\""
  cmd+="; INSTALL_STATIC_ROUTERS=\"${STATIC_ROUTERS:-}\""
  cmd+="; INSTALL_STATIC_DNS=\"${STATIC_DNS:-}\""
  cmd+="; if [ -r /var/lib/omnixys/identity.env ]; then . /var/lib/omnixys/identity.env; [ -n \"\${OMNIXYS_NETWORK_INTERFACE:-}\" ] && INSTALL_NETWORK_IF=\"\$OMNIXYS_NETWORK_INTERFACE\"; [ -n \"\${OMNIXYS_STATIC_IP:-}\" ] && INSTALL_STATIC_IP=\"\$OMNIXYS_STATIC_IP\"; [ -n \"\${OMNIXYS_STATIC_ROUTERS:-}\" ] && INSTALL_STATIC_ROUTERS=\"\$OMNIXYS_STATIC_ROUTERS\"; [ -n \"\${OMNIXYS_STATIC_DNS:-}\" ] && INSTALL_STATIC_DNS=\"\$OMNIXYS_STATIC_DNS\"; fi"
  cmd+="; if [ -n \"\$INSTALL_NETWORK_IF\" ] && [ -n \"\$INSTALL_STATIC_IP\" ] && [ -n \"\$INSTALL_STATIC_ROUTERS\" ] && [ -n \"\$INSTALL_STATIC_DNS\" ]; then in-target sh -c \"printf '\\ninterface %s\\nstatic ip_address=%s\\nstatic routers=%s\\nstatic domain_name_servers=%s\\n' '\\\$INSTALL_NETWORK_IF' '\\\$INSTALL_STATIC_IP' '\\\$INSTALL_STATIC_ROUTERS' '\\\$INSTALL_STATIC_DNS' >> /etc/dhcpcd.conf\"; in-target dhcpcd -k \"\$INSTALL_NETWORK_IF\" || true; in-target dhcpcd \"\$INSTALL_NETWORK_IF\" || true; fi"

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
      PARTMAN_RECIPE="atomic"
      ;;
    lvm)
      PARTMAN_METHOD="lvm"
      PARTMAN_RECIPE="atomic"
      ;;
    *)
      die "Unsupported PARTITION_MODE in renderer: $PARTITION_MODE"
      ;;
  esac
}

debian_compose_disk_early_command_auto() {
  printf '%s' "sh /cdrom/omnixys-disk-detect.sh"
}

debian_render_disk_detect_script() {
  local out="$GENERATED_DIR/omnixys-disk-detect.sh"
  cat >"$out" <<'EOF'
#!/bin/sh
set -x
exec >/var/log/omnixys-disk-detect.log 2>&1

normalize_parent() {
  dev="$1"
  case "$dev" in
    /dev/nvme*n*p[0-9]*) printf '%s\n' "${dev%p[0-9]*}" ;;
    /dev/mmcblk*p[0-9]*) printf '%s\n' "${dev%p[0-9]*}" ;;
    /dev/*[0-9]) printf '%s\n' "${dev%[0-9]*}" ;;
    *) printf '%s\n' "$dev" ;;
  esac
}

is_ignored_base() {
  base="$1"
  case "$base" in
    loop*|ram*|fd*|sr*) return 0 ;;
    *) return 1 ;;
  esac
}

INSTALL_DEVICE="$(awk '$2 == "/cdrom" {print $1; exit}' /proc/mounts)"
if [ -z "$INSTALL_DEVICE" ]; then
  INSTALL_DEVICE="$(awk '$2 == "/hd-media" {print $1; exit}' /proc/mounts)"
fi
if [ -z "$INSTALL_DEVICE" ]; then
  INSTALL_DEVICE="$(awk '$3 ~ /iso9660/ {print $1; exit}' /proc/mounts)"
fi
INSTALL_PARENT="$(normalize_parent "$INSTALL_DEVICE")"

ALL_DISKS="$(list-devices disk 2>/dev/null || true)"
echo "INSTALL_DEVICE=$INSTALL_DEVICE"
echo "INSTALL_PARENT=$INSTALL_PARENT"
echo "list-devices disk:"
printf '%s\n' "$ALL_DISKS"

if command -v lsblk >/dev/null 2>&1; then
  echo "lsblk:"
  lsblk
fi

echo "proc_partitions:"
cat /proc/partitions || true

NON_REMOVABLE_POOL=""
FALLBACK_POOL=""

for DISK in $ALL_DISKS; do
  BASE="${DISK#/dev/}"

  if is_ignored_base "$BASE"; then
    echo "reject $DISK reason=ignored-base"
    continue
  fi

  if [ "$DISK" = "$INSTALL_PARENT" ]; then
    echo "reject $DISK reason=install-media"
    continue
  fi

  if [ ! -b "$DISK" ]; then
    echo "reject $DISK reason=not-block"
    continue
  fi

  FALLBACK_POOL="${FALLBACK_POOL}${DISK}\n"

  REMOVABLE="0"
  if [ -r "/sys/block/$BASE/removable" ]; then
    REMOVABLE="$(cat "/sys/block/$BASE/removable" 2>/dev/null || echo 0)"
  fi

  if [ "$REMOVABLE" = "0" ]; then
    NON_REMOVABLE_POOL="${NON_REMOVABLE_POOL}${DISK}\n"
    echo "candidate $DISK removable=$REMOVABLE"
  else
    echo "reject $DISK reason=removable removable=$REMOVABLE"
  fi
done

SELECT_POOL="$NON_REMOVABLE_POOL"
POOL_KIND="non-removable"
if [ -z "$(printf '%b' "$SELECT_POOL" | sed '/^$/d')" ]; then
  SELECT_POOL="$FALLBACK_POOL"
  POOL_KIND="fallback-all"
fi

SORTED_POOL="$(printf '%b' "$SELECT_POOL" | sed '/^$/d' | sort -u)"
echo "POOL_KIND=$POOL_KIND"
echo "SORTED_POOL=$(printf '%s' "$SORTED_POOL" | tr '\n' ' ')"

pick_first_match() {
  prefix="$1"
  printf '%s\n' "$SORTED_POOL" | sed '/^$/d' | while IFS= read -r d; do
    case "$d" in
      "$prefix"*)
        printf '%s\n' "$d"
        break
        ;;
    esac
  done
}

TARGET=""
if [ -z "$TARGET" ]; then TARGET="$(pick_first_match /dev/nvme)"; fi
if [ -z "$TARGET" ]; then TARGET="$(pick_first_match /dev/vd)"; fi
if [ -z "$TARGET" ]; then TARGET="$(pick_first_match /dev/sd)"; fi
if [ -z "$TARGET" ]; then TARGET="$(pick_first_match /dev/xvd)"; fi
if [ -z "$TARGET" ]; then TARGET="$(pick_first_match /dev/mmcblk)"; fi
if [ -z "$TARGET" ]; then TARGET="$(printf '%s\n' "$SORTED_POOL" | sed '/^$/d' | head -n1)"; fi

echo "TARGET=$TARGET"

if [ -z "$TARGET" ] || [ ! -b "$TARGET" ]; then
  for fallback in /dev/nvme0n1 /dev/vda /dev/sda; do
    if [ -b "$fallback" ]; then
      TARGET="$fallback"
      echo "fallback target=$TARGET"
      break
    fi
  done
fi

if [ -n "$TARGET" ] && [ -b "$TARGET" ]; then
  if debconf-set partman-auto/disk "$TARGET"; then
    echo "debconf-set partman-auto/disk -> $TARGET"
  else
    echo "debconf-set failed for TARGET=$TARGET"
  fi
  if debconf-set grub-installer/bootdev "$TARGET"; then
    echo "debconf-set grub-installer/bootdev -> $TARGET"
  else
    echo "debconf-set grub-installer/bootdev failed for TARGET=$TARGET"
  fi
else
  echo "no valid target selected; partman-auto/disk not modified"
fi

exit 0
EOF
  chmod +x "$out"
}

debian_compose_disk_early_command_by_id() {
  cat <<EOF
TARGET="\$(readlink -f "$TARGET_DISK_BY_ID" 2>/dev/null || true)"; [ -b "\$TARGET" ] || { echo "omnixys: by-id target not resolvable: $TARGET_DISK_BY_ID" >/var/log/omnixys-disk-detect.log; exit 1; }; debconf-set partman-auto/disk "\$TARGET"
EOF
}

debian_render_early_script() {
  local out="$GENERATED_DIR/omnixys-early.sh"
  cat >"$out" <<EOF
#!/bin/sh
set -x
exec >/var/log/omnixys-early.log 2>&1

TARGET_DISK_MODE="$TARGET_DISK_MODE"
TARGET_DISK_BY_ID="${TARGET_DISK_BY_ID:-}"
IDENTITY_SOURCE="${IDENTITY_SOURCE:-none}"
IDENTITY_REQUIRED="${IDENTITY_REQUIRED:-false}"
IDENTITY_FILE_PATH="${IDENTITY_FILE_PATH:-/identity.env}"
IDENTITY_DEVICE_LABEL="${IDENTITY_DEVICE_LABEL:-OMNIXYS-ID}"
IDENTITY_CONFIRM="${IDENTITY_CONFIRM:-true}"
IDENTITY_DEVICE_RETRIES=5
IDENTITY_DEVICE_RETRY_DELAY=1

mkdir -p /var/log/installer

log_info() {
  echo "omnixys: \$*"
  echo "omnixys: \$*" >>/var/log/installer/omnixys-early.log 2>/dev/null || true
}

run_disk_step() {
  case "\$TARGET_DISK_MODE" in
    auto)
      if [ -x /cdrom/omnixys-disk-detect.sh ]; then
        sh /cdrom/omnixys-disk-detect.sh || echo "disk helper failed"
      else
        echo "disk helper missing: /cdrom/omnixys-disk-detect.sh"
      fi
      ;;
    by-id)
      TARGET="\$(readlink -f "\$TARGET_DISK_BY_ID" 2>/dev/null || true)"
      if [ -n "\$TARGET" ] && [ -b "\$TARGET" ]; then
        debconf-set partman-auto/disk "\$TARGET" || echo "debconf-set failed for by-id target"
        debconf-set grub-installer/bootdev "\$TARGET" || echo "debconf-set grub bootdev failed for by-id target"
      else
        echo "by-id target not resolvable: \$TARGET_DISK_BY_ID"
      fi
      ;;
    manual)
      echo "manual disk mode: no early disk override"
      ;;
    *)
      echo "unknown TARGET_DISK_MODE=\$TARGET_DISK_MODE"
      ;;
  esac
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
    [ "\$n" -lt "\$IDENTITY_DEVICE_RETRIES" ] && sleep "\$IDENTITY_DEVICE_RETRY_DELAY"
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
    for cand in /dev/sd[a-z][0-9]* /dev/vd[a-z][0-9]* /dev/xvd[a-z][0-9]* /dev/nvme[0-9]*n[0-9]*p[0-9]* /dev/mmcblk[0-9]*p[0-9]*; do
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

# Mount the identity device read-only. In the early d-i initramfs context the
# vfat/fat kernel module is often not loaded yet, so an auto-detect mount can
# fail even though the device is present. Fall back to an explicit -t vfat
# attempt and try to load the module before giving up. Only tools shipped in
# the installer initramfs are used (mount, lsmod, modprobe, grep).
mount_identity_device() {
  local err

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

  # Skip in non-interactive environments (CI, test sandbox, no TTY).
  if [ ! -t 0 ] && [ ! -t 1 ]; then
    log_info "non-interactive environment detected; skipping identity confirm dialog"
    return 0
  fi

  local UI_CMD=""
  if command -v whiptail >/dev/null 2>&1; then
    UI_CMD="whiptail"
  elif command -v dialog >/dev/null 2>&1; then
    UI_CMD="dialog"
  else
    log_info "neither whiptail nor dialog available; skipping identity confirm dialog"
    return 0
  fi

  log_info "identity confirm dialog starting (UI: \$UI_CMD)"

  local TITLE="Omnixys – Identity Configuration"
  local W=60
  local H=20

  prompt_value() {
    local label="\$1"
    local var_name="\$2"
    local current="\${!var_name:-}"
    local result

    result="\$(
      \$UI_CMD --inputbox \"\$label\" \$H \$W \"\$current\" 2>&1
    )"
    if [ \$? -eq 0 ]; then
      printf '%s' \"\$result\"
    else
      printf '%s' \"\$current\"
    fi
  }

  show_password_status() {
    local label="\$1"
    local is_set="\$2"
    local status="[nicht gesetzt]"
    if [ \"\$is_set\" = \"true\" ]; then
      status=\"[gesetzt]\"
    fi
    \$UI_CMD --msgbox \"\$label\\n\\nStatus: \$status\" \$H \$W 2>&1
  }

  OMNIXYS_HOSTNAME="\$(prompt_value 'Hostname:' 'OMNIXYS_HOSTNAME')"
  OMNIXYS_DOMAIN="\$(prompt_value 'Domain:' 'OMNIXYS_DOMAIN')"
  OMNIXYS_FULLNAME="\$(prompt_value 'Vollständiger Name:' 'OMNIXYS_FULLNAME')"
  OMNIXYS_USERNAME="\$(prompt_value 'Benutzername:' 'OMNIXYS_USERNAME')"

  if [ -n \"\${OMNIXYS_SSH_PUBLIC_KEY:-}\" ]; then
    OMNIXYS_SSH_PUBLIC_KEY="\$(prompt_value 'SSH Public Key:' 'OMNIXYS_SSH_PUBLIC_KEY')"
  fi

  local pw_set=\"false\"
  if [ -n \"\${OMNIXYS_PASSWORD_HASH:-}\" ]; then
    pw_set=\"true\"
  fi
  show_password_status 'Passwort-Hash:' \"\$pw_set\"

  OMNIXYS_NETWORK_INTERFACE="\$(prompt_value 'Netzwerk-Interface (z.B. eno1):' 'OMNIXYS_NETWORK_INTERFACE')"
  OMNIXYS_STATIC_IP="\$(prompt_value 'Statische IP (z.B. 192.168.2.101/24):' 'OMNIXYS_STATIC_IP')"
  OMNIXYS_STATIC_ROUTERS="\$(prompt_value 'Gateway/Router (z.B. 192.168.2.1):' 'OMNIXYS_STATIC_ROUTERS')"
  OMNIXYS_STATIC_DNS="\$(prompt_value 'DNS Server (z.B. 192.168.2.1):' 'OMNIXYS_STATIC_DNS')"

  SUMMARY="Hostname: \$OMNIXYS_HOSTNAME\\n"
  SUMMARY+=\"Domain: \$OMNIXYS_DOMAIN\\n\"
  SUMMARY+=\"Name: \$OMNIXYS_FULLNAME\\n\"
  SUMMARY+=\"Benutzer: \$OMNIXYS_USERNAME\\n\"
  SUMMARY+=\"Passwort: \$status\\n\"
  if [ -n \"\$OMNIXYS_NETWORK_INTERFACE\" ]; then
    SUMMARY+=\"\\nNetzwerk:\\n\"
    SUMMARY+=\"  Interface: \$OMNIXYS_NETWORK_INTERFACE\\n\"
    SUMMARY+=\"  IP: \$OMNIXYS_STATIC_IP\\n\"
    SUMMARY+=\"  Router: \$OMNIXYS_STATIC_ROUTERS\\n\"
    SUMMARY+=\"  DNS: \$OMNIXYS_STATIC_DNS\\n\"
  fi

  if \$UI_CMD --yesno \"\$SUMMARY\\n\\nFortfahren?\" \$H \$W 2>&1; then
    log_info "identity confirm dialog: confirmed"
  else
    log_info "identity confirm dialog: cancelled by user"
    exit 1
  fi

  cat > /var/lib/omnixys/identity.env <<IDEOF
OMNIXYS_HOSTNAME=\$OMNIXYS_HOSTNAME
OMNIXYS_DOMAIN=\$OMNIXYS_DOMAIN
OMNIXYS_FULLNAME=\"\$OMNIXYS_FULLNAME\"
OMNIXYS_USERNAME=\$OMNIXYS_USERNAME
OMNIXYS_SSH_PUBLIC_KEY=\"\${OMNIXYS_SSH_PUBLIC_KEY:-}\"
OMNIXYS_PASSWORD_HASH='\${OMNIXYS_PASSWORD_HASH:-}'
OMNIXYS_NETWORK_INTERFACE=\$OMNIXYS_NETWORK_INTERFACE
OMNIXYS_STATIC_IP=\$OMNIXYS_STATIC_IP
OMNIXYS_STATIC_ROUTERS=\$OMNIXYS_STATIC_ROUTERS
OMNIXYS_STATIC_DNS=\$OMNIXYS_STATIC_DNS
IDEOF

  . /var/lib/omnixys/identity.env
  log_info "identity confirm dialog: values saved"
}

run_identity_step() {
  [ "\$IDENTITY_SOURCE" = "usb-env" ] || return 0

  log_info "identity source selected: usb-env"
  IDENTITY_FILE=""
  IDENTITY_MOUNTED="false"
  mkdir -p /var/lib/omnixys /media/omnixys-identity

  IDENTITY_DEVICE=""
  detect_identity_device || true
  if [ -n "\$IDENTITY_DEVICE" ]; then
    if mount_identity_device; then
      IDENTITY_MOUNTED="true"
      log_info "identity device mount succeeded: \$IDENTITY_DEVICE"
      if [ -r "/media/omnixys-identity\$IDENTITY_FILE_PATH" ]; then
        IDENTITY_FILE="/media/omnixys-identity\$IDENTITY_FILE_PATH"
        log_info "identity.env found on mounted device"
        log_info "USB identity selected"
      else
        log_info "USB identity.env not found on mounted device"
      fi
    else
      log_info "identity device mount failed: \$IDENTITY_DEVICE"
    fi
  fi

  if [ -z "\$IDENTITY_FILE" ] && [ -r "/cdrom\$IDENTITY_FILE_PATH" ]; then
    IDENTITY_FILE="/cdrom\$IDENTITY_FILE_PATH"
    log_info "embedded identity selected"
  fi

  if [ -z "\$IDENTITY_FILE" ]; then
    if [ "\$IDENTITY_REQUIRED" = "true" ]; then
      log_info "required identity file not found (IDENTITY_SOURCE=usb-env); aborting installation"
      exit 1
    fi
    log_info "identity file not found; continuing with build-time defaults"
  else
    cp "\$IDENTITY_FILE" /var/lib/omnixys/identity.env
    set +x
    . /var/lib/omnixys/identity.env

    run_identity_confirm_dialog

    [ -n "\${OMNIXYS_HOSTNAME:-}" ] && { debconf-set netcfg/get_hostname "\$OMNIXYS_HOSTNAME" && log_info "hostname override applied: \$OMNIXYS_HOSTNAME"; } || true
    [ -n "\${OMNIXYS_DOMAIN:-}" ] && debconf-set netcfg/get_domain "\$OMNIXYS_DOMAIN" || true
    [ -n "\${OMNIXYS_FULLNAME:-}" ] && debconf-set passwd/user-fullname "\$OMNIXYS_FULLNAME" || true
    [ -n "\${OMNIXYS_USERNAME:-}" ] && debconf-set passwd/username "\$OMNIXYS_USERNAME" || true
    [ -n "\${OMNIXYS_PASSWORD_HASH:-}" ] && debconf-set passwd/user-password-crypted "\$OMNIXYS_PASSWORD_HASH" || true
    set -x
  fi

  if [ "\$IDENTITY_MOUNTED" = "true" ]; then
    umount /media/omnixys-identity >/dev/null 2>&1 || true
  fi
}

run_disk_step
run_identity_step
exit 0
EOF
  chmod +x "$out"
}

debian_compose_preseed_early_command() {
  PRESEED_EARLY_COMMAND="sh /cdrom/omnixys-early.sh"
}

debian_resolve_target_disk() {
  TARGET_DISK_MODE="${TARGET_DISK_MODE:-manual}"
  case "$TARGET_DISK_MODE" in
    manual)
      RESOLVED_TARGET_DISK="$TARGET_DISK"
      ;;
    by-id)
      RESOLVED_TARGET_DISK="$TARGET_DISK_BY_ID"
      ;;
    auto)
      # Use a real bootstrap value; early_command replaces it with detected target.
      RESOLVED_TARGET_DISK="/dev/sda"
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
  if [[ "$TARGET_DISK_MODE" == "auto" ]]; then
    debian_render_disk_detect_script
  fi
  debian_compose_preseed_early_command
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
