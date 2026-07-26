#!/usr/bin/env bash

manifest_value() {
  local manifest="$1"
  local key="$2"
  awk -F': *' -v k="$key" '$1 == k {print $2; exit}' "$manifest" 2>/dev/null | tr -d '"' | tr -d "'"
}

module_manifest_path() {
  local module_name="$1"
  echo "$ROOT_DIR/modules/$module_name/manifest.yaml"
}

load_module() {
  local module_name="$1"
  local manifest
  manifest="$(module_manifest_path "$module_name")"
  [[ -f "$manifest" ]] || die "Module manifest not found: $manifest"
}

enable_module() {
  local module_name="$1"
  load_module "$module_name"
  case ",${ENABLED_MODULES:-}," in
    *",${module_name},"*) ;;
    *) ENABLED_MODULES="${ENABLED_MODULES:+$ENABLED_MODULES,}$module_name" ;;
  esac
}

disable_module() {
  local module_name="$1"
  load_module "$module_name"
  case ",${DISABLED_MODULES:-}," in
    *",${module_name},"*) ;;
    *) DISABLED_MODULES="${DISABLED_MODULES:+$DISABLED_MODULES,}$module_name" ;;
  esac
}

module_dependencies() {
  local module_name="$1"
  local manifest
  manifest="$(module_manifest_path "$module_name")"
  if [[ -f "$manifest" ]]; then
    manifest_value "$manifest" "dependencies"
  fi
}

module_priority() {
  local module_name="$1"
  local manifest value
  manifest="$(module_manifest_path "$module_name")"
  value="$(manifest_value "$manifest" "priority")"
  if [[ -n "$value" ]]; then
    echo "$value"
  else
    echo "100"
  fi
}

module_enabled() {
  local module_name="$1"
  local manifest
  manifest="$(module_manifest_path "$module_name")"

  if [[ "$module_name" == "core" ]]; then
    echo "true"
    return 0
  fi

  case ",${DISABLED_MODULES:-}," in
    *",${module_name},"*) echo "false"; return 0 ;;
  esac

  if [[ -n "${ENABLED_MODULES:-}" ]]; then
    case ",${ENABLED_MODULES}," in
      *",${module_name},"*) echo "true"; return 0 ;;
      *) echo "false"; return 0 ;;
    esac
  fi

  if [[ -f "$manifest" ]] && grep -Eiq '^enabledByDefault:[[:space:]]*true$' "$manifest"; then
    echo "true"
  else
    echo "false"
  fi
}

run_modules_phase() {
  local phase="$1"
  local module_dir module_name module_script prio
  local sortable
  sortable="$(mktemp)"

  while IFS= read -r -d '' module_dir; do
    module_name="$(basename "$module_dir")"
    if [[ "$(module_enabled "$module_name")" != "true" ]]; then
      continue
    fi

    prio="$(module_priority "$module_name")"
    printf '%s|%s|%s\n' "$prio" "$module_name" "$module_dir" >>"$sortable"
  done < <(find "$ROOT_DIR/modules" -mindepth 1 -maxdepth 1 -type d -print0)

  if [[ -s "$sortable" ]]; then
    while IFS='|' read -r _ module_name module_dir; do
      module_script="$module_dir/module.sh"
      [[ -f "$module_script" ]] || continue

      step "Module[$module_name] phase: $phase"
      info "Module[$module_name] dependencies: $(module_dependencies "$module_name")"
      run_cmd bash "$module_script" "$phase" "$ROOT_DIR"
    done < <(sort -n -t '|' -k1,1 -k2,2 "$sortable")
  fi

  rm -f "$sortable"
}
