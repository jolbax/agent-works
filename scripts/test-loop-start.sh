#!/usr/bin/env bash
# Simulation test for scripts/loop-start.sh. Uses fake gh, git, orca-ide and
# loop-launch.sh (nothing reaches GitHub or Orca, no worker is launched) and a
# wrapper around the real loop-prompt.sh, to drive every launcher scenario.
# Checks the exit code, the prompt keys, the launch arguments, which calls were
# made and key output. Exits non-zero on any mismatch.
#
#   bash scripts/test-loop-start.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HELPER=${HELPER:-$here/loop-start.sh}
[ -f "$HELPER" ] || { echo "test-loop-start: helper not found: $HELPER" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
FIX=$work/fix LOG=$work/log
SPEC_SHA=abc1234def5678901234567890abcdef12345678
HEAD_SHA=a1b2c3d4e5f60718293a4b5c6d7e8f9012345678

# Fake gh. Reads fixtures from $FIX; every call is appended to $LOG.
#   repo.json            gh repo view (missing file: the call fails)
#   prs.json             gh pr list --state all (unfiltered: the launcher must match titles exactly)
#   open.json            gh pr list --state open
#   pr-<N>.json          gh pr view <N> (missing: "Could not resolve")
#   view-<N>.json        gh pr view <N> --json headRefOid,... (status)
#   issue-<N>.json       gh issue view <N> (missing: "Could not resolve")
cat > "$work/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$LOG"
case "$1 $2" in
  "repo view") [ -f "$FIX/repo.json" ] || { echo "HTTP 502" >&2; exit 1; }; cat "$FIX/repo.json" ;;
  "pr list") if [[ " $* " == *" --state all "* ]]; then cat "$FIX/prs.json"; else cat "$FIX/open.json"; fi ;;
  "pr view")
    if [[ "$*" == *headRefOid* ]]; then cat "$FIX/view-$3.json"
    elif [ -f "$FIX/pr-$3.json" ]; then cat "$FIX/pr-$3.json"
    else echo "GraphQL: Could not resolve to a PullRequest with the number of $3. (repository.pullRequest)" >&2; exit 1; fi ;;
  "issue view")
    [ -f "$FIX/issue-$3.json" ] || { echo "GraphQL: Could not resolve to an issue or pull request with the number of $3." >&2; exit 1; }
    cat "$FIX/issue-$3.json" ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
STUB

# Fake git: fetch succeeds, the main worktree is /fake/agent-works, branches from $FIX/refs.
cat > "$work/git" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "$LOG"
case "$1" in
  fetch) exit 0 ;;
  rev-parse) echo /fake/agent-works/.git ;;
  for-each-ref) cat "$FIX/refs" 2>/dev/null || true ;;
  *) echo "unexpected git call: $*" >&2; exit 1 ;;
esac
STUB

# Fake orca-ide: `worktree list` prints $FIX/worktrees.json; anything else is recorded and fails.
cat > "$work/orca-ide" <<'STUB'
#!/usr/bin/env bash
echo "orca-ide $*" >> "$LOG"
case "$1 $2" in
  "worktree list") cat "$FIX/worktrees.json" ;;
  *) echo "unexpected orca-ide call: $*" >&2; exit 1 ;;
esac
STUB

# loop-prompt.sh wrapper: records the keys, then runs the real helper (PROMPT_FAIL=1: refuses).
cat > "$work/loop-prompt.sh" <<STUB
#!/usr/bin/env bash
echo "prompt \$*" >> "\$LOG"
[ "\${PROMPT_FAIL:-0}" = 1 ] && { echo "loop-prompt: unfilled launch-time placeholder <x>" >&2; exit 1; }
exec bash "$here/loop-prompt.sh" "\$@"
STUB

# Fake loop-launch.sh (LAUNCH_FAIL=1: exits 4 as after a failed resend).
cat > "$work/loop-launch.sh" <<'STUB'
#!/usr/bin/env bash
echo "launch $*" >> "$LOG"
[ "${LAUNCH_FAIL:-0}" = 1 ] && { echo "loop-launch: resend did not reach turn_started; handle=term_stub" >&2; exit 4; }
echo "handle=term_stub stage=screen_activity"
STUB
chmod +x "$work/gh" "$work/git" "$work/orca-ide"

# pr <number> <title> <state> [refs-issue] [head-branch]: one PR object.
pr() {
  local merged=null commit=null body="Summary"
  [ "$3" != MERGED ] || { merged="\"2026-10-0$(( $1 % 9 + 1 ))T10:00:00Z\""; commit="{\"oid\":\"$SPEC_SHA\"}"; }
  [ -z "${4:-}" ] || body="Summary\\n\\nRefs #$4"
  printf '{"number":%s,"title":"%s","state":"%s","mergedAt":%s,"mergeCommit":%s,"headRefName":"%s","body":"%s"}' \
    "$1" "$2" "$3" "$merged" "$commit" "${5:-jolbax/x}" "$body"
}
# wt <name> <status> [comment] [activity]: one Orca worktree row.
wt() { printf '{"path":"/fake/ws/%s","isMainWorktree":false,"workspaceStatus":"%s","comment":"%s","lastActivityAt":%s}' "$1" "$2" "${3:-}" "${4:-0}"; }
join() { local IFS=,; echo "[$*]"; }

# fresh: new fixtures with one GitHub repo, the main worktree and no branches.
fresh() {
  rm -rf "$FIX"; mkdir -p "$FIX"; : > "$LOG"
  echo '{"nameWithOwner":"acme/widgets","defaultBranchRef":{"name":"main"}}' > "$FIX/repo.json"
  echo '[]' > "$FIX/prs.json"; echo '[]' > "$FIX/open.json"
  worktrees
}
# worktrees [row...]: the Orca worktree list (the main worktree is always present).
worktrees() {
  local main='{"path":"/fake/agent-works","isMainWorktree":true,"workspaceStatus":"in-progress","comment":"","lastActivityAt":0}'
  printf '{"ok":true,"result":{"worktrees":%s,"truncated":false}}' "$(join "$main" "$@")" > "$FIX/worktrees.json"
}
prs() { join "$@" > "$FIX/prs.json"; }

fail=0 out="" rc=0
# run <args...>: run the launcher against the stubs; sets $out and $rc.
run() {
  rc=0
  out=$(LOG=$LOG FIX=$FIX GH=$work/gh GIT=$work/git ORCA_IDE=$work/orca-ide \
        LOOP_PROMPT=$work/loop-prompt.sh LOOP_LAUNCH=$work/loop-launch.sh TMPDIR=$work \
        bash "$HELPER" "$@" 2>&1) || rc=$?
}
# check <scenario> <want-exit> [has:<text>|not:<text>|log:<text>|nolog:<text>|lines:<n> ...]
#   has/not search the output, log/nolog the call log; lines: number of log lines.
check() {
  local name=$1 want=$2 ok=1 a; shift 2
  [ "$rc" = "$want" ] || ok=0
  for a in "$@"; do
    case "$a" in
      has:*) grep -qF -- "${a#has:}" <<<"$out" || ok=0 ;;
      not:*) ! grep -qF -- "${a#not:}" <<<"$out" || ok=0 ;;
      log:*) grep -qF -- "${a#log:}" "$LOG" || ok=0 ;;
      nolog:*) ! grep -qF -- "${a#nolog:}" "$LOG" || ok=0 ;;
      lines:*) [ "$(wc -l < "$LOG")" = "${a#lines:}" ] || ok=0 ;;
    esac
    [ "$ok" = 1 ] || { echo "FAIL $name: exit $rc (want $want), failed on '$a'; output:"; sed 's/^/    /' <<<"$out"; echo "  log:"; sed 's/^/    /' "$LOG"; fail=1; return 0; }
  done
  echo "PASS $name (exit $rc)"
}

# --- Launcher derives launch-time values from GitHub ---
fresh; prs "$(pr 22 "spec: add-foo" MERGED 31)" "$(pr 23 "spec: add-foo-bar" MERGED 32)"
run implement add-foo
check "implement derives the spec PR" 0 log:"git fetch origin" \
  log:"change-name=add-foo issue-number=31 spec-pr-number=22 spec-merge-commit=$SPEC_SHA default-branch=main" \
  log:"launch add-foo-impl claude $work/loop-start-add-foo-impl." log:"--base-branch origin/main --issue 31"
check "output after launch" 0 has:"worker: add-foo-impl" has:"terminal: term_stub" has:"next: " has:"approve <sha>' and 'fix' in the worker's own terminal"

fresh; prs "$(pr 40 "impl: add-foo" MERGED 31)"
run archive add-foo
check "archive derives the implementation PR" 0 log:"owner=acme repo=widgets change-name=add-foo issue-number=31 impl-pr-number=40" \
  log:"launch add-foo-archive claude" log:"--base-branch origin/main --issue 31"

fresh; pr 40 "impl: add-foo" OPEN 31 jolbax/add-foo-impl > "$FIX/pr-40.json"
run judge 40
check "judge derives the change from the PR" 0 log:"change-name=add-foo pr-number=40" \
  log:"launch add-foo-judge codex" log:"--base-branch origin/jolbax/add-foo-impl --issue 31" nolog:"gh pr list"

fresh; prs "$(pr 20 "spec: add-foo" MERGED 30)" "$(pr 22 "spec: add-foo" MERGED 31)" "$(pr 24 "spec: add-foo" CLOSED 31)" "$(pr 25 "spec: add-foo-x" MERGED 9)"
run implement add-foo
check "several PRs match a title" 0 log:"spec-pr-number=22" has:"#20 (MERGED)" has:"#24 (CLOSED)" not:"#25"

fresh; prs "$(pr 22 "spec: add-foo" MERGED 31)"
PROMPT_FAIL=1 run implement add-foo
check "prompt builder refuses" 1 has:"loop-prompt.sh refused" log:"prompt " nolog:"launch "
unset PROMPT_FAIL

# --- Launcher uses the documented worker layout ---
fresh
run start add-foo --brief "add a foo"
check "start with a brief" 0 log:"brief=add a foo" log:"launch add-foo claude" log:"--base-branch origin/main" nolog:"--issue" nolog:"gh issue view"

fresh; echo '{"state":"OPEN","url":"https://github.com/acme/widgets/issues/31"}' > "$FIX/issue-31.json"
run start add-foo --issue 31
check "start from an issue" 0 log:"issue-number=31" log:"launch add-foo claude" log:"--base-branch origin/main --issue 31" nolog:"brief="

fresh; worktrees "$(wt add-foo-judge completed)" "$(wt add-foo-judge-2 completed)"
pr 40 "impl: add-foo" OPEN 31 jolbax/add-foo-impl > "$FIX/pr-40.json"
run judge 40
check "next free judge number" 0 log:"launch add-foo-judge-3 codex"

fresh; prs "$(pr 22 "spec: add-foo" MERGED 31)"
LAUNCH_FAIL=1 run implement add-foo
check "launch fails after the worktree exists" 1 has:"loop-launch.sh exited 4" has:"Not retried, not removed" has:"orca-ide terminal read" \
  nolog:"orca-ide worktree rm" nolog:"orca-ide worktree remove" nolog:"orca-ide terminal"
[ "$(grep -c '^launch ' "$LOG")" = 1 ] || { echo "FAIL launch fails after the worktree exists: launched more than once"; fail=1; }
unset LAUNCH_FAIL

# --- Launcher refuses what it cannot derive ---
fresh; prs "$(pr 22 "spec: add-foo" OPEN 31)"
run implement add-foo
check "implement before the spec merged (open)" 3 has:"'spec: add-foo'" has:"#22 (OPEN)" nolog:"prompt " nolog:"launch "
fresh
run implement add-foo
check "implement before the spec merged (none)" 3 has:"'spec: add-foo'" nolog:"launch "

for case in CLOSED MERGED missing title; do
  fresh
  case $case in
    missing) ;;
    title) pr 40 "spec: add-foo" OPEN 31 > "$FIX/pr-40.json" ;;
    *) pr 40 "impl: add-foo" "$case" 31 > "$FIX/pr-40.json" ;;
  esac
  run judge 40
  check "judge on a PR that is not an open implementation PR ($case)" 4 nolog:"prompt " nolog:"launch "
done

for case in OPEN CLOSED absent; do
  fresh; [ "$case" = absent ] || prs "$(pr 40 "impl: add-foo" "$case" 31)"
  run archive add-foo
  check "archive before the implementation merged ($case)" 5 nolog:"launch "
done

fresh; prs "$(pr 22 "spec: add-foo" MERGED)"
run implement add-foo
check "merged PR without an issue reference (implement)" 3 has:"Refs" nolog:"launch "
fresh; prs "$(pr 40 "impl: add-foo" MERGED)"
run archive add-foo
check "merged PR without an issue reference (archive)" 5 has:"Refs" nolog:"launch "

for case in worktree local origin-prefixed; do
  fresh; prs "$(pr 22 "spec: add-foo" MERGED 31)"
  case $case in
    worktree) worktrees "$(wt add-foo-impl completed)" ;;
    local) echo refs/heads/add-foo-impl > "$FIX/refs" ;;
    origin-prefixed) echo refs/remotes/origin/jolbax/add-foo-impl > "$FIX/refs" ;;
  esac
  run implement add-foo
  check "name already taken ($case)" 6 has:"add-foo-impl" nolog:"prompt " nolog:"launch "
done
fresh; echo refs/heads/jolbax/add-foo-impl-old > "$FIX/refs"; prs "$(pr 22 "spec: add-foo" MERGED 31)"
run implement add-foo
check "similar branch name is not taken" 0 log:"launch add-foo-impl"

fresh
run start add-foo --issue 31
check "issue not usable (missing)" 7 nolog:"launch "
fresh; echo '{"state":"CLOSED","url":"https://github.com/acme/widgets/issues/31"}' > "$FIX/issue-31.json"
run start add-foo --issue 31
check "issue not usable (closed)" 7 nolog:"launch "
fresh; echo '{"state":"OPEN","url":"https://github.com/acme/widgets/pull/31"}' > "$FIX/issue-31.json"
run start add-foo --issue 31
check "issue not usable (a pull request)" 7 nolog:"launch "

usage_cases=(
  "" "frobnicate add-foo" "start" "start add-foo" "start add-foo --brief x --issue 3"
  "start add-foo --issue x" "implement" "implement Add_Foo" "archive add-foo extra" "judge abc" "status extra"
)
for args in "${usage_cases[@]}"; do
  fresh; : > "$LOG"
  # shellcheck disable=SC2086
  run $args
  check "usage error: '${args}'" 2 lines:0
done

fresh; rm "$FIX/repo.json"
run implement add-foo
check "gh call fails" 1 has:"gh repo view failed" nolog:"launch "

# --- Launcher dry run launches nothing ---
fresh; prs "$(pr 22 "spec: add-foo" MERGED 31)"
run --dry-run implement add-foo
promptfile=$(sed -n 's/^prompt: //p' <<<"$out")
check "dry run of implement" 0 has:"prompt: $work/" has:"launch (dry run, not run): bash scripts/loop-launch.sh add-foo-impl claude" \
  has:"--base-branch origin/main --issue 31" log:"prompt " nolog:"launch "
if [ -z "$promptfile" ] || [ ! -s "$promptfile" ] || grep -qE '<[a-z][a-z0-9-]*>' "$promptfile"; then
  echo "FAIL dry run of implement: prompt file missing, empty or with a <name> token: $promptfile"; fail=1
else
  echo "PASS dry run prompt has no <name> token"
fi
fresh
run --dry-run implement add-foo
check "dry run still refuses" 3 nolog:"prompt "

# --- Status names where the operator acts ---
fresh
worktrees "$(wt add-foo in-review "PR #14 at a1b2c3d: review, then type: approve a1b2c3d" 5)" \
  "$(wt add-bar-impl in-progress "implement: add-bar" 4)" "$(wt add-baz-impl completed "merged 1234567" 3)" \
  "$(wt add-qux-judge in-progress "" 2)"
join '{"number":14,"title":"spec: add-foo","headRefName":"jolbax/add-foo"}' \
     '{"number":40,"title":"impl: add-bar","headRefName":"jolbax/add-bar-impl"}' \
     '{"number":41,"title":"impl: add-old","headRefName":"jolbax/add-old-impl"}' \
     '{"number":42,"title":"impl: add-pass","headRefName":"jolbax/add-pass-impl"}' \
     '{"number":43,"title":"impl: add-qux","headRefName":"jolbax/add-qux-impl"}' \
     '{"number":50,"title":"chore: unrelated","headRefName":"jolbax/x"}' > "$FIX/open.json"
check_ok='[{"__typename":"CheckRun","name":"openspec","status":"COMPLETED","conclusion":"SUCCESS"}]'
view() { printf '{"headRefOid":"%s","statusCheckRollup":%s,"comments":%s}' "$HEAD_SHA" "$2" "$3" > "$FIX/view-$1.json"; }
view 14 "$check_ok" '[]'
view 40 '[]' '[]'
view 41 "$check_ok" '[{"createdAt":"2026-10-20T10:00:00Z","body":"Verdict: PASS at 0000000"}]'
view 42 "$check_ok" '[{"createdAt":"2026-10-20T10:00:00Z","body":"Verdict: PASS at a1b2c3d\n\ndetails"}]'
view 43 "$check_ok" '[]'
run status
check "worker waits for the operator" 0 has:"ACT in the terminal of add-foo: PR #14 at a1b2c3d: review, then type: approve a1b2c3d" \
  has:"add-bar-impl  [in-progress]" not:"add-baz-impl" has:"1 completed not listed" not:"agent-works  [" has:"approve <sha>' and 'fix'"
check "implementation PR without a verdict at its head" 0 has:"ACT: judge it with /sdd-loop judge 40" has:"ACT: judge it with /sdd-loop judge 41" \
  not:"judge 42" not:"judge 14" not:"#50" has:"openspec: missing" has:"not at head a1b2c3d"
check "judge in progress is not suggested again" 0 not:"judge 43 " has:"judge add-qux-judge in progress"
bad=$(grep -vE '^(orca-ide worktree list |gh pr list --state open |gh pr view [0-9]+ --json headRefOid,statusCheckRollup,comments$|git rev-parse )' "$LOG" || true)
if [ -z "$bad" ]; then echo "PASS status is read only"; else echo "FAIL status is read only: unexpected calls:"; sed 's/^/    /' <<<"$bad"; fail=1; fi

[ "$fail" = 0 ] && echo "test-loop-start: all scenarios passed (simulation)" || { echo "test-loop-start: FAILED" >&2; exit 1; }
