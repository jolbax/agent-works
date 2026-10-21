#!/usr/bin/env bash
# Regression test for scripts/spec-length.sh. Builds stub change directories
# with requirements of known length and checks the exit code and which
# requirements are named. Exits non-zero on any mismatch.
#
#   bash scripts/test-spec-length.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HELPER=${HELPER:-$here/spec-length.sh}
[ -f "$HELPER" ] || { echo "test-spec-length: helper not found: $HELPER" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# text <n>: a requirement sentence of exactly n characters.
text() { local s="The helper SHALL "; printf '%s' "$s"; printf 'x%.0s' $(seq 1 $(($1 - ${#s}))); }

# change <name> <section> <requirement-name> <body>...: one spec.md with one
# requirement per name/body pair under <section> (ADDED or MODIFIED), each with
# a long scenario that must not count.
change() {
  local d="$work/$1" section=$2; shift 2
  mkdir -p "$d/specs/cap"
  { echo "## $section Requirements"; echo
    while [ "$#" -gt 0 ]; do
      printf '### Requirement: %s\n%s\n\n#### Scenario: s\n- **WHEN** %s\n- **THEN** ok\n\n' "$1" "$2" "$(text 900)"
      shift 2
    done
  } > "$d/specs/cap/spec.md"
}

fail=0 n=0
# run <name> <expected-exit> <expected-named|-> <dir>; expected-named is the
# requirement names reported over the limit, joined by '|', '-' for none.
run() {
  local name=$1 want=$2 named=$3 dir=$4
  n=$((n + 1))
  set +e
  out=$(bash "$HELPER" "$dir" 2>&1)
  code=$?
  set -e
  got=$(sed -n 's/^spec-length: .*: "\(.*\)" is [0-9]* characters.*/\1/p' <<<"$out" | paste -sd'|' -)
  [ -n "$got" ] || got=-
  if [ "$code" = "$want" ] && [ "$got" = "$named" ]; then
    echo "PASS  $name (exit $code)"
  else
    echo "FAIL  $name: exit $code (want $want); named '$got' (want '$named'); output: $out"
    fail=1
  fi
}

change at500 ADDED "At limit" "$(text 500)"
change over501 MODIFIED "Over limit" "$(text 501)"
change mixed MODIFIED "Fits" "$(text 500)" "Too long" "$(text 501)" "Also fits" "$(text 10)"
two=$(text 250)
change multiline ADDED "Two lines" "$two
   $(printf 'y%.0s' $(seq 1 249))   "
change multiline-over ADDED "Two lines over" "$two

$(printf 'y%.0s' $(seq 1 250))"
mkdir -p "$work/empty"

run "requirement at 500 characters passes"            0 -          "$work/at500"
run "MODIFIED requirement at 501 characters is named" 1 "Over limit" "$work/over501"
run "only the overlong requirement is named"          1 "Too long"   "$work/mixed"
run "lines trimmed, joined by one newline (500)"      0 -          "$work/multiline"
run "blank line dropped, joined by one newline (501)" 1 "Two lines over" "$work/multiline-over"
run "no specs directory is a usage error"             2 -          "$work/empty"

[ "$fail" = 0 ] && echo "test-spec-length: all $n scenarios behave (stub change directories)" || echo "test-spec-length: FAILURES (stub change directories)"
exit $fail
