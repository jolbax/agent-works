#!/usr/bin/env bash
# Simulation test for scripts/loop-await.sh. Uses a fake gh, a fake
# loop-status.sh and a fake sleep (no GitHub or Orca call, no real waiting) in a
# temporary git repository, and checks the exit code, the status call, the
# printed line and the poll budget. Exits non-zero on any mismatch.
#
#   bash scripts/test-loop-await.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HELPER=${HELPER:-$here/loop-await.sh}
[ -f "$HELPER" ] || { echo "test-loop-await: helper not found: $HELPER" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q "$work/repo"
git -C "$work/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m one
HEAD=$(git -C "$work/repo" rev-parse HEAD)
SHA7=${HEAD:0:7}
OLD=0000000000000000000000000000000000000001

# Fake gh: `pr view` prints the next line of $HEADS (the last line repeats) and
# logs each call to $GHLOG. GH_FAIL=1 makes every call fail.
cat > "$work/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$GHLOG"
[ "${GH_FAIL:-0}" = 1 ] && { echo "HTTP 502" >&2; exit 1; }
n=$(wc -l < "$GHLOG")
total=$(wc -l < "$HEADS")
[ "$n" -le "$total" ] || n=$total
sed -n "${n}p" "$HEADS"
STUB
# Fake loop-status.sh: logs its arguments joined by '|'. STATUS_FAIL=1 fails.
cat > "$work/loop-status.sh" <<'STUB'
#!/usr/bin/env bash
(IFS='|'; echo "$*") >> "$STATUSLOG"
[ "${STATUS_FAIL:-0}" = 1 ] && { echo "loop-status: orca-ide worktree set failed" >&2; exit 1; }
echo "loop-status: set"
STUB
# Fake sleep: records each duration instead of waiting.
cat > "$work/sleep" <<'STUB'
#!/usr/bin/env bash
echo "$1" >> "$SLEEPLOG"
STUB
chmod +x "$work/gh" "$work/loop-status.sh" "$work/sleep"

fail=0 n=0
# run <name> <expected-exit> <heads> <expected-status|-> <expected-stdout|-> <expected-polls> <args...>
#   heads: gh's successive head replies, space-separated; expected-status: the
#   loop-status.sh argv joined by '|', '-' for no call.
run() {
  local name=$1 want=$2 heads=$3 status=$4 stdout=$5 polls=$6; shift 6
  n=$((n + 1))
  tr ' ' '\n' <<<"$heads" > "$work/heads"
  : > "$work/gh.log"; : > "$work/status.log"; : > "$work/sleep.log"
  set +e
  out=$(cd "$work/repo" && GH="$work/gh" LOOP_STATUS="$work/loop-status.sh" SLEEP="$work/sleep" \
        HEADS="$work/heads" GHLOG="$work/gh.log" STATUSLOG="$work/status.log" SLEEPLOG="$work/sleep.log" \
        bash "$HELPER" "$@" 2>"$work/err")
  code=$?
  set -e
  got_status=$(cat "$work/status.log"); [ -n "$got_status" ] || got_status=-
  [ -n "$out" ] || out=-
  got_polls=$(wc -l < "$work/gh.log" | tr -d ' ')
  slept=$(paste -sd+ "$work/sleep.log"); slept=$((${slept:-0}))
  if [ "$code" = "$want" ] && [ "$got_status" = "$status" ] && [ "$out" = "$stdout" ] && [ "$got_polls" = "$polls" ] && [ "$slept" -le 60 ]; then
    echo "PASS  $name (exit $code, $got_polls polls, ${slept}s)"
  else
    echo "FAIL  $name: exit $code (want $want); status '$got_status' (want '$status'); stdout '$out' (want '$stdout'); polls $got_polls (want $polls); slept ${slept}s (max 60); stderr: $(cat "$work/err")"
    fail=1
  fi
}

A="PR #7 at $SHA7: review, then type: approve $SHA7"
J="PR #7 at $SHA7: ready for the judge (launch it, then wait for its verdict)"

run "approve: head matches, exact line set and printed" 0 "$HEAD" "in-review|$A|--pr|7" "$A" 1 7 approve
run "judge: head matches, exact line set and printed"   0 "$HEAD" "in-review|$J|--pr|7" "$J" 1 7 judge
n=$((n + 1)); if [[ "$J" != *"type: approve"* ]]; then echo "PASS  judge line does not contain type: approve"; else echo "FAIL  judge line contains type: approve"; fail=1; fi
run "head appears after two polls"                      0 "$OLD $OLD $HEAD" "in-review|$A|--pr|7" "$A" 3 7 approve
run "head behind after 60 s: exit 1, no status"         1 "$OLD" - - 13 7 approve
GH_FAIL=1 run "gh failing for 60 s: exit 1, no status"  1 "$HEAD" - - 13 7 judge
STATUS_FAIL=1 run "loop-status.sh fails: exit 1, no line printed" 1 "$HEAD" "in-review|$A|--pr|7" - 1 7 approve
LOOP_AWAIT_INTERVAL=7 run "poll budget capped at 60 s with another interval" 1 "$OLD" - - 10 7 judge
run "unknown mode is a usage error"                     2 "$HEAD" - - 0 7 merge
run "non-numeric PR is a usage error"                   2 "$HEAD" - - 0 seven approve
run "missing mode is a usage error"                     2 "$HEAD" - - 0 7

[ "$fail" = 0 ] && echo "test-loop-await: all $n scenarios behave (simulation, fake gh, loop-status.sh and sleep)" || echo "test-loop-await: FAILURES (simulation, fake gh, loop-status.sh and sleep)"
exit $fail
