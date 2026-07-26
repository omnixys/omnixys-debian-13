#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/core/lib/common.sh"

[[ -f "$ROOT_DIR/build.sh" ]] || die "build.sh missing"
[[ -f "$ROOT_DIR/core/lib/backend.sh" ]] || die "backend loader missing"
[[ -f "$ROOT_DIR/core/lib/modules.sh" ]] || die "module loader missing"

info "Core tests passed"
