#!/usr/bin/env bash
# Simulation test for scripts/loop-prompt.sh. Drives the helper on stub
# templates and on every template in .agents/loop/ with its documented keys,
# and checks the exit code, the written prompt and the named placeholders.
# Exits non-zero on any mismatch.
#
#   bash scripts/test-loop-prompt.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HELPER=${HELPER:-$here/loop-prompt.sh}
TEMPLATES=${TEMPLATES:-$here/../.agents/loop}
[ -f "$HELPER" ] || { echo "test-loop-prompt: helper not found: $HELPER" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/t.md" <<'T'
# Stub template

Header <not-in-body> is not part of the prompt.

---

Worker for <owner>/<repo>, change <change-name>.

Intake: issue #<issue-number>.
Intake: brief: <brief>

Merge with `loop-merge.sh {N} {sha}`, then report "merged {merge-commit}".
T
printf 'Only a header, no separator <owner>\n' > "$work/nosep.md"
printf 'head\n---\nPlain <owner>, no intake.\n' > "$work/plain.md"

fail=0 n=0
# run <name> <expected-exit> <template> <key=value...>: runs the helper with
# output to $work/out; leaves exit in $code, stderr+stdout in $out.
run() {
  local name=$1 want=$2 tpl=$3; shift 3
  n=$((n + 1))
  rm -f "$work/out"
  set +e
  out=$(bash "$HELPER" "$tpl" "$work/out" "$@" 2>&1)
  code=$?
  set -e
  label=$name
  [ "$code" = "$want" ] || { bad "exit $code (want $want); output: $out"; return 0; }
}
bad() { fail=1; [ -n "$label" ] || return 0; echo "FAIL  $label: $1"; label=""; }
ok() { [ -z "$label" ] || echo "PASS  $label (exit $code)"; }
has() { grep -qF -- "$1" "$work/out" 2>/dev/null || bad "output lacks '$1'"; }
lacks() { ! grep -qF -- "$1" "$work/out" 2>/dev/null || bad "output contains '$1'"; }
names() { grep -qF -- "unfilled launch-time placeholder <$1>" <<<"$out" || bad "does not name <$1>: $out"; }
# keeps_runtime <template>: every {name} of the template body is in the output.
keeps_runtime() {
  local want got
  want=$(sed '1,/^---$/d' "$1" | grep -oE '\{[A-Za-z][A-Za-z0-9 -]*\}' | sort -u | paste -sd' ' -)
  got=$(grep -oE '\{[A-Za-z][A-Za-z0-9 -]*\}' "$work/out" 2>/dev/null | sort -u | paste -sd' ' -)
  [ "$want" = "$got" ] || bad "runtime placeholders changed: '$got' (want '$want')"
}
no_out() { [ ! -e "$work/out" ] || bad "wrote the output file"; }
no_token() { ! grep -qE '<[a-z][a-z0-9-]*>' "$work/out" 2>/dev/null || bad "left a <name> token: $(grep -oE '<[a-z][a-z0-9-]*>' "$work/out" 2>/dev/null | sort -u | paste -sd' ' -)"; }

run "filled: body after ---, keys replaced" 0 "$work/t.md" owner=o repo=r change-name=c issue-number=7
has "Worker for o/r, change c."; has "Intake: issue #7."; lacks "Header"; lacks "# Stub template"; no_token; ok

run "unfilled placeholder named, nothing written" 1 "$work/t.md" owner=o change-name=c issue-number=7
names repo; no_out; ok

run "several unfilled placeholders all named" 1 "$work/t.md" issue-number=7
names owner; names repo; names change-name; no_out; ok

run "Intake: issue given keeps only the issue line" 0 "$work/t.md" owner=o repo=r change-name=c issue-number=7
has "Intake: issue #7."; lacks "Intake: brief"; ok

run "Intake: brief given keeps only the brief line" 0 "$work/t.md" owner=o repo=r change-name=c "brief=add a <thing> & more"
has "Intake: brief: add a <thing> & more"; lacks "Intake: issue"; ok

run "Intake: both given is an error" 2 "$work/t.md" owner=o repo=r change-name=c issue-number=7 brief=b
no_out; ok

run "Intake: neither given is an error" 2 "$work/t.md" owner=o repo=r change-name=c
no_out; ok

run "runtime value untouched (merge-commit=abc)" 0 "$work/t.md" owner=o repo=r change-name=c issue-number=7 merge-commit=abc sha=2
keeps_runtime "$work/t.md"; has '"merged {merge-commit}"'; has '`loop-merge.sh {N} {sha}`'; lacks abc; ok

run "values are literal (& and \\ kept, not re-scanned)" 0 "$work/t.md" 'owner=a&b\1' 'repo=<change-name>' change-name=c issue-number=7
has 'Worker for a&b\1/<change-name>, change c.'; ok

run "template without --- is a usage error" 2 "$work/nosep.md" owner=o
no_out; ok

run "template without Intake lines needs no intake key" 0 "$work/plain.md" owner=o
has "Plain o, no intake."; ok

run "malformed key=value is a usage error" 2 "$work/plain.md" owner
no_out; ok

# Every shipped template with its documented keys (.agents/loop/README.md).
keys_common=(owner=o repo=r change-name=c)
declare -A keys=(
  [propose]="issue-number=7"
  [apply]="issue-number=7 spec-pr-number=8 spec-merge-commit=abc1234 default-branch=main"
  [judge]="pr-number=9"
  [fix]=""
  [archive]="issue-number=7 impl-pr-number=9"
)
for t in propose apply judge fix archive; do
  # shellcheck disable=SC2086
  run "template $t.md filled with its documented keys" 0 "$TEMPLATES/$t.md" "${keys_common[@]}" ${keys[$t]}
  no_token; keeps_runtime "$TEMPLATES/$t.md"
  case "$t" in propose|apply|archive|fix) has "{merge-commit}" ;; esac
  ok
done
run "template propose.md with a brief" 0 "$TEMPLATES/propose.md" "${keys_common[@]}" "brief=a brief"
no_token; lacks "Intake: issue"; ok

[ "$fail" = 0 ] && echo "test-loop-prompt: all $n scenarios behave (simulation, stub and shipped templates)" || echo "test-loop-prompt: FAILURES (simulation, stub and shipped templates)"
exit $fail
