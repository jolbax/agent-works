#!/usr/bin/env bash
# Simulation test for scripts/loop-status.sh. Uses a fake orca-ide (no real
# Orca call) to drive each helper scenario and checks the exit code and the
# exact arguments passed. Exits non-zero on any mismatch.
#
#   bash scripts/test-loop-status.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HELPER=${HELPER:-$here/loop-status.sh}
[ -f "$HELPER" ] || { echo "test-loop-status: helper not found: $HELPER" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q "$work/repo"
top=$(cd "$work/repo" && git rev-parse --show-toplevel)

# Fake orca-ide. RESULT selects the reply (ok, notok, garbage, fail); each call's
# arguments are written one per line to $LOG.
cat > "$work/orca-ide" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$LOG"
case "${RESULT:-ok}" in
  ok) echo '{"id":"x","ok":true,"result":{}}' ;;
  notok) echo '{"id":"x","ok":false,"error":{"code":"selector_ambiguous","message":"matches 3 worktrees"}}' ;;
  garbage) echo 'not json' ;;
  fail) echo "runtime unreachable" >&2; exit 1 ;;
esac
STUB
chmod +x "$work/orca-ide"

fail=0 n=0
# run <name> <expected-exit> <expected-args|-> <args...>; expected-args is the call's argv joined by '|', '-' for no call.
run() {
  local name=$1 want=$2 args=$3; shift 3
  n=$((n + 1))
  : > "$work/log"
  set +e
  out=$(cd "$work/repo" && LOG="$work/log" ORCA_IDE="$work/orca-ide" bash "$HELPER" "$@" 2>&1)
  code=$?
  set -e
  got=$(paste -sd'|' - < "$work/log")
  [ -n "$got" ] || got=-
  if [ "$code" = "$want" ] && [ "$got" = "$args" ]; then
    echo "PASS  $name (exit $code)"
  else
    echo "FAIL  $name: exit $code (want $want); args '$got' (want '$args'); output: $out"
    fail=1
  fi
}

run "in-review marks unread and links the PR" 0 \
  "worktree|set|--worktree|branch:feat|--workspace-status|in-review|--comment|spec ready: approve abc1234|--pr|7|--unread|--json" \
  in-review "spec ready: approve abc1234" --pr 7 --worktree branch:feat
run "--issue links the issue" 0 \
  "worktree|set|--worktree|branch:feat|--workspace-status|in-progress|--comment|filed|--issue|13|--read|--json" \
  in-progress filed --issue 13 --worktree branch:feat
run "other status marks read" 0 \
  "worktree|set|--worktree|branch:feat|--workspace-status|in-progress|--comment|working|--read|--json" \
  in-progress working --worktree branch:feat
run "default worktree is the git toplevel" 0 \
  "worktree|set|--worktree|path:$top|--workspace-status|completed|--comment|merged|--read|--json" \
  completed merged
run "unknown status rejected without a call" 2 - review "typo"
run "non-numeric PR rejected without a call" 2 - in-review x --pr seven
run "non-numeric issue rejected without a call" 2 - in-review x --issue 1a
run "missing message is a usage error"      2 - in-review
RESULT=fail    run "orca-ide call fails"          1 "worktree|set|--worktree|branch:f|--workspace-status|todo|--comment|m|--read|--json" todo m --worktree branch:f
RESULT=notok   run "result not ok (selector_ambiguous)"             1 "worktree|set|--worktree|branch:f|--workspace-status|todo|--comment|m|--read|--json" todo m --worktree branch:f
RESULT=garbage run "result not JSON"              1 "worktree|set|--worktree|branch:f|--workspace-status|todo|--comment|m|--read|--json" todo m --worktree branch:f

[ "$fail" = 0 ] && echo "test-loop-status: all $n scenarios behave (simulation, fake orca-ide)" || echo "test-loop-status: FAILURES (simulation, fake orca-ide)"
exit $fail
