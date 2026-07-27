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

  # Determine the effective install user at runtime so identity overrides stay consistent.
  cmd+="; INSTALL_USER=\"\$(in-target awk -F: '\$3 == 1000 { print \$1; exit }' /etc/passwd 2>/dev/null || true)\""
  cmd+="; [ -n \"\$INSTALL_USER\" ] || INSTALL_USER=\"${USERNAME}\""
  cmd+="; INSTALL_SSH_KEY=\"${SSH_PUBLIC_KEY:-}\""
  cmd+="; INSTALL_HOSTNAME=\"\""
  cmd+="; if [ -r /var/lib/omnixys/identity.env ]; then . /var/lib/omnixys/identity.env; [ -n \"\${OMNIXYS_USERNAME:-}\" ] && INSTALL_USER=\"\$OMNIXYS_USERNAME\"; [ -n \"\${OMNIXYS_SSH_PUBLIC_KEY:-}\" ] && INSTALL_SSH_KEY=\"\$OMNIXYS_SSH_PUBLIC_KEY\"; [ -n \"\${OMNIXYS_HOSTNAME:-}\" ] && INSTALL_HOSTNAME=\"\$OMNIXYS_HOSTNAME\"; fi"

  if [[ "$sudo_nopasswd" == "true" ]]; then
    cmd+="; in-target env INSTALL_USER=\"\$INSTALL_USER\" sh -c 'printf \"%s\\n\" \"\$INSTALL_USER ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/90-omnixys-nopasswd'"
    cmd+="; in-target chmod 440 /etc/sudoers.d/90-omnixys-nopasswd"
    cmd+="; in-target visudo -cf /etc/sudoers.d/90-omnixys-nopasswd"
  fi

  cmd+="; if [ -n \"\$INSTALL_HOSTNAME\" ]; then in-target sh -c \"printf '%s\\n' \\\"\$INSTALL_HOSTNAME\\\" > /etc/hostname\"; in-target hostnamectl set-hostname \"\$INSTALL_HOSTNAME\" >/dev/null 2>&1 || true; fi"
  cmd+="; if [ -n \"\$INSTALL_SSH_KEY\" ]; then in-target env INSTALL_USER=\"\$INSTALL_USER\" INSTALL_SSH_KEY=\"\$INSTALL_SSH_KEY\" sh -c 'mkdir -p /home/\$INSTALL_USER/.ssh; printf %s \"\$INSTALL_SSH_KEY\" > /home/\$INSTALL_USER/.ssh/authorized_keys; chown -R \$INSTALL_USER:\$INSTALL_USER /home/\$INSTALL_USER/.ssh; chmod 700 /home/\$INSTALL_USER/.ssh; chmod 600 /home/\$INSTALL_USER/.ssh/authorized_keys'; fi"

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
  cat <<'EOF'
LOG_FILE="/var/log/omnixys-disk-detect.log"; INSTALL_DEVICE="$(awk '$2 == "/cdrom" {print $1; exit}' /proc/mounts)"; [ -n "$INSTALL_DEVICE" ] || INSTALL_DEVICE="$(awk '$2 == "/hd-media" {print $1; exit}' /proc/mounts)"; INSTALL_PARENT="$INSTALL_DEVICE"; case "$INSTALL_PARENT" in /dev/nvme*n*p[0-9]*|/dev/mmcblk*p[0-9]*) INSTALL_PARENT="${INSTALL_PARENT%p[0-9]*}" ;; /dev/*[0-9]) INSTALL_PARENT="${INSTALL_PARENT%[0-9]*}" ;; esac; ALL_DISKS="$(list-devices disk 2>/dev/null || true)"; CANDIDATES=""; FALLBACK_CANDIDATES=""; for DISK in $ALL_DISKS; do BASE="${DISK#/dev/}"; case "$BASE" in loop*|ram*|fd*|sr*) continue ;; esac; [ "$DISK" = "$INSTALL_PARENT" ] && continue; [ -b "$DISK" ] || continue; FALLBACK_CANDIDATES="${FALLBACK_CANDIDATES}${DISK}\n"; REMOVABLE="0"; [ -r "/sys/block/$BASE/removable" ] && REMOVABLE="$(cat "/sys/block/$BASE/removable" 2>/dev/null || echo 0)"; [ "$REMOVABLE" = "0" ] || continue; CANDIDATES="${CANDIDATES}${DISK}\n"; done; if [ -n "$CANDIDATES" ]; then SELECT_POOL="$CANDIDATES"; POOL_KIND="non-removable"; else SELECT_POOL="$FALLBACK_CANDIDATES"; POOL_KIND="fallback-all"; fi; SORTED_POOL="$(printf "%b" "$SELECT_POOL" | sed '/^$/d' | sort -u)"; COUNT="$(printf "%s\n" "$SORTED_POOL" | sed '/^$/d' | wc -l | tr -d ' ')"; TARGET=""; for PATTERN in '/dev/nvme*' '/dev/vd*' '/dev/xvd*' '/dev/sd*' '/dev/mmcblk*' '/dev/*'; do TARGET="$(printf "%s\n" "$SORTED_POOL" | sed '/^$/d' | grep -E "^${PATTERN}$" | head -n1 || true)"; [ -n "$TARGET" ] && break; done; { echo "omnixys: auto disk detect"; echo "install_device=${INSTALL_DEVICE:-unknown}"; echo "install_parent=${INSTALL_PARENT:-unknown}"; echo "pool_kind=$POOL_KIND"; echo "all_disks=$(printf '%s' "$ALL_DISKS" | tr '\n' ' ')"; echo "candidates=$(printf '%b' "$SORTED_POOL" | tr '\n' ' ')"; echo "candidate_count=$COUNT"; echo "selected=${TARGET:-none}"; if command -v lsblk >/dev/null 2>&1; then echo "lsblk:"; lsblk 2>&1; fi; echo "proc_partitions:"; cat /proc/partitions 2>&1; } >"$LOG_FILE"; [ -n "$TARGET" ] || { echo "omnixys: auto disk detect failed (no suitable target)" >>"$LOG_FILE"; exit 1; }; debconf-set partman-auto/disk "$TARGET"
EOF
}

debian_compose_disk_early_command_by_id() {
  cat <<EOF
TARGET="\$(readlink -f "$TARGET_DISK_BY_ID" 2>/dev/null || true)"; [ -b "\$TARGET" ] || { echo "omnixys: by-id target not resolvable: $TARGET_DISK_BY_ID" >/var/log/omnixys-disk-detect.log; exit 1; }; debconf-set partman-auto/disk "\$TARGET"
EOF
}

debian_compose_identity_early_command() {
  case "$IDENTITY_SOURCE" in
    none)
      echo "true"
      ;;
    usb-env)
      cat <<EOF
IDENTITY_FILE=""; IDENTITY_MOUNTED="false"; mkdir -p /var/lib/omnixys /media/omnixys-identity; if [ -r "/cdrom$IDENTITY_FILE_PATH" ]; then IDENTITY_FILE="/cdrom$IDENTITY_FILE_PATH"; elif [ -b "/dev/disk/by-label/$IDENTITY_DEVICE_LABEL" ]; then if mount -o ro "/dev/disk/by-label/$IDENTITY_DEVICE_LABEL" /media/omnixys-identity >/dev/null 2>&1; then IDENTITY_MOUNTED="true"; fi; if [ -r "/media/omnixys-identity$IDENTITY_FILE_PATH" ]; then IDENTITY_FILE="/media/omnixys-identity$IDENTITY_FILE_PATH"; fi; fi; if [ -z "\$IDENTITY_FILE" ]; then if [ "$IDENTITY_REQUIRED" = "true" ]; then echo "omnixys: required identity file not found" >/var/log/omnixys-identity.log; exit 1; fi; else cp "\$IDENTITY_FILE" /var/lib/omnixys/identity.env; . /var/lib/omnixys/identity.env; [ -n "\${OMNIXYS_HOSTNAME:-}" ] && debconf-set netcfg/get_hostname "\$OMNIXYS_HOSTNAME"; [ -n "\${OMNIXYS_DOMAIN:-}" ] && debconf-set netcfg/get_domain "\$OMNIXYS_DOMAIN"; [ -n "\${OMNIXYS_FULLNAME:-}" ] && debconf-set passwd/user-fullname "\$OMNIXYS_FULLNAME"; [ -n "\${OMNIXYS_USERNAME:-}" ] && debconf-set passwd/username "\$OMNIXYS_USERNAME"; [ -n "\${OMNIXYS_PASSWORD_HASH:-}" ] && debconf-set passwd/user-password-crypted "\$OMNIXYS_PASSWORD_HASH"; fi; if [ "\$IDENTITY_MOUNTED" = "true" ]; then umount /media/omnixys-identity >/dev/null 2>&1 || true; fi
EOF
      ;;
    *)
      die "Unsupported IDENTITY_SOURCE in renderer: $IDENTITY_SOURCE"
      ;;
  esac
}

debian_compose_preseed_early_command() {
  PRESEED_EARLY_COMMAND="$DISK_EARLY_COMMAND"

  if [[ "$IDENTITY_SOURCE" != "none" ]]; then
    PRESEED_EARLY_COMMAND+="; $(debian_compose_identity_early_command)"
  fi
}

debian_resolve_target_disk() {
  TARGET_DISK_MODE="${TARGET_DISK_MODE:-manual}"
  case "$TARGET_DISK_MODE" in
    manual)
      RESOLVED_TARGET_DISK="$TARGET_DISK"
      DISK_EARLY_COMMAND="true"
      ;;
    by-id)
      RESOLVED_TARGET_DISK="$TARGET_DISK_BY_ID"
      DISK_EARLY_COMMAND="$(debian_compose_disk_early_command_by_id)"
      ;;
    auto)
      RESOLVED_TARGET_DISK="/dev/omnixys-auto-detect"
      DISK_EARLY_COMMAND="$(debian_compose_disk_early_command_auto)"
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
