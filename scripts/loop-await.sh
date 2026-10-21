#!/usr/bin/env bash
# Hand-off helper for the spec-driven loop: announces a PR to the operator only
# once GitHub shows the head this worktree pushed, and says who acts next.
#
#   bash scripts/loop-await.sh <pr> approve|judge
#
# Polls `gh pr view <pr> --json headRefOid` for at most 60 seconds until it
# equals `git rev-parse HEAD`. If it never does, exits 1 and sets no status.
# Otherwise sets `in-review` with the PR linked through loop-status.sh and prints
# the line (on stdout, last):
#   approve  PR #<pr> at <sha7>: review, then type: approve <sha7>
#   judge    PR #<pr> at <sha7>: ready for the judge (launch it, then wait for its verdict)
# Propose and archive use approve; apply and fix use judge, so only the judge's
# verdict line tells the operator to approve an implementation PR.
#
# Exit codes: 0 announced; 1 head not confirmed within 60 s, or loop-status.sh
# failed (the line is then not printed); 2 usage.
#
# Environment (all optional):
#   GH                   gh command (default: gh); tests point it at a stub
#   LOOP_STATUS          status helper (default: loop-status.sh next to this script)
#   LOOP_AWAIT_INTERVAL  seconds between polls (default: 5)
#   SLEEP                sleep command (default: sleep); tests replace it
set -euo pipefail

usage() { echo "usage: loop-await.sh <pr> approve|judge" >&2; exit 2; }
[ "$#" -eq 2 ] || usage
pr=$1 mode=$2
[[ "$pr" =~ ^[0-9]+$ ]] || { echo "loop-await: PR must be a number, got '$pr'" >&2; exit 2; }
case "$mode" in approve|judge) ;; *) usage ;; esac

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GH_CMD=${GH:-gh}
STATUS=${LOOP_STATUS:-$here/loop-status.sh}
interval=${LOOP_AWAIT_INTERVAL:-5}
[[ "$interval" =~ ^[1-9][0-9]*$ ]] || { echo "loop-await: LOOP_AWAIT_INTERVAL must be a positive integer, got '$interval'" >&2; exit 2; }
limit=60

head=$(git rev-parse HEAD) || { echo "loop-await: not inside a git worktree" >&2; exit 2; }

waited=0 remote=""
while :; do
  remote=$("$GH_CMD" pr view "$pr" --json headRefOid -q .headRefOid 2>/dev/null) || remote=""
  [ "$remote" != "$head" ] || break
  if [ "$waited" -ge "$limit" ]; then
    echo "loop-await: PR #$pr head is '${remote:-unknown}', not the local HEAD $head, after ${limit}s; push, then run loop-await.sh again" >&2
    exit 1
  fi
  step=$((limit - waited < interval ? limit - waited : interval))
  "${SLEEP:-sleep}" "$step"
  waited=$((waited + step))
done

sha7=${head:0:7}
case "$mode" in
  approve) line="PR #$pr at $sha7: review, then type: approve $sha7" ;;
  judge) line="PR #$pr at $sha7: ready for the judge (launch it, then wait for its verdict)" ;;
esac
bash "$STATUS" in-review "$line" --pr "$pr" >&2 || { echo "loop-await: loop-status.sh failed; PR #$pr head $sha7 was not announced in Orca" >&2; exit 1; }
echo "$line"
