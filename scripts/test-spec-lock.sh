#!/usr/bin/env bash
# Regression test for scripts/spec-lock.sh. Builds a throwaway git repository,
# runs the lock against one branch per scenario and compares exit code and key
# output lines. Exits non-zero if any scenario behaves wrongly.
#
#   bash scripts/test-spec-lock.sh
#   LOCK=/path/to/other-lock.sh bash scripts/test-spec-lock.sh   # test another copy
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOCK=${LOCK:-$here/spec-lock.sh}
[ -f "$LOCK" ] || { echo "test-spec-lock: lock script not found: $LOCK" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
git init -q -b main .
git config user.email test@example.invalid
git config user.name test
git config commit.gpgsign false

mkdir -p openspec/changes/demo/specs/cap openspec/specs/cap scripts src
echo proposal > openspec/changes/demo/proposal.md
echo design > openspec/changes/demo/design.md
printf -- '- [ ] 1.1 task\n' > openspec/changes/demo/tasks.md
echo delta > openspec/changes/demo/specs/cap/spec.md
echo main-spec > openspec/specs/cap/spec.md
: > openspec/specs/.gitkeep
echo code > src/app.txt
git add -A
git commit -q -m base
base=$(git rev-parse HEAD)

failures=0

# scenario <name> <expected-exit> <expected-output-regex> <mutation-function>
scenario() {
  local name=$1 want_exit=$2 want_out=$3 mutate=$4 out got
  git checkout -q -b "scenario-$RANDOM" "$base"
  "$mutate"
  git add -A
  git commit -q -m "scenario: $name"
  set +e
  out=$(BASE=$base bash "$LOCK" 2>&1)
  got=$?
  set -e
  if [ "$got" = "$want_exit" ] && grep -Eq -- "$want_out" <<<"$out"; then
    echo "ok   - $name (exit $got)"
  else
    echo "FAIL - $name: expected exit $want_exit and /$want_out/, got exit $got"
    sed 's/^/       | /' <<<"$out"
    failures=$((failures + 1))
  fi
  git checkout -q main
}

m_spec_only()    { echo more >> openspec/changes/demo/proposal.md; echo new > openspec/changes/demo/specs/cap/extra.md; }
m_tick_tasks()   { echo code2 >> src/app.txt; sed -i 's/\[ \]/[x]/' openspec/changes/demo/tasks.md; }
m_edit_proposal(){ echo code2 >> src/app.txt; echo edit >> openspec/changes/demo/proposal.md; }
m_edit_delta()   { echo code2 >> src/app.txt; echo edit >> openspec/changes/demo/specs/cap/spec.md; }
m_edit_main()    { echo code2 >> src/app.txt; echo edit >> openspec/specs/cap/spec.md; }
m_config_note()  { echo '{}' > tsconfig.json; }
m_gitkeep()      { echo code2 >> src/app.txt; echo x >> openspec/specs/.gitkeep; }

scenario "spec-only PR passes"                       0 'spec-lock: PASS'                    m_spec_only
scenario "ticking tasks.md passes"                   0 'spec-lock: PASS'                    m_tick_tasks
scenario "editing proposal.md alongside code fails"  1 'spec-lock: FAIL'     m_edit_proposal
scenario "editing a delta spec alongside code fails" 1 'spec-lock: FAIL'                    m_edit_delta
scenario "editing openspec/specs alongside code fails" 1 'spec-lock: FAIL'                  m_edit_main
scenario "config change passes with a NOTE"          0 'spec-lock: NOTE'   m_config_note
scenario ".gitkeep edit is ignored"                  0 'spec-lock: PASS'                    m_gitkeep

if [ "$failures" -ne 0 ]; then
  echo "test-spec-lock: $failures scenario(s) failed"
  exit 1
fi
echo "test-spec-lock: all 7 scenarios behave"
