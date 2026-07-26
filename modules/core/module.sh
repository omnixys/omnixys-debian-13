#!/usr/bin/env bash
set -Eeuo pipefail
phase="${1:-}"
case "$phase" in
  pre-build|post-build) exit 0 ;;
  *) exit 0 ;;
esac
