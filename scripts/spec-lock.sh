#!/usr/bin/env bash
# Spec lock for the spec-driven loop. Run by CI on every pull request.
#
#   BASE=<base-sha> bash scripts/spec-lock.sh
#
# Rule: a PR that changes anything outside openspec/ may change, inside
# openspec/changes/ and openspec/specs/, only tasks.md files. So:
#   - a spec PR (openspec/ only) is free to write the change;
#   - an implementation PR can tick tasks.md but never edit the approved
#     proposal, design or delta specs, nor the main specs;
#   - an archive PR (openspec/ only) is free to move the change and sync specs.
# Approval of a change is the merge of its spec PR; this keeps that approval
# from being edited after the fact.
#
# Separately, changes to tooling and test configuration are LISTED (not blocked)
# so the judge and the human reviewer see them.
set -euo pipefail
BASE="${BASE:?set BASE to the pull request base commit}"

files=$(git diff --name-only "$BASE"...HEAD)
[ -n "$files" ] || { echo "spec-lock: no changes"; exit 0; }

outside=$(grep -v '^openspec/' <<<"$files" || true)
locked=$(grep -E '^openspec/(changes|specs)/' <<<"$files" | grep -vE '/(tasks\.md|\.gitkeep)$' || true)

fail=0
if [ -n "$outside" ] && [ -n "$locked" ]; then
  echo "spec-lock: FAIL — this PR changes code or docs outside openspec/ AND edits locked spec files:"
  sed 's/^/  /' <<<"$locked"
  echo "Split it: spec changes go in a spec PR (openspec/ only); implementation PRs may only tick tasks.md."
  fail=1
else
  echo "spec-lock: PASS"
fi

config=$(grep -E '(^|/)(\.eslintrc[^/]*|eslint\.config\.[^/]+|\.prettierrc[^/]*|prettier\.config\.[^/]+|biome\.jsonc?|tsconfig[^/]*\.json|(vitest|jest|playwright)\.config\.[^/]+|\.nvmrc|\.node-version|package\.json)$|^\.github/' <<<"$files" || true)
if [ -n "$config" ]; then
  msg="Tooling/test configuration changed — the judge must justify each against the approved spec:"
  echo "spec-lock: NOTE — $msg"; sed 's/^/  /' <<<"$config"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    { echo "### ⚠️ $msg"; sed 's/^/- `/; s/$/`/' <<<"$config"; } >> "$GITHUB_STEP_SUMMARY"
  fi
fi
exit $fail
