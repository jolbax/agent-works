#!/usr/bin/env bash
# Hand-off helper for the spec-driven loop: announces a PR to the operator only
# once GitHub shows the head this worktree pushed, and says who acts next.
#
#   bash scripts/loop-await.sh <pr> approve|judge
#
# Polls `gh pr view <pr> --json headRefOid` for at most 60 seconds until it
# equals `git rev-parse HEAD`. If it never does, exits 1 and sets no status.
# The 60 seconds are elapsed time: each `gh` call is stopped when the time left
# runs out, so a slow or hung request cannot extend the wait.
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
#   LOOP_AWAIT_LIMIT     deadline in seconds, 1 to 60 (default: 60); it can only
#                        shorten the wait, and tests use it for real-time cases
#   SLEEP                sleep command between polls (default: sleep); tests
#                        replace it. A fake sleep advances the deadline by what
#                        it was asked to sleep, as a real one would.
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
limit=${LOOP_AWAIT_LIMIT:-60}
[[ "$limit" =~ ^[1-9][0-9]*$ ]] && [ "$limit" -le 60 ] || { echo "loop-await: LOOP_AWAIT_LIMIT must be 1 to 60, got '$limit'" >&2; exit 2; }

head=$(git rev-parse HEAD) || { echo "loop-await: not inside a git worktree" >&2; exit 2; }

# Time in milliseconds. Elapsed is the larger of the real time since start and
# the time asked of SLEEP (equal or smaller with a real sleep).
now_ms() { local t=${EPOCHREALTIME//[!0-9]/}; echo $((10#$t / 1000)); }
secs() { if [ $(($1 % 1000)) = 0 ]; then echo $(($1 / 1000)); else printf '%d.%03d' $(($1 / 1000)) $(($1 % 1000)); fi; }
start=$(now_ms) slept=0
left_ms() { local real=$(($(now_ms) - start)); echo $((limit * 1000 - (real > slept ? real : slept))); }

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
# remote_head <ms>: the PR head from gh, or nothing if gh fails or is still
# running after <ms> milliseconds (it is then stopped).
remote_head() {
  local gh_pid watcher
  : > "$tmp"
  "$GH_CMD" pr view "$pr" --json headRefOid -q .headRefOid > "$tmp" 2>/dev/null &
  gh_pid=$!
  ( trap 'kill "$sp" 2>/dev/null; exit 0' TERM
    sleep "$(secs "$1")" & sp=$!
    wait "$sp"; kill "$gh_pid" 2>/dev/null ) >/dev/null 2>&1 &
  watcher=$!
  if wait "$gh_pid"; then cat "$tmp"; fi
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
}

remote="" seen=""
while :; do
  left=$(left_ms)
  [ "$left" -gt 0 ] && remote=$(remote_head "$left") || remote=""
  [ "$remote" != "$head" ] || break
  [ -z "$remote" ] || seen=$remote
  left=$(left_ms)
  if [ "$left" -le 0 ]; then
    echo "loop-await: PR #$pr head is '${seen:-unknown}', not the local HEAD $head, after ${limit}s; push, then run loop-await.sh again" >&2
    exit 1
  fi
  step=$((left < interval * 1000 ? left : interval * 1000))
  "${SLEEP:-sleep}" "$(secs "$step")"
  slept=$((slept + step))
done

sha7=${head:0:7}
case "$mode" in
  approve) line="PR #$pr at $sha7: review, then type: approve $sha7" ;;
  judge) line="PR #$pr at $sha7: ready for the judge (launch it, then wait for its verdict)" ;;
esac
bash "$STATUS" in-review "$line" --pr "$pr" >&2 || { echo "loop-await: loop-status.sh failed; PR #$pr head $sha7 was not announced in Orca" >&2; exit 1; }
echo "$line"
