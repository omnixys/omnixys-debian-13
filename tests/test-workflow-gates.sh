#!/usr/bin/env bash
# shellcheck disable=SC2016 # workflow expressions are intentional literal fixtures
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEMANTIC_WORKFLOW="$ROOT_DIR/.github/workflows/semantic-release.yml"
RELEASE_WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"

grep -q 'workflows: \[CI\]' "$SEMANTIC_WORKFLOW"
grep -q 'types: \[completed\]' "$SEMANTIC_WORKFLOW"
grep -q "workflow_run.conclusion == 'success'" "$SEMANTIC_WORKFLOW"
grep -q "workflow_run.event == 'push'" "$SEMANTIC_WORKFLOW"
grep -q "workflow_run.head_branch == 'main'" "$SEMANTIC_WORKFLOW"
grep -q 'ref: \${{ github.event.workflow_run.head_sha }}' "$SEMANTIC_WORKFLOW"
if grep -qE '^  push:' "$SEMANTIC_WORKFLOW"; then
  echo "semantic-release must not run directly on push" >&2
  exit 1
fi

grep -q 'workflows: \[Semantic Release\]' "$RELEASE_WORKFLOW"
grep -q 'types: \[completed\]' "$RELEASE_WORKFLOW"
grep -q "workflow_run.conclusion == 'success'" "$RELEASE_WORKFLOW"
grep -q '^  release-gate:' "$RELEASE_WORKFLOW"
grep -q "if: needs.release-gate.outputs.publish == 'true'" "$RELEASE_WORKFLOW"
grep -q "git tag --points-at HEAD --list 'v\*'" "$RELEASE_WORKFLOW"
if grep -qE '^  release:' "$RELEASE_WORKFLOW"; then
  echo "release assets must not run directly on release publication" >&2
  exit 1
fi

echo "Workflow release gates test passed"
