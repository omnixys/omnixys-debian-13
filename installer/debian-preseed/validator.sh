#!/usr/bin/env bash

debian_check_tooling() {
  require_commands awk sed grep openssl

  if [[ "$DRY_RUN" != "true" ]]; then
    require_commands xorriso
  fi

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
  # Strength checks intentionally disabled to allow weak/lab passwords
  # such as "asd". PASSWORD is still required via debian_require_var.
  #[[ ${#PASSWORD} -ge 12 ]] || die "PASSWORD must be at least 12 characters"
  #[[ "$PASSWORD" =~ [A-Z] ]] || die "PASSWORD must include an uppercase letter"
  #[[ "$PASSWORD" =~ [a-z] ]] || die "PASSWORD must include a lowercase letter"
  #[[ "$PASSWORD" =~ [0-9] ]] || die "PASSWORD must include a number"
  :
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

debian_validate_ipv4() {
  local value="$1"
  local IFS=.
  local -a octets=()
  local octet
  read -r -a octets <<<"$value"
  [[ ${#octets[@]} -eq 4 ]] || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]+$ ]] || return 1
    ((10#$octet <= 255)) || return 1
  done
}

debian_validate_ipv4_list() {
  local value="$1"
  local address
  [[ -n "$value" ]] || return 1
  for address in $value; do
    debian_validate_ipv4 "$address" || return 1
  done
}

debian_validate_network_config() {
  NETWORK_INTERFACE="${NETWORK_INTERFACE:-}"
  STATIC_IP="${STATIC_IP:-}"
  STATIC_ROUTERS="${STATIC_ROUTERS:-}"
  STATIC_DNS="${STATIC_DNS:-}"

  local configured=0
  local value
  for value in "$NETWORK_INTERFACE" "$STATIC_IP" "$STATIC_ROUTERS" "$STATIC_DNS"; do
    [[ -z "$value" ]] || ((configured += 1))
  done

  [[ $configured -eq 0 ]] && return 0
  [[ $configured -eq 4 ]] || die "Static network configuration requires NETWORK_INTERFACE, STATIC_IP, STATIC_ROUTERS and STATIC_DNS"
  [[ "$NETWORK_INTERFACE" =~ ^[[:alnum:]_.:-]{1,15}$ ]] || die "Invalid NETWORK_INTERFACE: $NETWORK_INTERFACE"

  local address="${STATIC_IP%/*}"
  local prefix="${STATIC_IP#*/}"
  [[ "$address" != "$STATIC_IP" ]] || die "STATIC_IP must include an IPv4 CIDR prefix: $STATIC_IP"
  debian_validate_ipv4 "$address" || die "Invalid STATIC_IP address: $STATIC_IP"
  if [[ ! "$prefix" =~ ^[0-9]+$ ]] || ((10#$prefix > 32)); then
    die "Invalid STATIC_IP prefix: $STATIC_IP"
  fi
  debian_validate_ipv4_list "$STATIC_ROUTERS" || die "Invalid STATIC_ROUTERS: $STATIC_ROUTERS"
  debian_validate_ipv4_list "$STATIC_DNS" || die "Invalid STATIC_DNS: $STATIC_DNS"
}

debian_validate_target_disk() {
  [[ "$TARGET_DISK" =~ ^/dev/ ]] || die "TARGET_DISK must start with /dev/: $TARGET_DISK"
  if [[ "$DRY_RUN" != "true" ]] && [[ -d /dev ]] && [[ ! -e "$TARGET_DISK" ]]; then
    warn "TARGET_DISK does not exist on this machine: $TARGET_DISK"
  fi
}

debian_validate_target_disk_mode() {
  TARGET_DISK_MODE="${TARGET_DISK_MODE:-manual}"
  case "$TARGET_DISK_MODE" in
    auto|by-id|manual) ;;
    *) die "Unsupported TARGET_DISK_MODE: $TARGET_DISK_MODE (expected auto|by-id|manual)" ;;
  esac
}

debian_validate_target_disk_by_id() {
  [[ -n "${TARGET_DISK_BY_ID:-}" ]] || die "TARGET_DISK_BY_ID is required when TARGET_DISK_MODE=by-id"
  [[ "$TARGET_DISK_BY_ID" =~ ^/dev/disk/by-id/ ]] || die "TARGET_DISK_BY_ID must start with /dev/disk/by-id/: $TARGET_DISK_BY_ID"
}

debian_validate_target_disk_config() {
  debian_validate_target_disk_mode
  case "$TARGET_DISK_MODE" in
    auto)
      ;;
    by-id)
      debian_validate_target_disk_by_id
      ;;
    manual)
      debian_require_var TARGET_DISK
      debian_validate_target_disk
      ;;
  esac
}

debian_validate_identity_source() {
  IDENTITY_SOURCE="${IDENTITY_SOURCE:-none}"
  case "$IDENTITY_SOURCE" in
    none|usb-env) ;;
    *) die "Unsupported IDENTITY_SOURCE: $IDENTITY_SOURCE (expected none|usb-env)" ;;
  esac
}

debian_validate_identity_config() {
  debian_validate_identity_source

  if [[ -n "${IDENTITY_REQUIRED:-}" ]]; then
    debian_validate_bool IDENTITY_REQUIRED
  else
    IDENTITY_REQUIRED="false"
  fi

  IDENTITY_FILE_PATH="${IDENTITY_FILE_PATH:-/identity.env}"
  IDENTITY_DEVICE_LABEL="${IDENTITY_DEVICE_LABEL:-OMNIXYS-ID}"

  if [[ "$IDENTITY_SOURCE" == "usb-env" ]]; then
    [[ "$IDENTITY_FILE_PATH" == /* ]] || die "IDENTITY_FILE_PATH must start with /: $IDENTITY_FILE_PATH"
    [[ -n "$IDENTITY_DEVICE_LABEL" ]] || die "IDENTITY_DEVICE_LABEL must not be empty when IDENTITY_SOURCE=usb-env"
  fi

  # IDENTITY_EMBED gates whether a local ./identity.env is baked into the
  # output ISO. It is unrelated to the runtime usb-env identity lookup. Default
  # is true (backwards-compatible: local builds may self-provision). Published
  # VM release images must set IDENTITY_EMBED=false explicitly (see release.yml).
  if [[ -n "${IDENTITY_EMBED:-}" ]]; then
    debian_validate_bool IDENTITY_EMBED
  else
    IDENTITY_EMBED="true"
  fi

  if [[ "$IDENTITY_EMBED" == "true" ]] && [[ "$IDENTITY_SOURCE" == "none" ]]; then
    warn "IDENTITY_EMBED=true with IDENTITY_SOURCE=none: identity.env (if present) will be baked in, but runtime lookup is disabled"
  fi

  if [[ -n "${IDENTITY_CONFIRM:-}" ]]; then
    debian_validate_bool IDENTITY_CONFIRM
  else
    IDENTITY_CONFIRM="true"
  fi
}

debian_validate_password_input() {
  if [[ -n "${PASSWORD_HASH:-}" ]]; then
    return 0
  fi

  if [[ "$IDENTITY_SOURCE" != "none" && "$IDENTITY_REQUIRED" == "true" ]]; then
    warn "PASSWORD/PASSWORD_HASH not required at build time because runtime identity is mandatory"
    return 0
  fi

  debian_require_var PASSWORD
  debian_validate_password
}

debian_validate_bool() {
  local var_name="$1"
  local normalized
  normalized="$(normalize_bool "${!var_name}")" || die "Invalid boolean for $var_name: ${!var_name}"
  printf -v "$var_name" '%s' "$normalized"
}

debian_validate() {
  step "debian-preseed validate: required variables"
  DOMAIN="${DOMAIN:-}"
  debian_require_var INSTALLER
  debian_require_var ARCH
  debian_require_var INSTALLER_VERSION
  debian_require_var DEBIAN_MAJOR
  debian_require_var DEBIAN_RELEASE
  debian_require_var HOSTNAME
  debian_require_var FULLNAME
  debian_require_var USERNAME
  debian_require_var LANGUAGE
  debian_require_var COUNTRY
  debian_require_var LOCALE
  debian_require_var KEYBOARD
  debian_require_var TIMEZONE
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
  debian_validate_identity_config
  debian_validate_password_input
  debian_validate_target_disk_config
  debian_validate_mirror
  debian_validate_ssh_policy
  debian_validate_network_config

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
