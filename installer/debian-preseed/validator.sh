#!/usr/bin/env bash

debian_check_tooling() {
  require_commands xorriso awk sed grep openssl
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    die "Either curl or wget is required"
  fi
}

debian_require_var() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "Missing required variable: $name"
}

debian_validate_hostname() {
  [[ "$HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || die "Invalid HOSTNAME: $HOSTNAME"
}

debian_validate_timezone() {
  if [[ -d /usr/share/zoneinfo ]] && [[ ! -e "/usr/share/zoneinfo/$TIMEZONE" ]]; then
    die "Invalid TIMEZONE (not found in /usr/share/zoneinfo): $TIMEZONE"
  fi
}

debian_validate_locale() {
  [[ "$LOCALE" =~ ^[a-z]{2}_[A-Z]{2}\.UTF-8$ ]] || die "Invalid LOCALE: $LOCALE"
  if command -v locale >/dev/null 2>&1; then
    if ! locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -q "^$(echo "$LOCALE" | tr '[:upper:]' '[:lower:]' | tr -d '-')$"; then
      warn "LOCALE not found in locale -a on this host: $LOCALE"
    fi
  fi
}

debian_validate_arch() {
  case "$ARCH" in
    amd64|arm64) ;;
    *) die "Unsupported ARCH: $ARCH (expected amd64|arm64)" ;;
  esac
}

debian_validate_filesystem() {
  case "$FILESYSTEM" in
    ext4|xfs|btrfs) ;;
    *) die "Unsupported FILESYSTEM: $FILESYSTEM (expected ext4|xfs|btrfs)" ;;
  esac
}

debian_validate_partition_mode() {
  case "$PARTITION_MODE" in
    erase|lvm|custom) ;;
    *) die "Unsupported PARTITION_MODE: $PARTITION_MODE (expected erase|lvm|custom)" ;;
  esac
}

debian_validate_password() {
  [[ ${#PASSWORD} -ge 12 ]] || die "PASSWORD must be at least 12 characters"
  [[ "$PASSWORD" =~ [A-Z] ]] || die "PASSWORD must include an uppercase letter"
  [[ "$PASSWORD" =~ [a-z] ]] || die "PASSWORD must include a lowercase letter"
  [[ "$PASSWORD" =~ [0-9] ]] || die "PASSWORD must include a number"
}

debian_validate_mirror() {
  [[ -n "$APT_MIRROR" ]] || die "APT_MIRROR is empty"
  if command -v curl >/dev/null 2>&1; then
    if ! curl -fsI --max-time 10 "https://$APT_MIRROR" >/dev/null 2>&1; then
      warn "APT_MIRROR not reachable over HTTPS probe: $APT_MIRROR"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -q --spider --timeout=10 "https://$APT_MIRROR"; then
      warn "APT_MIRROR not reachable over HTTPS probe: $APT_MIRROR"
    fi
  fi
}

debian_validate_ssh_policy() {
  case "$SSH_PERMIT_ROOT_LOGIN" in
    yes|no|prohibit-password|forced-commands-only) ;;
    *) die "Invalid SSH_PERMIT_ROOT_LOGIN: $SSH_PERMIT_ROOT_LOGIN" ;;
  esac
}

debian_validate_target_disk() {
  [[ "$TARGET_DISK" =~ ^/dev/ ]] || die "TARGET_DISK must start with /dev/: $TARGET_DISK"
  if [[ "$DRY_RUN" != "true" ]] && [[ -d /dev ]] && [[ ! -e "$TARGET_DISK" ]]; then
    warn "TARGET_DISK does not exist on this machine: $TARGET_DISK"
  fi
}

debian_validate_bool() {
  local var_name="$1"
  local normalized
  normalized="$(normalize_bool "${!var_name}")" || die "Invalid boolean for $var_name: ${!var_name}"
  printf -v "$var_name" '%s' "$normalized"
}

debian_validate() {
  step "debian-preseed validate: required variables"
  debian_require_var INSTALLER
  debian_require_var ARCH
  debian_require_var INSTALLER_VERSION
  debian_require_var DEBIAN_MAJOR
  debian_require_var DEBIAN_RELEASE
  debian_require_var HOSTNAME
  debian_require_var DOMAIN
  debian_require_var FULLNAME
  debian_require_var USERNAME
  debian_require_var PASSWORD
  debian_require_var LANGUAGE
  debian_require_var COUNTRY
  debian_require_var LOCALE
  debian_require_var KEYBOARD
  debian_require_var TIMEZONE
  debian_require_var TARGET_DISK
  debian_require_var PARTITION_MODE
  debian_require_var ERASE_DISK
  debian_require_var FILESYSTEM
  debian_require_var INSTALL_OPENSSH
  debian_require_var INSTALL_STANDARD_UTILITIES
  debian_require_var INSTALL_FIRMWARE
  debian_require_var INSTALL_UPDATES
  debian_require_var SSH_PASSWORD_AUTH
  debian_require_var SSH_PERMIT_ROOT_LOGIN
  debian_require_var REBOOT_AFTER_INSTALL

  debian_validate_hostname
  debian_check_tooling
  debian_validate_timezone
  debian_validate_locale
  debian_validate_arch
  debian_validate_filesystem
  debian_validate_partition_mode
  debian_validate_password
  debian_validate_target_disk
  debian_validate_mirror
  debian_validate_ssh_policy

  if [[ "$PARTITION_MODE" == "custom" ]]; then
    die "PARTITION_MODE=custom is reserved for post-v1.0 extension; use erase or lvm"
  fi

  debian_validate_bool ERASE_DISK
  debian_validate_bool INSTALL_OPENSSH
  debian_validate_bool INSTALL_STANDARD_UTILITIES
  debian_validate_bool INSTALL_FIRMWARE
  debian_validate_bool INSTALL_UPDATES
  debian_validate_bool SSH_PASSWORD_AUTH
  debian_validate_bool REBOOT_AFTER_INSTALL
  if [[ -n "${SUDO_NOPASSWD:-}" ]]; then
    debian_validate_bool SUDO_NOPASSWD
  fi

  [[ "$INSTALLER" == "debian-preseed" ]] || die "INSTALLER must be debian-preseed for this backend"
}
