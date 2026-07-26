#!/usr/bin/env bash
set -Eeuo pipefail
phase="${1:-}"
case "$phase" in
  pre-build)
    # Placeholder for future SSH policy checks.
    exit 0
    ;;
  post-build)
    # Placeholder for future SSH artifact verification.
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
