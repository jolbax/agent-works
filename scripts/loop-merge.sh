#!/usr/bin/env bash
# Merge helper for the spec-driven loop: merges a PR on the operator's approval
# of its exact head, given in the worker's Orca terminal as `approve <sha>`.
# Every merge stays the operator's decision; this makes it head-bound and audited.
#
#   bash scripts/loop-merge.sh <pr> <sha> [--dry-run]
#
# Checks, in order, from one `gh pr view` (nothing changes if any fails):
#   3  PR not open, base is not $LOOP_BASE, or the body has no `Kind:` line
#   4  head does not start with <sha>: the operator must approve the new head
#   5  the latest run of check $LOOP_REQUIRED_CHECK on the head is missing,
#      pending or failed
#   6  Kind: implementation and the newest `Verdict:` comment is not
#      `Verdict: PASS at <sha>` for the head (a verdict naming no head counts
#      as missing)
# Then: `gh pr ready` if draft, an audit comment, and
# `gh pr merge --merge --match-head-commit <head>`. No retry: a merge whose
# outcome is unknown stays unknown until someone looks.
#
# Exit codes: 0 merged (or would merge, with --dry-run); 1 a gh call failed or
# its result could not be read; 2 usage; 3-6 as above.
#
# The repository is the worktree's origin, as gh resolves it.
#
# Environment (all optional):
#   GH                   gh command (default: gh); tests point it at a stub
#   LOOP_BASE            required base branch (default: main)
#   LOOP_REQUIRED_CHECK  required check name (default: openspec)
set -euo pipefail

usage() { echo "usage: loop-merge.sh <pr> <sha> [--dry-run]" >&2; exit 2; }
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || usage
pr=$1 sha=$2 dry=0
if [ "$#" -eq 3 ]; then [ "$3" = --dry-run ] || usage; dry=1; fi
[[ "$pr" =~ ^[0-9]+$ ]] || { echo "loop-merge: PR must be a number, got '$pr'" >&2; exit 2; }
[[ "$sha" =~ ^[0-9a-fA-F]{7,40}$ ]] || { echo "loop-merge: SHA must be 7 to 40 hex characters, got '$sha'" >&2; exit 2; }

GH_CMD=${GH:-gh}

view=$("$GH_CMD" pr view "$pr" --json state,isDraft,baseRefName,headRefOid,body,statusCheckRollup,comments) || {
  echo "loop-merge: gh pr view #$pr failed; nothing changed" >&2; exit 1; }

# Prints "<head> <isDraft>" on success; otherwise "<exit-code> <reason>" on stderr and exits with it.
verdict=$(python3 -I - "$sha" "${LOOP_BASE:-main}" "${LOOP_REQUIRED_CHECK:-openspec}" "$view" <<'PY'
import json, re, sys
sha, base, check, raw = sys.argv[1].lower(), sys.argv[2], sys.argv[3], sys.argv[4]
def stop(code, msg):
    print(f"loop-merge: {msg}; nothing changed", file=sys.stderr); sys.exit(code)
try:
    d = json.loads(raw)
    state, draft, head = d["state"], bool(d["isDraft"]), d["headRefOid"].lower()
    body, rollup, comments = d.get("body") or "", d.get("statusCheckRollup") or [], d.get("comments") or []
except Exception as e:
    stop(1, f"cannot read gh pr view result ({e})")
if state != "OPEN":
    stop(3, f"PR is {state}, not OPEN")
if d.get("baseRefName") != base:
    stop(3, f"PR base is {d.get('baseRefName')!r}, not {base!r}")
m = re.search(r"^Kind:\s*(spec|implementation|archive)\s*$", body, re.M)
if not m:
    stop(3, "PR body has no 'Kind: spec|implementation|archive' line")
kind = m.group(1)
if not head.startswith(sha):
    stop(4, f"approval is for {sha} but the PR head is now {head}: review and approve the new head")
runs = [c for c in rollup if (c.get("name") or c.get("context")) == check]
if not runs:
    stop(5, f"required check {check!r} has not reported on {head[:7]}")
# The latest run decides, so a successful re-run counts. A CheckRun reports
# status/conclusion; a commit StatusContext reports state.
c = max(runs, key=lambda c: c.get("completedAt") or c.get("startedAt") or "")
if c.get("__typename") == "StatusContext" or "state" in c:
    ok, now = c.get("state") == "SUCCESS", c.get("state")
else:
    ok, now = c.get("status") == "COMPLETED" and c.get("conclusion") == "SUCCESS", c.get("conclusion") or c.get("status")
if not ok:
    stop(5, f"required check {check!r} is {now} on {head[:7]}")
if kind == "implementation":
    pat = re.compile(r"^\W*Verdict:\s*(.*?)\s+at\s+([0-9a-fA-F]{7,40})\b")
    found = [(c.get("createdAt") or "", pat.match(c.get("body") or "")) for c in comments]
    found = sorted((f for f in found if f[1]), key=lambda f: f[0])
    if not found:
        stop(6, "implementation PR has no 'Verdict: ... at <sha>' comment")
    result, at = found[-1][1].group(1), found[-1][1].group(2).lower()
    if not result.startswith("PASS"):
        stop(6, f"newest judge verdict is '{result}', not PASS")
    if not head.startswith(at):
        stop(6, f"newest judge verdict is for {at}, not the head {head[:7]}: judge again")
print(head, "true" if draft else "false")
PY
) || exit $?
read -r head draft <<<"$verdict"

if [ "$dry" = 1 ]; then
  echo "loop-merge: would merge #$pr at $head (dry run; nothing changed)"
  exit 0
fi
if [ "$draft" = true ]; then
  "$GH_CMD" pr ready "$pr" >/dev/null || { echo "loop-merge: gh pr ready #$pr failed; not merged" >&2; exit 1; }
fi
"$GH_CMD" pr comment "$pr" --body "Operator approved head $head in Orca (approve $sha); scripts/loop-merge.sh is merging at this head." >/dev/null || {
  echo "loop-merge: audit comment on #$pr failed; not merged" >&2; exit 1; }
"$GH_CMD" pr merge "$pr" --merge --match-head-commit "$head" || {
  echo "loop-merge: gh pr merge #$pr failed; not retried, and the PR stays ready. Check the PR state before doing anything else." >&2; exit 1; }
merged=$("$GH_CMD" pr view "$pr" --json mergeCommit -q .mergeCommit.oid 2>/dev/null || true)
echo "loop-merge: merged #$pr at $head${merged:+ as $merged}"
