#!/usr/bin/env bash

load_backend() {
  local installer_name="$1"
  BACKEND_DIR="$ROOT_DIR/installer/$installer_name"
  BACKEND_ENTRY="$BACKEND_DIR/backend.sh"

  [[ -f "$BACKEND_ENTRY" ]] || die "Installer backend not found: $BACKEND_ENTRY"
  # shellcheck disable=SC1090
  source "$BACKEND_ENTRY"

  local fn
  for fn in render validate build verify package; do
    declare -F "$fn" >/dev/null 2>&1 || die "Backend $installer_name does not implement function: $fn"
  done

  info "Loaded backend: $installer_name"
}
