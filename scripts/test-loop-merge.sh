#!/usr/bin/env bash
# Simulation test for scripts/loop-merge.sh. Uses a fake gh (nothing reaches
# GitHub) to drive every helper scenario and checks the exit code, which gh
# calls were made and key output. Exits non-zero on any mismatch.
#
#   bash scripts/test-loop-merge.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HELPER=${HELPER:-$here/loop-merge.sh}
[ -f "$HELPER" ] || { echo "test-loop-merge: helper not found: $HELPER" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
HEAD=a1b2c3d4e5f60718293a4b5c6d7e8f9012345678

# Fake gh. `pr view` prints $FIXTURE; every call is appended to $LOG.
# MERGE_FAIL=1 makes `pr merge` fail; VIEW_FAIL=1 makes `pr view` fail.
cat > "$work/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$LOG"
case "$1 $2" in
  "pr view") [ "${VIEW_FAIL:-0}" = 1 ] && { echo "HTTP 502" >&2; exit 1; }
             if [[ " $* " == *" mergeCommit "* ]]; then echo deadbeef; else cat "$FIXTURE"; fi ;;
  "pr merge") [ "${MERGE_FAIL:-0}" = 1 ] && { echo "merge failed" >&2; exit 1; } ;;
esac
exit 0
STUB
chmod +x "$work/gh"

# fixture <file> [key=value ...]: write a gh pr view result; keys override defaults.
#   state draft base kind check(success|pending|failed|none|status|rerun-ok|rerun-bad)
#   verdict(none|pass|blocking|other|legacy)
fixture() {
  python3 -I - "$HEAD" "$@" <<'PY'
import json, sys
head, out, kv = sys.argv[1], sys.argv[2], dict(a.split("=", 1) for a in sys.argv[3:])
o = {"state": "OPEN", "draft": "true", "base": "main", "kind": "spec", "check": "success", "verdict": "none", **kv}
checks = {
    "success": [{"__typename": "CheckRun", "name": "openspec", "status": "COMPLETED", "conclusion": "SUCCESS"}],
    "pending": [{"__typename": "CheckRun", "name": "openspec", "status": "IN_PROGRESS", "conclusion": ""}],
    "failed":  [{"__typename": "CheckRun", "name": "openspec", "status": "COMPLETED", "conclusion": "FAILURE"}],
    "none":    [{"__typename": "CheckRun", "name": "lint", "status": "COMPLETED", "conclusion": "SUCCESS"}],
    "status":  [{"__typename": "StatusContext", "context": "openspec", "state": "SUCCESS"}],
    "rerun-ok":  [{"__typename": "CheckRun", "name": "openspec", "status": "COMPLETED", "conclusion": "FAILURE", "completedAt": "2026-10-20T10:00:00Z"},
                  {"__typename": "CheckRun", "name": "openspec", "status": "COMPLETED", "conclusion": "SUCCESS", "completedAt": "2026-10-20T11:00:00Z"}],
    "rerun-bad": [{"__typename": "CheckRun", "name": "openspec", "status": "COMPLETED", "conclusion": "SUCCESS", "completedAt": "2026-10-20T10:00:00Z"},
                  {"__typename": "CheckRun", "name": "openspec", "status": "COMPLETED", "conclusion": "FAILURE", "completedAt": "2026-10-20T11:00:00Z"}],
}[o["check"]]
old = {"createdAt": "2026-10-20T10:00:00Z", "body": "Verdict: BLOCKING (2 findings) at " + head[:7]}
comments = {
    "none": [{"createdAt": "2026-10-20T09:00:00Z", "body": "looks fine"}],
    "pass": [old, {"createdAt": "2026-10-20T11:00:00Z", "body": "Verdict: PASS at " + head[:7] + "\n\ndetails"}],
    "blocking": [{"createdAt": "2026-10-20T11:00:00Z", "body": "Verdict: PASS at " + head[:7]}, {**old, "createdAt": "2026-10-20T12:00:00Z"}],
    "other": [{"createdAt": "2026-10-20T11:00:00Z", "body": "Verdict: PASS at 0000000"}],
    "legacy": [{"createdAt": "2026-10-20T11:00:00Z", "body": "Verdict: PASS"}],
}[o["verdict"]]
body = "## Summary\n\nx\n\n## Kind\n\n" + ("Kind: " + o["kind"] if o["kind"] != "none" else "Kind:") + "\n"
json.dump({"state": o["state"], "isDraft": o["draft"] == "true", "baseRefName": o["base"], "headRefOid": head,
           "body": body, "statusCheckRollup": checks, "comments": comments}, open(out, "w"))
PY
}

fail=0 n=0
# run <name> <expected-exit> <expected-calls> <expected-output-substring> <sha> [extra args] -- [fixture keys]
# expected-calls: the gh subcommands after `pr view`, space-separated, e.g. "ready comment merge"; "-" for none.
run() {
  local name=$1 want=$2 calls=$3 needle=$4 sha=$5; shift 5
  local extra=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do extra+=("$1"); shift; done
  [ "$#" -gt 0 ] && shift
  n=$((n + 1))
  fixture "$work/pr.json" "$@"
  : > "$work/log"
  set +e
  out=$(LOG="$work/log" FIXTURE="$work/pr.json" MERGE_FAIL="${MERGE_FAIL:-0}" VIEW_FAIL="${VIEW_FAIL:-0}" GH="$work/gh" \
        bash "$HELPER" 42 "$sha" ${extra[@]+"${extra[@]}"} 2>&1)
  code=$?
  set -e
  got=$(grep -v '^pr view' "$work/log" | awk '{print $2}' | paste -sd' ' - || true)
  [ -n "$got" ] || got=-
  local ok=1
  [ "$code" = "$want" ] || ok=0
  [ "$got" = "$calls" ] || ok=0
  [[ "$out" == *"$needle"* ]] || ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS  $name (exit $code, calls: $got)"
  else
    echo "FAIL  $name: exit $code (want $want), calls '$got' (want '$calls'), output: $out"
    fail=1
  fi
}

run "spec PR merges at the approved head"      0 "ready comment merge" "merged #42 at $HEAD" "${HEAD:0:7}"
grep -q -- "--match-head-commit $HEAD" "$work/log" && echo "PASS  merge is bound with --match-head-commit <full head>" \
  || { echo "FAIL  merge call lacks --match-head-commit $HEAD: $(cat "$work/log")"; fail=1; }
if grep -q "^pr comment 42 --body Operator approved head $HEAD in Orca (approve ${HEAD:0:7}); scripts/loop-merge.sh is merging at this head.$" "$work/log" \
   && ! grep "^pr comment" "$work/log" | grep -qiE "merged"; then
  echo "PASS  audit comment names the head and does not claim the merge"
else
  echo "FAIL  audit comment wrong: $(grep '^pr comment' "$work/log")"; fail=1
fi
run "ready PR is not marked ready again"       0 "comment merge" "merged #42" "${HEAD:0:7}" -- draft=false
run "full 40-char approval accepted"           0 "ready comment merge" "merged #42" "$HEAD"
run "commit status context counts as check"    0 "ready comment merge" "merged #42" "${HEAD:0:7}" -- check=status
run "head moved after approval"                4 - "approve the new head" "1234567"
run "openspec check pending"                   5 - "IN_PROGRESS" "${HEAD:0:7}" -- check=pending
run "openspec check failed"                    5 - "FAILURE" "${HEAD:0:7}" -- check=failed
run "openspec check missing"                   5 - "has not reported" "${HEAD:0:7}" -- check=none
run "failed run then successful re-run"        0 "ready comment merge" "merged #42" "${HEAD:0:7}" -- check=rerun-ok
run "successful run then failed re-run"        5 - "FAILURE" "${HEAD:0:7}" -- check=rerun-bad
run "implementation without verdict"           6 - "no 'Verdict" "${HEAD:0:7}" -- kind=implementation
run "implementation, newest verdict blocking"  6 - "not PASS" "${HEAD:0:7}" -- kind=implementation verdict=blocking
run "implementation, PASS for another head"    6 - "judge again" "${HEAD:0:7}" -- kind=implementation verdict=other
run "implementation, legacy verdict w/o head" 6 - "no 'Verdict" "${HEAD:0:7}" -- kind=implementation verdict=legacy
run "implementation, PASS at the head"         0 "ready comment merge" "merged #42" "${HEAD:0:7}" -- kind=implementation verdict=pass
run "archive PR needs no verdict"              0 "ready comment merge" "merged #42" "${HEAD:0:7}" -- kind=archive
run "closed PR"                                3 - "not OPEN" "${HEAD:0:7}" -- state=CLOSED
run "wrong base"                               3 - "not 'main'" "${HEAD:0:7}" -- base=develop
run "missing Kind"                             3 - "no 'Kind" "${HEAD:0:7}" -- kind=none
run "SHA too short"                            2 - "7 to 40 hex" "a1b2c3"
run "SHA not hex"                              2 - "7 to 40 hex" "zzzzzzz"
run "dry run changes nothing"                  0 - "would merge #42 at $HEAD" "${HEAD:0:7}" --dry-run
run "dry run still refuses a moved head"       4 - "approve the new head" "1234567" --dry-run
MERGE_FAIL=1 run "merge call fails, no retry"  1 "ready comment merge" "not retried" "${HEAD:0:7}"
VIEW_FAIL=1 run "gh pr view fails"             1 - "gh pr view #42 failed" "${HEAD:0:7}"

[ "$fail" = 0 ] && echo "test-loop-merge: all $n scenarios behave (simulation, fake gh)" || echo "test-loop-merge: FAILURES (simulation, fake gh)"
exit $fail
