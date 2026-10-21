#!/usr/bin/env bash
# Status helper for the spec-driven loop: sets a worker's Orca worktree status,
# comment and linked PR, so the operator sees in Orca which worker waits on them.
# Orca metadata is a notification only; GitHub stays the record.
#
#   bash scripts/loop-status.sh <status> <message> [--pr <N>] [--issue <N>] [--worktree <selector>]
#
# <status> is one of the default board ids: todo, in-progress, in-review,
# completed. in-review ("waiting for the operator") marks the worktree unread;
# every other status marks it read. The default worktree is the one containing
# the current directory (path:<git toplevel>). The `current`/`active` selector is
# not used: it may mean the worktree active in the Orca window. `branch:` needs
# the full branch name.
#
# Exit codes: 0 set; 1 the orca-ide call failed or its result was not ok; 2 usage.
#
# Environment (optional):
#   ORCA_IDE  orca-ide command (default: orca-ide); tests point it at a stub
set -euo pipefail

usage() { echo "usage: loop-status.sh <todo|in-progress|in-review|completed> <message> [--pr <N>] [--issue <N>] [--worktree <selector>]" >&2; exit 2; }

[ "$#" -ge 2 ] || usage
status=$1 message=$2
shift 2
pr="" issue="" worktree=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr) [ "$#" -ge 2 ] || usage; pr=$2; shift 2 ;;
    --issue) [ "$#" -ge 2 ] || usage; issue=$2; shift 2 ;;
    --worktree) [ "$#" -ge 2 ] || usage; worktree=$2; shift 2 ;;
    *) usage ;;
  esac
done

case "$status" in
  todo|in-progress|in-review|completed) ;;
  *) echo "loop-status: unknown status '$status' (expected todo, in-progress, in-review or completed)" >&2; exit 2 ;;
esac
[[ "$message" =~ [^[:space:]] ]] || { echo "loop-status: the message must not be empty or only whitespace" >&2; exit 2; }
[ -z "$pr" ] || [[ "$pr" =~ ^[0-9]+$ ]] || { echo "loop-status: --pr must be a number, got '$pr'" >&2; exit 2; }
[ -z "$issue" ] || [[ "$issue" =~ ^[0-9]+$ ]] || { echo "loop-status: --issue must be a number, got '$issue'" >&2; exit 2; }
if [ -z "$worktree" ]; then
  top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "loop-status: not inside a git worktree; pass --worktree" >&2; exit 2; }
  worktree="path:$top"
fi

ORCA=${ORCA_IDE:-orca-ide}
args=(worktree set --worktree "$worktree" --workspace-status "$status" --comment "$message")
[ -z "$pr" ] || args+=(--pr "$pr")
[ -z "$issue" ] || args+=(--issue "$issue")
if [ "$status" = in-review ]; then args+=(--unread); else args+=(--read); fi

out=$("$ORCA" "${args[@]}" --json) || { echo "loop-status: orca-ide worktree set failed for $worktree" >&2; exit 1; }
ok=$(python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("ok") is True)' <<<"$out" 2>/dev/null) || ok=False
[ "$ok" = True ] || { echo "loop-status: orca-ide did not report ok for $worktree" >&2; exit 1; }
echo "loop-status: $worktree -> $status${pr:+ (PR #$pr)}: $message"
