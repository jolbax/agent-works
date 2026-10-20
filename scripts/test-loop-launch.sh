#!/usr/bin/env bash
# Simulation test for scripts/loop-launch.sh. Uses a fake orca-ide (no real
# worker is launched) to drive each helper scenario and checks exit code, the
# number of `terminal send` calls and key output. Exits non-zero on any mismatch.
#
#   bash scripts/test-loop-launch.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HELPER=${HELPER:-$here/loop-launch.sh}
[ -f "$HELPER" ] || { echo "test-loop-launch: helper not found: $HELPER" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
echo "build a thing" > "$work/prompt.md"

# Fake orca-ide. SCENARIO selects behaviour; every call is appended to $LOG.
cat > "$work/orca-ide" <<'STUB'
#!/usr/bin/env bash
echo "$1 $2" >> "$LOG"
case "$1 $2" in
  "worktree create")
    case "$SCENARIO" in
      nohandle) echo '{"result":{"launch":{"outcome":{"kind":"chat"}}}}' ;;
      garbage-create) echo 'not json' ;;
      *) echo '{"result":{"launch":{"outcome":{"kind":"terminal","handle":"term_stub"}}}}' ;;
    esac ;;
  "terminal read")
    case "$SCENARIO" in
      delivered) echo '{"result":{"terminal":{"tail":["❯ build a thing","● Running ..."]}}}' ;;
      delivered-codex) echo '{"result":{"terminal":{"tail":["• Working (3s)"]}}}' ;;
      garbage-read) echo 'not json' ;;
      *) echo '{"result":{"terminal":{"tail":["  banner","❯"]}}}' ;;
    esac ;;
  "terminal send")
    case "$SCENARIO" in
      resent) echo '{"result":{"send":{"accepted":true,"prompt":{"stages":["input_accepted","turn_started"]}}}}' ;;
      send-transport-error) echo "transport error; retry-request abc" >&2; exit 1 ;;
      garbage-send) echo 'not json' ;;
      *) echo '{"result":{"send":{"accepted":true,"prompt":{"stages":["input_accepted"]}}}}' ;;
    esac ;;
esac
STUB
chmod +x "$work/orca-ide"

fail=0
# run <scenario> <expected-exit> <expected-sends> <expected-stdout-or-stderr-substring>
run() {
  local scenario=$1 want_rc=$2 want_sends=$3 want_text=$4 rc=0 out sends
  : > "$work/log"
  out=$(SCENARIO=$scenario LOG=$work/log ORCA_IDE=$work/orca-ide LOOP_LAUNCH_WAIT=1 LOOP_LAUNCH_POLL=1 \
        bash "$HELPER" t claude "$work/prompt.md" 2>&1) || rc=$?
  sends=$(grep -c '^terminal send$' "$work/log" || true)
  if [ "$rc" = "$want_rc" ] && [ "$sends" = "$want_sends" ] && grep -qF -- "$want_text" <<<"$out"; then
    echo "PASS $scenario (exit $rc, sends $sends)"
  else
    echo "FAIL $scenario: exit $rc (want $want_rc), sends $sends (want $want_sends), output:"; sed 's/^/    /' <<<"$out"
    fail=1
  fi
}

run delivered            0 0 "handle=term_stub stage=screen_activity"
run delivered-codex      0 0 "handle=term_stub stage=screen_activity"
run resent               0 1 "turn_started (resent once)"
run second-failure       4 1 "handle=term_stub"
run nohandle             3 0 "no terminal handle"
run garbage-create       1 0 "cannot parse worktree create"
run garbage-read         1 0 "cannot parse terminal read"
run garbage-send         1 1 "cannot parse terminal send"
run send-transport-error 1 1 "not resending a new payload"

[ "$fail" = 0 ] && echo "test-loop-launch: all scenarios passed (simulation)" || { echo "test-loop-launch: FAILED" >&2; exit 1; }
