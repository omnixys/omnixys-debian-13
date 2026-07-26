#!/usr/bin/env bash

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

debian_render_template() {
  local template="$1"
  local output="$2"

  local esc_fullname esc_ssh_key esc_late_command esc_tasksel esc_pkgsel esc_anna_modules esc_finish_action esc_disk_early_command
  esc_fullname="$(escape_sed_replacement "$FULLNAME")"
  esc_ssh_key="$(escape_sed_replacement "${SSH_PUBLIC_KEY:-}")"
  esc_late_command="$(escape_sed_replacement "$LATE_COMMAND")"
  esc_tasksel="$(escape_sed_replacement "$TASKSEL_FIRST")"
  esc_pkgsel="$(escape_sed_replacement "$PKGSEL_INCLUDE")"
  esc_anna_modules="$(escape_sed_replacement "$ANNA_MODULES")"
  esc_finish_action="$(escape_sed_replacement "$FINISH_ACTION")"
  esc_disk_early_command="$(escape_sed_replacement "$DISK_EARLY_COMMAND")"

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
    -e "s|__DISK_EARLY_COMMAND__|$esc_disk_early_command|g" \
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

  if [[ "$sudo_nopasswd" == "true" ]]; then
    cmd+="; in-target sh -c 'printf \"%s\\n\" \"${USERNAME} ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/90-${USERNAME}-nopasswd'"
    cmd+="; in-target chmod 440 /etc/sudoers.d/90-${USERNAME}-nopasswd"
    cmd+="; in-target visudo -cf /etc/sudoers.d/90-${USERNAME}-nopasswd"
  fi

  if [[ -n "${SSH_PUBLIC_KEY:-}" ]]; then
    cmd+="; in-target mkdir -p /home/${USERNAME}/.ssh"
    cmd+="; in-target sh -c 'printf %s \"${SSH_PUBLIC_KEY}\" > /home/${USERNAME}/.ssh/authorized_keys'"
    cmd+="; in-target chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.ssh"
    cmd+="; in-target chmod 700 /home/${USERNAME}/.ssh"
    cmd+="; in-target chmod 600 /home/${USERNAME}/.ssh/authorized_keys"
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
INSTALL_DEVICE="$(awk '$2 == "/cdrom" {print $1; exit}' /proc/mounts)"; INSTALL_PARENT="$INSTALL_DEVICE"; case "$INSTALL_PARENT" in /dev/nvme*n*p[0-9]*|/dev/mmcblk*p[0-9]*) INSTALL_PARENT="${INSTALL_PARENT%p[0-9]*}" ;; /dev/*[0-9]) INSTALL_PARENT="${INSTALL_PARENT%[0-9]*}" ;; esac; CANDIDATES=""; for DISK in $(list-devices disk); do BASE="${DISK#/dev/}"; [ "$DISK" = "$INSTALL_PARENT" ] && continue; [ -r "/sys/block/$BASE/removable" ] || continue; [ "$(cat "/sys/block/$BASE/removable" 2>/dev/null)" = "0" ] || continue; CANDIDATES="${CANDIDATES}${DISK}\n"; done; COUNT="$(printf "%b" "$CANDIDATES" | sed '/^$/d' | wc -l | tr -d ' ')"; if [ "$COUNT" -ne 1 ]; then echo "omnixys: auto disk detect failed (install media: ${INSTALL_PARENT:-unknown}, candidates: $(printf "%b" "$CANDIDATES" | tr '\n' ' '))" >/var/log/omnixys-disk-detect.log; exit 1; fi; TARGET="$(printf "%b" "$CANDIDATES" | sed '/^$/d' | head -n1)"; [ -n "$TARGET" ] || exit 1; debconf-set partman-auto/disk "$TARGET"
EOF
}

debian_compose_disk_early_command_by_id() {
  cat <<EOF
TARGET="\$(readlink -f "$TARGET_DISK_BY_ID" 2>/dev/null || true)"; [ -b "\$TARGET" ] || { echo "omnixys: by-id target not resolvable: $TARGET_DISK_BY_ID" >/var/log/omnixys-disk-detect.log; exit 1; }; debconf-set partman-auto/disk "\$TARGET"
EOF
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

  step "debian-preseed render: hashing password"
  PASSWORD_HASH="$(openssl passwd -6 "$PASSWORD")"

  debian_partition_mode_values
  debian_resolve_target_disk
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
