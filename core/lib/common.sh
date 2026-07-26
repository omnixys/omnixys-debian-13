#!/usr/bin/env bash

if [[ -t 1 ]]; then
  C_RESET='\033[0m'
  C_RED='\033[31m'
  C_GREEN='\033[32m'
  C_YELLOW='\033[33m'
  C_BLUE='\033[34m'
else
  C_RESET=''
  C_RED=''
  C_GREEN=''
  C_YELLOW=''
  C_BLUE=''
fi

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log() {
  local level="$1"
  local color="$2"
  shift 2
  local msg="$*"
  local line="[$(timestamp)] [$level] $msg"
  printf '%b%s%b\n' "$color" "$line" "$C_RESET"
  if [[ -n "${LOG_FILE:-}" ]]; then
    printf '%s\n' "$line" >>"$LOG_FILE"
  fi
}

step() { log STEP "$C_BLUE" "$*"; }
info() { log INFO "$C_GREEN" "$*"; }
warn() { log WARN "$C_YELLOW" "$*"; }
error() { log ERROR "$C_RED" "$*"; }

die() {
  error "$*"
  exit 1
}

ensure_dir() {
  mkdir -p "$1"
}

run_cmd() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    info "[dry-run] $*"
    return 0
  fi
  "$@"
}

declare -a READINESS_CHECKS=()

readiness_ok() {
  local msg="$1"
  READINESS_CHECKS+=("OK|$msg")
  info "[readiness] $msg"
}

readiness_fail() {
  local msg="$1"
  READINESS_CHECKS+=("FAIL|$msg")
  error "[readiness] $msg"
}

print_readiness_report() {
  local line status msg symbol
  echo
  echo "Readiness Report"
  echo "----------------"
  for line in "${READINESS_CHECKS[@]:-}"; do
    status="${line%%|*}"
    msg="${line#*|}"
    if [[ "$status" == "OK" ]]; then
      symbol="[OK]"
    else
      symbol="[FAIL]"
    fi
    echo "$symbol $msg"
    if [[ -n "${LOG_FILE:-}" ]]; then
      printf '%s %s\n' "$symbol" "$msg" >>"$LOG_FILE"
    fi
  done
}

require_commands() {
  local missing=0
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      error "Missing command: $cmd"
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]] || die "One or more required tools are missing"
}

normalize_bool() {
  local input="$1"
  case "${input,,}" in
    true|1|yes|y|on) echo "true" ;;
    false|0|no|n|off) echo "false" ;;
    *) return 1 ;;
  esac
}

load_config() {
  local file="$1"
  [[ -f "$file" ]] || die "Config not found: $file"
  # shellcheck disable=SC1090
  source "$file"
}

run_hook_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  local hook
  while IFS= read -r -d '' hook; do
    if [[ -x "$hook" ]]; then
      step "Hook: $hook"
      run_cmd "$hook"
    else
      warn "Skipping non-executable hook: $hook"
    fi
  done < <(find "$dir" -maxdepth 1 -type f -print0 | sort -z)
}
