#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$ROOT_DIR/config.env"
DRY_RUN="false"
SHOW_VERSION="false"

# shellcheck disable=SC1091
source "$ROOT_DIR/core/lib/common.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/core/lib/backend.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/core/lib/modules.sh"

usage() {
  cat <<'EOF'
Usage: ./build.sh [options]

Options:
  --config <file>   Use a config profile file
  --dry-run         Validate and simulate build without creating ISO
  --version         Print installer framework version
  -h, --help        Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        [[ $# -gt 1 ]] || die "--config requires a value"
        CONFIG_FILE="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      --version)
        SHOW_VERSION="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
}

validate_config_schema() {
  local config_file="$1"
  local schema_file="$2"

  [[ -f "$schema_file" ]] || {
    warn "Schema file not found: $schema_file"
    return 0
  }

  local config_keys_file expected_keys_file
  config_keys_file="$(mktemp)"
  expected_keys_file="$(mktemp)"

  awk -F= '/^[A-Za-z_][A-Za-z0-9_]*=/{print $1}' "$config_file" | sort -u >"$config_keys_file"
  grep -E '^[A-Za-z_][A-Za-z0-9_]*$' "$schema_file" | sort -u >"$expected_keys_file"

  local missing unknown
  missing="$(comm -23 "$expected_keys_file" "$config_keys_file" || true)"
  unknown="$(comm -13 "$expected_keys_file" "$config_keys_file" || true)"

  if [[ -n "$missing" ]]; then
    warn "Config migration hint: missing keys detected"
    while IFS= read -r key; do
      [[ -n "$key" ]] && warn "  missing: $key"
    done <<<"$missing"
  fi

  if [[ -n "$unknown" ]]; then
    warn "Config migration hint: unknown keys detected"
    while IFS= read -r key; do
      [[ -n "$key" ]] && warn "  unknown: $key"
    done <<<"$unknown"
  fi

  rm -f "$config_keys_file" "$expected_keys_file"
}

print_version() {
  local commit="unknown"
  if command -v git >/dev/null 2>&1; then
    commit="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  fi

  load_config "$CONFIG_FILE"
  echo "Omnixys Installer Framework ${INSTALLER_VERSION:-0.0.0}"
  echo "Installer backend: ${INSTALLER:-unknown}"
  echo "Git commit: $commit"
}

main() {
  parse_args "$@"

  load_config "$CONFIG_FILE"

  if [[ "$SHOW_VERSION" == "true" ]]; then
    print_version
    exit 0
  fi

  ensure_dir "$ROOT_DIR/logs"
  ensure_dir "$ROOT_DIR/output"
  ensure_dir "$ROOT_DIR/downloads"
  ensure_dir "$ROOT_DIR/work"

  LOG_FILE="$ROOT_DIR/logs/build.log"
  : >"$LOG_FILE"

  step "Starting Omnixys Installer Framework"
  info "Config file: $CONFIG_FILE"
  info "Dry run: $DRY_RUN"

  require_commands awk sed grep openssl
  readiness_ok "Config loaded"

  INSTALLER="${INSTALLER:-debian-preseed}"
  load_backend "$INSTALLER"
  readiness_ok "Backend loaded: $INSTALLER"

  validate_config_schema "$CONFIG_FILE" "$ROOT_DIR/installer/$INSTALLER/schema.keys"
  readiness_ok "Config schema checked"

  run_hook_dir "$ROOT_DIR/hooks/pre-build"
  run_modules_phase "pre-build"

  step "Backend validate()"
  validate
  readiness_ok "Config valid"

  step "Backend render()"
  render
  readiness_ok "Preseed generated"

  step "Backend build()"
  build
  readiness_ok "ISO source resolved"

  step "Backend verify()"
  verify
  readiness_ok "ISO/source verification passed"

  run_hook_dir "$ROOT_DIR/hooks/pre-install"
  run_modules_phase "pre-install"

  step "Backend package()"
  package
  if [[ "$DRY_RUN" == "true" ]]; then
    readiness_ok "Builder passed"
    readiness_ok "Ready to build"
  else
    readiness_ok "Output ISO packaged"
  fi

  run_modules_phase "post-install"
  run_hook_dir "$ROOT_DIR/hooks/post-install"

  run_modules_phase "post-build"
  run_hook_dir "$ROOT_DIR/hooks/post-build"

  info "Build flow completed"
  if [[ "$DRY_RUN" == "true" ]]; then
    print_readiness_report
  fi
}

main "$@"
